import Foundation

/// Measures one transfer (download or upload) for at most `timeout` seconds.
final class SpeedProbe: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private var bytes: Int64 = 0
  private var firstChunk: Int64 = 0
  private var firstDataAt: Date?
  private var started = Date()
  private var continuation: CheckedContinuation<Void, Never>?
  private let onLive: @Sendable (Double) -> Void

  init(onLive: @escaping @Sendable (Double) -> Void) { self.onLive = onLive }

  static func mbps(bytes: Int64, seconds: Double) -> Double {
    seconds > 0 ? Double(bytes) * 8 / seconds / 1_000_000 : 0
  }

  /// Returns megabits per second, or nil if nothing was transferred.
  func run(request: URLRequest, body: Data?, timeout: TimeInterval) async -> Double? {
    let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let task =
      body.map { session.uploadTask(with: request, from: $0) } ?? session.dataTask(with: request)
    await withTaskCancellationHandler {
      await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
        lock.lock()
        continuation = c
        started = Date()
        lock.unlock()
        task.resume()
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { task.cancel() }
      }
    } onCancel: {
      task.cancel()
    }
    return result()
  }

  private func result() -> Double? {
    lock.lock()
    defer { lock.unlock() }
    guard bytes > 0 else { return nil }
    // Downloads are timed from the first byte so connection setup doesn't skew the result.
    if let t0 = firstDataAt, bytes > firstChunk {
      return Self.mbps(bytes: bytes - firstChunk, seconds: Date().timeIntervalSince(t0))
    }
    return Self.mbps(bytes: bytes, seconds: Date().timeIntervalSince(started))
  }

  func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    lock.lock()
    if firstDataAt == nil {
      firstDataAt = Date()
      firstChunk = Int64(data.count)
    }
    bytes += Int64(data.count)
    let live = Self.mbps(
      bytes: bytes - firstChunk, seconds: Date().timeIntervalSince(firstDataAt ?? started))
    lock.unlock()
    onLive(live)
  }

  func urlSession(
    _ s: URLSession, task: URLSessionTask, didSendBodyData n: Int64, totalBytesSent t: Int64,
    totalBytesExpectedToSend e: Int64
  ) {
    lock.lock()
    bytes = t
    let live = Self.mbps(bytes: t, seconds: Date().timeIntervalSince(started))
    lock.unlock()
    onLive(live)
  }

  func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    lock.lock()
    let c = continuation
    continuation = nil
    lock.unlock()
    c?.resume()
  }
}
