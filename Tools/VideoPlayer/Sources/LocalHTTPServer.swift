import Foundation
import Network
import KitbagCore

// MARK: - Server Callbacks & Status

public struct ServerStats: Equatable, Sendable {
  public let isRunning: Bool
  public let port: UInt16
  public let clientCount: Int
  public let activeStreams: Int

  public static let stopped = ServerStats(isRunning: false, port: 0, clientCount: 0, activeStreams: 0)
}

public protocol LocalVideoServerDelegate: AnyObject, Sendable {
  func serverConfigSnapshot() -> VideoPlayerConfigSnapshot
  func serverApplyConfigPatch(_ patch: WebConfigPatch) -> VideoPlayerConfigSnapshot
  func serverRecents() -> [RecentVideo]
  func serverRecordProgress(path: String, position: Double, duration: Double)
  func serverPickFile(kind: String) async -> String?
  func serverStatsChanged(_ stats: ServerStats)
  func serverDidAutoStop()
}

// MARK: - Active Video Stream Session

private final class StreamSession: @unchecked Sendable {
  let id: UUID
  private let lock = NSLock()
  private var cancelled = false
  private var process: Process?
  private var readHandle: FileHandle?
  private var connection: NWConnection?
  private let onFinish: @Sendable () -> Void
  private var finished = false
  /// Byte-range mode (Safari): `rangeStart` is the first byte asked for. The body is sent raw with a
  /// huge fake Content-Length instead of chunked, and the leading `rangeStart` bytes are skipped.
  var rangeStart: Int?
  private var toSkip = 0
  static let fakeTotal = 1 << 40

  init(id: UUID = UUID(), connection: NWConnection, onFinish: @escaping @Sendable () -> Void) {
    self.id = id
    self.connection = connection
    self.onFinish = onFinish
  }

  func start(ffmpegPath: String, arguments: [String]) {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: ffmpegPath)
    proc.arguments = arguments
    proc.standardInput = FileHandle.nullDevice
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice

    lock.lock()
    if cancelled {
      lock.unlock()
      finish()
      return
    }
    self.process = proc
    self.readHandle = pipe.fileHandleForReading
    let conn = self.connection
    lock.unlock()

    do {
      try proc.run()
      try? pipe.fileHandleForWriting.close()
    } catch {
      cancel()
      return
    }

    guard let conn else {
      cancel()
      return
    }

    // Watch for client disconnect (FIN/RST) while streaming so ffmpeg stops immediately on seek/close.
    armDisconnectWatcher(on: conn)

    let header: String
    if let s = rangeStart {
      toSkip = s
      let total = Self.fakeTotal
      header =
        "HTTP/1.1 206 Partial Content\r\n"
        + "Content-Type: video/mp4\r\n"
        + "Accept-Ranges: bytes\r\n"
        + "Content-Range: bytes \(s)-\(total - 1)/\(total)\r\n"
        + "Content-Length: \(total - s)\r\n"
        + "Cache-Control: no-store\r\n"
        + "Connection: close\r\n\r\n"
    } else {
      header =
        "HTTP/1.1 200 OK\r\n"
        + "Content-Type: video/mp4\r\n"
        + "Cache-Control: no-store\r\n"
        + "Transfer-Encoding: chunked\r\n"
        + "Connection: close\r\n\r\n"
    }

    conn.send(
      content: Data(header.utf8),
      completion: .contentProcessed { [weak self] err in
        guard let self else { return }
        if err != nil {
          self.cancel()
          return
        }
        DispatchQueue.global(qos: .userInitiated).async {
          self.pumpNextChunk()
        }
      })
  }

  private func armDisconnectWatcher(on conn: NWConnection) {
    conn.receive(minimumIncompleteLength: 1, maximumLength: 256) { [weak self] _, _, isComplete, err in
      guard let self else { return }
      if isComplete || err != nil {
        self.cancel()
      } else if !self.isCancelled {
        self.armDisconnectWatcher(on: conn)
      }
    }
  }

  private var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }

  private func pumpNextChunk() {
    lock.lock()
    if cancelled {
      lock.unlock()
      return
    }
    guard let handle = readHandle, let conn = connection else {
      lock.unlock()
      cancel()
      return
    }
    lock.unlock()

    let chunk: Data
    do {
      guard let data = try handle.read(upToCount: 65_536), !data.isEmpty else {
        // EOF from ffmpeg — send final zero-length chunk with isComplete so client sees clean EOF
        conn.send(
          content: rangeStart == nil ? Data("0\r\n\r\n".utf8) : nil,
          contentContext: .defaultMessage,
          isComplete: true,
          completion: .contentProcessed { [weak self] _ in
            conn.cancel()
            self?.finish()
          })
        return
      }
      chunk = data
    } catch {
      cancel()
      return
    }

    var framed = Data(capacity: chunk.count + 16)
    if rangeStart != nil {
      if toSkip >= chunk.count {
        toSkip -= chunk.count
        DispatchQueue.global(qos: .userInitiated).async { self.pumpNextChunk() }
        return
      }
      framed.append(chunk.dropFirst(toSkip))
      toSkip = 0
    } else {
      framed.append(contentsOf: String(format: "%x\r\n", chunk.count).utf8)
      framed.append(chunk)
      framed.append(contentsOf: "\r\n".utf8)
    }

    conn.send(
      content: framed,
      completion: .contentProcessed { [weak self] err in
        guard let self else { return }
        if err != nil || self.isCancelled {
          self.cancel()
          return
        }
        DispatchQueue.global(qos: .userInitiated).async {
          self.pumpNextChunk()
        }
      })
  }

  func cancel() {
    lock.lock()
    if cancelled {
      lock.unlock()
      return
    }
    cancelled = true
    let proc = process
    let handle = readHandle
    let conn = connection
    process = nil
    readHandle = nil
    connection = nil
    lock.unlock()

    if let proc, proc.isRunning {
      kill(proc.processIdentifier, SIGKILL)
    }
    try? handle?.close()
    conn?.cancel()
    finish()
  }

  private func finish() {
    lock.lock()
    if finished {
      lock.unlock()
      return
    }
    finished = true
    let proc = process
    let handle = readHandle
    process = nil
    readHandle = nil
    connection = nil
    lock.unlock()

    if let proc, proc.isRunning {
      kill(proc.processIdentifier, SIGKILL)
    }
    try? handle?.close()
    onFinish()
  }
}

// MARK: - HTTP Request Parser

private struct HTTPRequest {
  let method: String
  let target: String
  let headers: [String: String]
  let body: Data
}

// MARK: - Pure Swift Local HTTP Server (127.0.0.1 only)

public final class LocalHTTPServer: @unchecked Sendable {
  private let queue = DispatchQueue(label: "com.irahuldutta.kitbag.videoplayer.http", qos: .userInitiated)
  private let stateLock = NSLock()
  private var listener: NWListener?
  private var boundPort: UInt16 = 0
  private var clients: [String: Date] = [:]
  private var activeSessions: [UUID: StreamSession] = [:]
  private var autoStopWork: DispatchWorkItem?
  private var pruneTimer: DispatchSourceTimer?
  private var startedAt = Date.distantPast
  private var isStopped = true

  private let engine: VideoMediaEngine
  private weak var delegate: LocalVideoServerDelegate?

  public init(engine: VideoMediaEngine, delegate: LocalVideoServerDelegate) {
    self.engine = engine
    self.delegate = delegate
  }

  public var currentPort: UInt16 {
    stateLock.lock()
    defer { stateLock.unlock() }
    return boundPort
  }

  public var isRunning: Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    return !isStopped && listener != nil
  }

  public func start(port: UInt16) async throws -> UInt16 {
    stop()

    let params = NWParameters.tcp
    params.allowLocalEndpointReuse = true
    let nwPort: NWEndpoint.Port = port == 0 ? .any : (NWEndpoint.Port(rawValue: port) ?? .any)
    params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)

    let newListener = try NWListener(using: params)

    let actualPort: UInt16 = try await withCheckedThrowingContinuation { cont in
      final class OnceFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func claim() -> Bool {
          lock.lock()
          defer { lock.unlock() }
          guard !done else { return false }
          done = true
          return true
        }
      }
      let once = OnceFlag()

      newListener.stateUpdateHandler = { [weak self] state in
        switch state {
        case .ready:
          let p = newListener.port?.rawValue ?? port
          self?.stateLock.lock()
          self?.listener = newListener
          self?.boundPort = p
          self?.isStopped = false
          self?.startedAt = Date()
          self?.stateLock.unlock()
          self?.startPruneTimer()
          self?.notifyStats()
          if once.claim() {
            cont.resume(returning: p)
          }
        case .failed(let err):
          newListener.cancel()
          if once.claim() {
            cont.resume(throwing: err)
          }
          self?.stop()
        case .cancelled:
          if once.claim() {
            cont.resume(throwing: CancellationError())
          }
        default:
          break
        }
      }

      newListener.newConnectionHandler = { [weak self] conn in
        self?.handleConnection(conn)
      }

      newListener.start(queue: self.queue)
    }

    return actualPort
  }

  public func stop() {
    stateLock.lock()
    let wasRunning = !isStopped || listener != nil
    isStopped = true
    let currentListener = listener
    listener = nil
    boundPort = 0
    let sessions = Array(activeSessions.values)
    activeSessions.removeAll()
    clients.removeAll()
    autoStopWork?.cancel()
    autoStopWork = nil
    pruneTimer?.cancel()
    pruneTimer = nil
    stateLock.unlock()

    sessions.forEach { $0.cancel() }
    currentListener?.cancel()
    if wasRunning {
      notifyStats()
    }
  }

  public func scheduleAutoStopIfNeeded(graceSeconds: TimeInterval = 6.0, force: Bool = false) {
    guard let cfg = delegate?.serverConfigSnapshot(),
      cfg.serverMode == ServerMode.onDemand.rawValue
    else { return }

    stateLock.lock()
    guard !isStopped else {
      stateLock.unlock()
      return
    }
    autoStopWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      self?.evaluateAutoStop(force: force)
    }
    autoStopWork = work
    stateLock.unlock()

    queue.asyncAfter(deadline: .now() + graceSeconds, execute: work)
  }

  private func startPruneTimer() {
    stateLock.lock()
    pruneTimer?.cancel()
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + 25, repeating: 25)
    timer.setEventHandler { [weak self] in
      self?.pruneAndCheckAutoStop()
    }
    pruneTimer = timer
    stateLock.unlock()
    timer.resume()
  }

  private func pruneAndCheckAutoStop() {
    let now = Date()
    stateLock.lock()
    guard !isStopped else {
      stateLock.unlock()
      return
    }
    let before = clients.count
    clients = clients.filter { now.timeIntervalSince($0.value) < 90 }
    let changed = clients.count != before
    let empty = clients.isEmpty && activeSessions.isEmpty
    let uptime = now.timeIntervalSince(startedAt)
    stateLock.unlock()

    if changed { notifyStats() }
    if empty && uptime > 45 {
      evaluateAutoStop()
    }
  }

  private func evaluateAutoStop(force: Bool = false) {
    guard let cfg = delegate?.serverConfigSnapshot(),
      cfg.serverMode == ServerMode.onDemand.rawValue
    else { return }

    let now = Date()
    stateLock.lock()
    guard !isStopped else {
      stateLock.unlock()
      return
    }
    clients = clients.filter { now.timeIntervalSince($0.value) < 90 }
    let shouldStop = clients.isEmpty && (force || activeSessions.isEmpty)
    stateLock.unlock()

    if shouldStop {
      stop()
      delegate?.serverDidAutoStop()
    }
  }

  private func notifyStats() {
    stateLock.lock()
    let stats = ServerStats(
      isRunning: !isStopped && listener != nil,
      port: boundPort,
      clientCount: clients.count,
      activeStreams: activeSessions.count
    )
    stateLock.unlock()
    delegate?.serverStatsChanged(stats)
  }

  // MARK: - Connection Handling

  private func handleConnection(_ conn: NWConnection) {
    conn.start(queue: queue)
    readRequest(on: conn, buffer: Data())
  }

  private func readRequest(on conn: NWConnection, buffer: Data) {
    conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
      [weak self] data, _, isComplete, error in
      guard let self else {
        conn.cancel()
        return
      }
      if error != nil {
        conn.cancel()
        return
      }

      var acc = buffer
      if let data, !data.isEmpty {
        acc.append(data)
      }

      if acc.count > 512 * 1024 {
        self.sendJSON(conn, status: 413, body: ["error": "Request too large"])
        return
      }

      let sep = Data("\r\n\r\n".utf8)
      if let headerEnd = acc.range(of: sep) {
        let headerData = acc[..<headerEnd.lowerBound]
        let bodyStart = headerEnd.upperBound
        let headerString = String(decoding: headerData, as: UTF8.self)
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
          conn.cancel()
          return
        }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else {
          conn.cancel()
          return
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
          if let colon = line.firstIndex(of: ":") {
            let k = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let v = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[k] = v
          }
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let availableBody = acc.count - bodyStart
        if availableBody < contentLength && !isComplete {
          self.readRequest(on: conn, buffer: acc)
          return
        }

        let bodyData: Data
        if contentLength > 0 && availableBody >= contentLength {
          bodyData = Data(acc[bodyStart..<(bodyStart + contentLength)])
        } else {
          bodyData = Data(acc[bodyStart...])
        }

        let req = HTTPRequest(method: parts[0], target: parts[1], headers: headers, body: bodyData)
        self.route(req, on: conn)
        return
      }

      if isComplete {
        conn.cancel()
      } else {
        self.readRequest(on: conn, buffer: acc)
      }
    }
  }

  // MARK: - Routing

  private func route(_ req: HTTPRequest, on conn: NWConnection) {
    guard let comps = URLComponents(string: "http://127.0.0.1\(req.target)") else {
      sendJSON(conn, status: 400, body: ["error": "Invalid URL"])
      return
    }
    let path = comps.path
    var query: [String: String] = [:]
    for item in comps.queryItems ?? [] {
      query[item.name] = item.value ?? ""
    }

    switch path {
    case "/":
      let html = PlayerWebUI.html
      sendResponse(
        conn, status: 200, contentType: "text/html; charset=utf-8",
        cacheControl: "no-cache", body: Data(html.utf8))

    case "/assets/favicon.svg":
      sendResponse(
        conn, status: 200, contentType: "image/svg+xml",
        cacheControl: "max-age=3600", body: Data(PlayerWebUI.faviconSVG.utf8))

    case "/api/config":
      if req.method == "POST" {
        if let patch = try? JSONDecoder().decode(WebConfigPatch.self, from: req.body),
          let updated = delegate?.serverApplyConfigPatch(patch)
        {
          sendEncodable(conn, status: 200, value: updated)
        } else {
          sendJSON(conn, status: 400, body: ["error": "Invalid config payload"])
        }
      } else {
        if let snap = delegate?.serverConfigSnapshot() {
          sendEncodable(conn, status: 200, value: snap)
        } else {
          sendJSON(conn, status: 500, body: ["error": "No config available"])
        }
      }

    case "/api/recents":
      let items = delegate?.serverRecents() ?? []
      sendEncodable(conn, status: 200, value: items)

    case "/api/progress":
      struct ProgressPayload: Decodable {
        let path: String
        let position: Double
        let duration: Double
      }
      if let payload = try? JSONDecoder().decode(ProgressPayload.self, from: req.body) {
        delegate?.serverRecordProgress(
          path: payload.path, position: payload.position, duration: payload.duration)
        sendJSON(conn, status: 200, body: ["ok": true])
      } else {
        sendJSON(conn, status: 400, body: ["error": "Invalid progress payload"])
      }

    case "/api/ping":
      let cid = query["id"] ?? "?"
      stateLock.lock()
      clients[cid] = Date()
      autoStopWork?.cancel()
      autoStopWork = nil
      stateLock.unlock()
      notifyStats()
      let ver = delegate?.serverConfigSnapshot().configVersion ?? 1
      struct PingReply: Encodable {
        let ok: Bool
        let configVersion: Int
      }
      sendEncodable(conn, status: 200, value: PingReply(ok: true, configVersion: ver))

    case "/api/bye":
      let cid = query["id"] ?? "?"
      stateLock.lock()
      clients.removeValue(forKey: cid)
      let remaining = clients.count
      stateLock.unlock()
      notifyStats()
      sendEmpty(conn, status: 204)
      if remaining == 0 {
        scheduleAutoStopIfNeeded(graceSeconds: 5.0, force: true)
      }

    case "/api/ls":
      let cfg = delegate?.serverConfigSnapshot()
      let fallback = cfg?.defaultFolder ?? "~/Movies"
      let dirParam = query["dir"]
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let listing = try VideoMediaEngine.listDirectory(
            dirParam?.isEmpty == true ? nil : dirParam, fallback: fallback)
          self.sendEncodable(conn, status: 200, value: listing)
        } catch {
          self.sendJSON(conn, status: 404, body: ["error": error.localizedDescription])
        }
      }

    case "/api/probe":
      let file = VideoMediaEngine.expandPath(query["file"])
      let customFFmpeg = delegate?.serverConfigSnapshot().customFFmpegPath ?? ""
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let result = try self.engine.probe(file: file, customFFmpegPath: customFFmpeg)
          self.sendEncodable(conn, status: 200, value: result)
        } catch {
          self.sendJSON(conn, status: 500, body: ["error": error.localizedDescription])
        }
      }

    case "/api/pick":
      let kind = query["kind"] ?? "video"
      Task {
        let picked = await self.delegate?.serverPickFile(kind: kind)
        struct PickReply: Encodable { let path: String? }
        self.sendEncodable(conn, status: 200, value: PickReply(path: picked))
      }

    case "/api/wallpaper":
      DispatchQueue.global(qos: .userInitiated).async {
        if let jpeg = self.engine.desktopWallpaperJPEG() {
          self.sendResponse(
            conn, status: 200, contentType: "image/jpeg", cacheControl: "no-cache", body: jpeg)
        } else {
          self.sendEmpty(conn, status: 404)
        }
      }

    case "/api/thumb":
      let file = query["file"] ?? ""
      let customFFmpeg = delegate?.serverConfigSnapshot().customFFmpegPath ?? ""
      DispatchQueue.global(qos: .utility).async {
        if let jpeg = self.engine.thumbnailJPEG(file: file, customFFmpegPath: customFFmpeg) {
          self.sendResponse(
            conn, status: 200, contentType: "image/jpeg", cacheControl: "max-age=86400", body: jpeg)
        } else {
          self.sendEmpty(conn, status: 404)
        }
      }

    case "/api/keyframe":
      let file = query["file"] ?? ""
      let t = Double(query["t"] ?? "0") ?? 0
      let customFFmpeg = delegate?.serverConfigSnapshot().customFFmpegPath ?? ""
      DispatchQueue.global(qos: .userInitiated).async {
        let kt = self.engine.keyframeTime(file: file, time: t, customFFmpegPath: customFFmpeg)
        self.sendJSON(conn, status: 200, body: ["t": kt])
      }

    case "/api/frame":
      let file = query["file"] ?? ""
      let t = Double(query["t"] ?? "0") ?? 0
      let customFFmpeg = delegate?.serverConfigSnapshot().customFFmpegPath ?? ""
      DispatchQueue.global(qos: .userInitiated).async {
        if let jpeg = self.engine.frameJPEG(file: file, time: t, customFFmpegPath: customFFmpeg) {
          self.sendResponse(
            conn, status: 200, contentType: "image/jpeg", cacheControl: "max-age=86400", body: jpeg)
        } else {
          self.sendEmpty(conn, status: 404)
        }
      }

    case "/api/bgimg":
      let imgPath = query["path"] ?? ""
      DispatchQueue.global(qos: .userInitiated).async {
        if let jpeg = self.engine.customBackgroundJPEG(path: imgPath) {
          self.sendResponse(
            conn, status: 200, contentType: "image/jpeg", cacheControl: "max-age=3600", body: jpeg)
        } else {
          self.sendEmpty(conn, status: 404)
        }
      }

    case "/subs":
      let file = query["file"].flatMap { $0.isEmpty ? nil : VideoMediaEngine.expandPath($0) }
      let ext = query["ext"].flatMap { $0.isEmpty ? nil : VideoMediaEngine.expandPath($0) }
      let sid = query["sid"].flatMap(Int.init)
      let customFFmpeg = delegate?.serverConfigSnapshot().customFFmpegPath ?? ""
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let vtt = try self.engine.extractSubtitlesVTT(
            file: file, subtitleID: sid, externalPath: ext, customFFmpegPath: customFFmpeg)
          self.sendResponse(
            conn, status: 200, contentType: "text/vtt; charset=utf-8", cacheControl: "no-store",
            body: vtt)
        } catch {
          self.sendJSON(conn, status: 422, body: ["error": error.localizedDescription])
        }
      }

    case "/stream":
      // Only Safari needs byte-range semantics. Chromium/Firefox treat a ranged live transcode as seekable and
      // re-request mid-stream offsets, which restarts ffmpeg and yields a corrupt stream — so give them a
      // plain chunked 200 with no range support.
      let ua = req.headers["user-agent"] ?? ""
      let isSafari = ua.contains("Safari") && !ua.contains("Chrome") && !ua.contains("Chromium")
        && !ua.contains("CriOS") && !ua.contains("Edg") && !ua.contains("Firefox")
      handleStream(query: query, range: isSafari ? req.headers["range"] : nil, on: conn)

    default:
      sendJSON(conn, status: 404, body: ["error": "Not found"])
    }
  }

  private func handleStream(query: [String: String], range: String?, on conn: NWConnection) {
    // Safari insists on byte ranges. Parse "bytes=S-E".
    var rangeStart: Int?
    if let r = range?.lowercased(), r.hasPrefix("bytes=") {
      let bounds = r.dropFirst(6).split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
      if let s = bounds.first.flatMap({ Int($0) }) {
        let e = bounds.count > 1 ? Int(bounds[1]) : nil
        if let e, e >= s, e - s < 16, s == 0, e < 4 {
          // Probe request: the first bytes of an MP4 box size are always zero.
          let n = e - s + 1
          var head = Data("HTTP/1.1 206 Partial Content\r\nContent-Type: video/mp4\r\nAccept-Ranges: bytes\r\n".utf8)
          head.append(Data("Content-Range: bytes \(s)-\(e)/\(StreamSession.fakeTotal)\r\nContent-Length: \(n)\r\nConnection: close\r\n\r\n".utf8))
          head.append(Data(count: n))
          conn.send(content: head, contentContext: .defaultMessage, isComplete: true,
            completion: .contentProcessed { _ in conn.cancel() })
          return
        }
        if s > 64 * 1024 * 1024 {
          sendEmpty(conn, status: 416)
          return
        }
        rangeStart = s
      }
    }
    let file = VideoMediaEngine.expandPath(query["file"])
    guard VideoMediaEngine.isVideoPath(file), FileManager.default.fileExists(atPath: file) else {
      sendJSON(conn, status: 400, body: ["error": "Not a video file"])
      return
    }

    let aid = max(1, Int(query["aid"] ?? "1") ?? 1)
    let t = max(0, Double(query["t"] ?? "0") ?? 0)
    let quality = VideoQuality(rawValue: query["q"] ?? "orig") ?? .orig
    let cfg = delegate?.serverConfigSnapshot()
    let customFFmpeg = cfg?.customFFmpegPath ?? ""
    let hwAccel = cfg?.hardwareAcceleration ?? true

    guard let ffmpegPath = VideoMediaEngine.resolveBinaries(customFFmpegPath: customFFmpeg).ffmpeg else {
      sendJSON(conn, status: 500, body: ["error": MediaEngineError.ffmpegMissing.localizedDescription])
      return
    }

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else {
        conn.cancel()
        return
      }
      do {
        let info = try self.engine.probe(file: file, customFFmpegPath: customFFmpeg)
        let args = VideoMediaEngine.buildStreamArguments(
          file: file, audioTrackID: aid, seekTime: t, quality: quality, probe: info,
          hardwareAcceleration: hwAccel, copyHEVC: query["vc"] == "1")

        let sessionID = UUID()
        let session = StreamSession(id: sessionID, connection: conn) { [weak self] in
          guard let self else { return }
          self.stateLock.lock()
          self.activeSessions.removeValue(forKey: sessionID)
          let noClients = self.clients.isEmpty
          let noStreams = self.activeSessions.isEmpty
          self.stateLock.unlock()
          self.notifyStats()
          if noClients && noStreams {
            self.scheduleAutoStopIfNeeded(graceSeconds: 5.0)
          }
        }

        session.rangeStart = rangeStart
        self.stateLock.lock()
        if self.isStopped {
          self.stateLock.unlock()
          conn.cancel()
          return
        }
        self.activeSessions[session.id] = session
        self.autoStopWork?.cancel()
        self.autoStopWork = nil
        self.stateLock.unlock()
        self.notifyStats()

        Diagnostics.event("videoplayer.stream", "start \((file as NSString).lastPathComponent) q=\(quality.rawValue) t=\(Int(t)) range=\(rangeStart.map(String.init) ?? "-")")
        session.start(ffmpegPath: ffmpegPath, arguments: args)
      } catch {
        self.sendJSON(conn, status: 500, body: ["error": error.localizedDescription])
      }
    }
  }

  // MARK: - HTTP Response Helpers

  private func statusText(_ code: Int) -> String {
    switch code {
    case 200: return "OK"
    case 204: return "No Content"
    case 416: return "Range Not Satisfiable"
    case 400: return "Bad Request"
    case 404: return "Not Found"
    case 413: return "Payload Too Large"
    case 422: return "Unprocessable Entity"
    default: return "Internal Server Error"
    }
  }

  private func sendEmpty(_ conn: NWConnection, status: Int) {
    let header = "HTTP/1.1 \(status) \(statusText(status))\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    conn.send(
      content: Data(header.utf8),
      completion: .contentProcessed { _ in conn.cancel() })
  }

  private func sendResponse(
    _ conn: NWConnection, status: Int, contentType: String, cacheControl: String = "no-store",
    body: Data
  ) {
    let header =
      "HTTP/1.1 \(status) \(statusText(status))\r\n"
      + "Content-Type: \(contentType)\r\n"
      + "Cache-Control: \(cacheControl)\r\n"
      + "Content-Length: \(body.count)\r\n"
      + "Connection: close\r\n\r\n"
    var packet = Data(header.utf8)
    packet.append(body)
    conn.send(
      content: packet,
      completion: .contentProcessed { _ in conn.cancel() })
  }

  private func sendEncodable<T: Encodable>(_ conn: NWConnection, status: Int, value: T) {
    do {
      let data = try JSONEncoder().encode(value)
      sendResponse(conn, status: status, contentType: "application/json; charset=utf-8", body: data)
    } catch {
      sendJSON(conn, status: 500, body: ["error": "Encoding failed"])
    }
  }

  private func sendJSON(_ conn: NWConnection, status: Int, body: [String: Any]) {
    let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
    sendResponse(conn, status: status, contentType: "application/json; charset=utf-8", body: data)
  }
}
