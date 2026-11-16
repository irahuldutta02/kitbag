import Foundation

/// Downloads one file, reports progress, and refuses to follow a redirect to anywhere but GitHub.
final class UpdateDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  private var continuation: CheckedContinuation<URL, Error>?
  private var session: URLSession?
  private let destination: URL
  private let progress: @Sendable (Double) -> Void
  private let maxBytes: Int64

  private init(destination: URL, maxBytes: Int64, progress: @escaping @Sendable (Double) -> Void) {
    self.destination = destination
    self.maxBytes = maxBytes
    self.progress = progress
  }

  static func fetch(
    _ url: URL, to destination: URL, maxBytes: Int64 = 600 * 1024 * 1024,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> URL {
    guard UpdateTrust.isTrusted(url) else { throw UpdateError.untrustedURL(url.host ?? url.absoluteString) }
    let job = UpdateDownload(destination: destination, maxBytes: maxBytes, progress: progress)
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { cont in
        job.continuation = cont
        let session = URLSession(configuration: .ephemeral, delegate: job, delegateQueue: nil)
        job.session = session
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("Kitbag-Updater", forHTTPHeaderField: "User-Agent")  // a generic name; nothing about you
        session.downloadTask(with: request).resume()
      }
    } onCancel: { job.session?.invalidateAndCancel() }
  }

  private func finish(_ result: Result<URL, Error>) {
    guard let c = continuation else { return }
    continuation = nil
    session?.finishTasksAndInvalidate()
    session = nil
    c.resume(with: result)
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
  ) {
    if let u = request.url, UpdateTrust.isTrusted(u) { completionHandler(request) } else {
      completionHandler(nil)
      finish(.failure(UpdateError.untrustedURL(request.url?.host ?? "unknown")))
    }
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    if totalBytesWritten > maxBytes {
      downloadTask.cancel()
      finish(.failure(UpdateError.badRelease("the download is far larger than expected.")))
      return
    }
    if totalBytesExpectedToWrite > 0 { progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      return finish(.failure(UpdateError.network("GitHub answered \(http.statusCode).")))
    }
    do {  // the temporary file disappears when this returns, so move it now
      try? FileManager.default.removeItem(at: destination)
      try FileManager.default.moveItem(at: location, to: destination)
      finish(.success(destination))
    } catch { finish(.failure(UpdateError.network(error.localizedDescription))) }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error { finish(.failure(UpdateError.network(error.localizedDescription))) }
  }
}
