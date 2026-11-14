import Foundation

@MainActor
final class SpeedTestModel: ObservableObject {
  enum Phase: Equatable { case idle, ping, download, upload, done, failed }

  // Cloudflare's public speed test endpoints; no account or personal data is sent.
  static let downURL = "https://speed.cloudflare.com/__down?bytes="
  static let upURL = "https://speed.cloudflare.com/__up"
  static let phaseSeconds: TimeInterval = 6

  @Published private(set) var phase: Phase = .idle
  @Published private(set) var ping: Double?  // ms
  @Published private(set) var download: Double?  // Mbps
  @Published private(set) var upload: Double?
  @Published private(set) var live: Double = 0

  private var task: Task<Void, Never>?

  var isRunning: Bool { [.ping, .download, .upload].contains(phase) }

  /// Runs only when asked; nothing touches the network otherwise.
  func start() {
    guard !isRunning else { return }
    ping = nil
    download = nil
    upload = nil
    live = 0
    task = Task { await run() }
  }

  func cancel() {
    task?.cancel()
    task = nil
    if isRunning { phase = .idle }
  }

  /// Stops any run and forgets all results (used when leaving the tab).
  func reset() {
    cancel()
    phase = .idle
    ping = nil
    download = nil
    upload = nil
    live = 0
  }

  private func run() async {
    phase = .ping
    guard let p = await Self.measurePing() else { return fail() }
    ping = p
    if Task.isCancelled { return }

    phase = .download
    live = 0
    var req = URLRequest(url: URL(string: Self.downURL + "50000000")!)
    req.cachePolicy = .reloadIgnoringLocalCacheData
    let down = await SpeedProbe { [weak self] v in Task { @MainActor in self?.live = v } }
      .run(request: req, body: nil, timeout: Self.phaseSeconds)
    guard let d = down else { return Task.isCancelled ? () : fail() }
    download = d
    if Task.isCancelled { return }

    phase = .upload
    live = 0
    var up = URLRequest(url: URL(string: Self.upURL)!)
    up.httpMethod = "POST"
    let body = Data(count: 25_000_000)  // released when this function returns
    let u = await SpeedProbe { [weak self] v in Task { @MainActor in self?.live = v } }
      .run(request: up, body: body, timeout: Self.phaseSeconds)
    guard let u else { return Task.isCancelled ? () : fail() }
    upload = u
    live = 0
    phase = .done
  }

  private func fail() { phase = .failed }

  /// Median of three small requests, after one warm-up that pays for the TLS handshake.
  private static func measurePing() async -> Double? {
    let session = URLSession(configuration: .ephemeral)
    defer { session.invalidateAndCancel() }
    guard let url = URL(string: downURL + "0") else { return nil }
    var times: [Double] = []
    for i in 0..<4 {
      if Task.isCancelled { return nil }
      let t0 = Date()
      guard (try? await session.data(from: url)) != nil else { return nil }
      if i > 0 { times.append(Date().timeIntervalSince(t0) * 1000) }
    }
    return times.sorted()[1]
  }
}
