import AppKit
import Darwin
import Foundation
import os

/// Opt-in performance recorder. While it is on, Kitbag writes a plain-text log of what the app is
/// doing: CPU and memory of the app and of the programs it started, which threads are busy, what
/// the tools were doing, and stalls of the main thread. When CPU or memory spikes it also saves a
/// call-stack sample of the app. Send the log folder to whoever is fixing the problem.
///
/// Off by default; nothing is recorded or written while it is off.
/// One point on the live graphs.
public struct DiagnosticsSample: Identifiable, Sendable {
  public let id = UUID()
  public let time: Date
  public let appCPU: Double      // percent of one core
  public let helperCPU: Double   // ffmpeg and other programs Kitbag started
  public let appMemoryMB: Double
  public let helperMemoryMB: Double
}

@MainActor
public final class Diagnostics: ObservableObject {
  public static let shared = Diagnostics()

  @Published public private(set) var isRecording = false
  @Published public private(set) var startedAt: Date?
  @Published public private(set) var stoppedAt: Date?
  @Published public private(set) var samples: [DiagnosticsSample] = []
  @Published public private(set) var logSize: Int64 = 0
  @Published public private(set) var currentLogPath: String?

  /// Extra context for the log header (which tools are on, settings...). Set by the app.
  public var contextProvider: (() -> [String])?

  private let recorder = DiagnosticsRecorder()
  private let maxPoints = 1800  // an hour at one sample every two seconds

  public nonisolated static var folder: URL {
    FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Logs/Kitbag", isDirectory: true)
  }

  /// Recording is always off when Kitbag starts; the user turns it on when they want it.
  public func start() {
    guard !isRecording else { return }
    samples = []
    startedAt = Date()
    stoppedAt = nil
    isRecording = true
    DiagnosticsRecorder.active.set(true)
    recorder.onSample = { [weak self] sample in
      DispatchQueue.main.async { self?.append(sample) }
    }
    currentLogPath = recorder.start(header: contextProvider?() ?? [])?.path
    refreshSize()
  }

  public func stop() {
    guard isRecording else { return }
    isRecording = false
    stoppedAt = Date()
    DiagnosticsRecorder.active.set(false)
    recorder.onSample = nil
    recorder.stop()
    refreshSize()
  }

  private func append(_ s: DiagnosticsSample) {
    guard isRecording else { return }
    samples.append(s)
    if samples.count > maxPoints { samples.removeFirst(samples.count - maxPoints) }
    if samples.count % 5 == 0 { refreshSize() }
  }

  public func refreshSize() {
    let dir = Self.folder
    let total = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]))?
      .reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) } ?? 0
    logSize = total
  }

  public var hasLog: Bool { currentLogPath.map { FileManager.default.fileExists(atPath: $0) } ?? false }

  public func revealInFinder() {
    try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
    if let p = currentLogPath, FileManager.default.fileExists(atPath: p) {
      NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
    } else {
      NSWorkspace.shared.open(Self.folder)
    }
  }

  /// Puts the log's text on the clipboard so it can be pasted into a chat. Very long logs keep the
  /// header and the most recent part.
  @discardableResult
  public func copyLogText() -> Bool {
    guard let p = currentLogPath, let data = FileManager.default.contents(atPath: p) else { return false }
    let limit = 900_000
    var text = String(decoding: data, as: UTF8.self)
    if data.count > limit {
      let lines = text.components(separatedBy: "\n")
      let head = lines.prefix(14).joined(separator: "\n")
      let tail = String(decoding: data.suffix(limit - 4_000), as: UTF8.self)
      text = head + "\n... (middle of the log left out to fit the clipboard; the full file is in \(Self.folder.path)) ...\n" + tail
    }
    NSPasteboard.general.clearContents()
    return NSPasteboard.general.setString(text, forType: .string)
  }

  /// Puts the log file itself on the clipboard (paste it into Finder, Mail or a chat that takes files).
  @discardableResult
  public func copyLogFile() -> Bool {
    guard let p = currentLogPath, FileManager.default.fileExists(atPath: p) else { return false }
    NSPasteboard.general.clearContents()
    return NSPasteboard.general.writeObjects([URL(fileURLWithPath: p) as NSURL])
  }

  public func copyFolderPath() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(Self.folder.path, forType: .string)
  }

  /// Deletes old logs (keeps the one being written or just finished).
  public func clearOldLogs() {
    let fm = FileManager.default
    let files = (try? fm.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
    for f in files where f.path != currentLogPath { try? fm.removeItem(at: f) }
    refreshSize()
  }

  // MARK: Events from anywhere in the app (cheap no-op while recording is off)

  /// Records one line such as `tool.visible systemmonitor`. Safe to call from any thread.
  public nonisolated static func event(_ category: String, _ message: @autoclosure () -> String) {
    guard DiagnosticsRecorder.active.value else { return }
    DiagnosticsRecorder.shared?.event(category, message())
  }
}

/// Lock-protected flag so `Diagnostics.event` costs almost nothing when recording is off.
final class DiagnosticsFlag: @unchecked Sendable {
  private var lock = os_unfair_lock()
  private var on = false
  var value: Bool {
    os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
    return on
  }
  func set(_ v: Bool) {
    os_unfair_lock_lock(&lock); on = v; os_unfair_lock_unlock(&lock)
  }
}

/// Does the actual sampling and writing, off the main thread.
final class DiagnosticsRecorder: @unchecked Sendable {
  nonisolated(unsafe) static var shared: DiagnosticsRecorder?
  static let active = DiagnosticsFlag()

  var onSample: ((DiagnosticsSample) -> Void)?
  private let queue = DispatchQueue(label: "kitbag.diagnostics", qos: .utility)
  private var timer: DispatchSourceTimer?
  private var heartbeat: DispatchSourceTimer?
  private var handle: FileHandle?
  private var bytesWritten = 0
  private var logURL: URL?
  private let maxBytes = 25 * 1024 * 1024
  private let interval: TimeInterval = 2

  private struct Prev { var cpuNs: UInt64; var at: UInt64 }
  private var prev: [Int32: Prev] = [:]
  private var highCPUStreak = 0
  private var lastSample = Date.distantPast
  private var lastFootprint = Date.distantPast
  private var baselineFootprint: UInt64 = 0
  private var samplesTaken = 0
  private var mainBeatSent: UInt64 = 0
  private var mainBeatSeen: UInt64 = 0
  private var stallReported = false

  private let timebase: mach_timebase_info_data_t = {
    var t = mach_timebase_info_data_t()
    mach_timebase_info(&t)
    return t
  }()

  private static let stamp: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
    return f
  }()

  // MARK: Start / stop

  func start(header: [String]) -> URL? {
    Self.shared = self
    let dir = Diagnostics.folder
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    pruneOldFiles(in: dir)
    let nameStamp = DateFormatter()
    nameStamp.dateFormat = "yyyyMMdd-HHmmss"
    let url = dir.appendingPathComponent("diagnostics-\(nameStamp.string(from: Date())).log")
    FileManager.default.createFile(atPath: url.path, contents: nil)
    guard let h = try? FileHandle(forWritingTo: url) else { return nil }
    queue.sync {
      handle = h
      logURL = url
      bytesWritten = 0
      prev = [:]
      highCPUStreak = 0
      samplesTaken = 0
      baselineFootprint = 0
      write("=== Kitbag diagnostics ===")
      write("started: \(Date())")
      let info = Bundle.main.infoDictionary
      write("app: \(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))  pid \(getpid())")
      write("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)  cores: \(ProcessInfo.processInfo.activeProcessorCount)  RAM: \(ProcessInfo.processInfo.physicalMemory / 1_048_576) MB")
      write("low power mode: \(ProcessInfo.processInfo.isLowPowerModeEnabled)  thermal: \(ProcessInfo.processInfo.thermalState.rawValue)")
      header.forEach { write($0) }
      write("legend: cpu% is percent of ONE core (800% = all 8 cores). Lines: [SAMPLE] every \(Int(interval))s, [EVENT] app activity, [HANG] main thread stalls, [SPIKE] saved call-stack sample.")
      write("")
    }

    let t = DispatchSource.makeTimerSource(queue: queue)
    t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(200))
    t.setEventHandler { [weak self] in self?.tick() }
    t.resume()
    timer = t

    // Main-thread stall detector: the main queue must answer a ping within a moment.
    let hb = DispatchSource.makeTimerSource(queue: queue)
    hb.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(250))
    hb.setEventHandler { [weak self] in self?.beat() }
    hb.resume()
    heartbeat = hb

    NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
      self?.event("app", "became active")
    }
    NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: nil) { [weak self] _ in
      self?.event("app", "resigned active")
    }
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { [weak self] _ in
      self?.event("system", "going to sleep")
    }
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
      self?.event("system", "woke from sleep")
    }
    return url
  }

  func stop() {
    queue.sync {
      write("")
      write("=== recording stopped: \(Date()) ===")
      timer?.cancel(); timer = nil
      heartbeat?.cancel(); heartbeat = nil
      try? handle?.close(); handle = nil
    }
    NotificationCenter.default.removeObserver(self)
    NSWorkspace.shared.notificationCenter.removeObserver(self)
  }

  private func pruneOldFiles(in dir: URL) {
    let fm = FileManager.default
    let files = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
      .sorted { a, b in
        let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return da > db
      }
    for f in files.dropFirst(14) { try? fm.removeItem(at: f) }  // keep the newest few files
  }

  // MARK: Writing

  func event(_ category: String, _ message: String) {
    queue.async { [weak self] in self?.write("[EVENT] \(category): \(message)") }
  }

  private func write(_ line: String) {
    guard let handle, bytesWritten < maxBytes else { return }
    let text = line.hasPrefix("===") || line.isEmpty || !line.hasPrefix("[")
      ? line + "\n"
      : "\(Self.stamp.string(from: Date())) \(line)\n"
    let data = Data(text.utf8)
    bytesWritten += data.count
    try? handle.write(contentsOf: data)
    if bytesWritten >= maxBytes {
      try? handle.write(contentsOf: Data("log size limit reached; recording continues without writing\n".utf8))
    }
  }

  // MARK: Main-thread stall detector

  private func beat() {
    // If the previous ping never came back, the main thread has been busy for at least a second.
    if mainBeatSeen < mainBeatSent {
      if !stallReported {
        stallReported = true
        write("[HANG] main thread has not responded for >1s (UI is frozen or busy)")
        captureSample(reason: "main thread hang", seconds: 2)
      }
    } else {
      stallReported = false
    }
    mainBeatSent += 1
    let n = mainBeatSent
    DispatchQueue.main.async { [weak self] in
      self?.queue.async { self?.mainBeatSeen = max(self?.mainBeatSeen ?? 0, n) }
    }
  }

  // MARK: Sampling

  private func machNow() -> UInt64 { mach_absolute_time() }
  private func ns(_ mach: UInt64) -> UInt64 { mach &* UInt64(timebase.numer) / UInt64(timebase.denom) }

  private struct Usage { var cpuNs: UInt64; var footprint: UInt64; var rss: UInt64 }

  private func usage(of pid: Int32) -> Usage? {
    var info = rusage_info_v4()
    let r = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
    }
    guard r == 0 else { return nil }
    return Usage(cpuNs: ns(info.ri_user_time &+ info.ri_system_time), footprint: info.ri_phys_footprint, rss: info.ri_resident_size)
  }

  private func name(of pid: Int32) -> String {
    var buf = [CChar](repeating: 0, count: 256)
    proc_name(pid, &buf, 256)
    let n = String(cString: buf)
    return n.isEmpty ? "pid\(pid)" : n
  }

  private func children(of pid: Int32, depth: Int = 0) -> [Int32] {
    var pids = [Int32](repeating: 0, count: 128)
    let n = proc_listchildpids(pid, &pids, Int32(pids.count * MemoryLayout<Int32>.size))
    guard n > 0 else { return [] }
    let found = Array(pids.prefix(Int(n)).filter { $0 > 0 })
    guard depth < 3 else { return found }
    return found + found.flatMap { children(of: $0, depth: depth + 1) }
  }

  private func cpuPercent(pid: Int32, usage u: Usage, now: UInt64) -> Double {
    defer { prev[pid] = Prev(cpuNs: u.cpuNs, at: now) }
    guard let p = prev[pid], now > p.at else { return 0 }
    let wall = Double(ns(now - p.at))
    guard wall > 0 else { return 0 }
    return Double(u.cpuNs &- p.cpuNs) / wall * 100
  }

  private func mb(_ bytes: UInt64) -> String { String(format: "%.0fMB", Double(bytes) / 1_048_576) }

  /// Busy threads of this process (name and share of one core).
  private func hotThreads() -> (count: Int, hot: [String]) {
    var list: thread_act_array_t?
    var count = mach_msg_type_number_t(0)
    guard task_threads(mach_task_self_, &list, &count) == KERN_SUCCESS, let list else { return (0, []) }
    defer {
      vm_deallocate(mach_task_self_, vm_address_t(bitPattern: list), vm_size_t(Int(count) * MemoryLayout<thread_t>.size))
    }
    var rows: [(String, Double)] = []
    for i in 0..<Int(count) {
      var info = thread_basic_info()
      var c = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
      let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(c)) {
          thread_info(list[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &c)
        }
      }
      guard kr == KERN_SUCCESS else { continue }
      let pct = Double(info.cpu_usage) / 10.0  // TH_USAGE_SCALE is 1000 = one full core
      guard pct >= 2 else { continue }
      var label = "thread\(list[i])"
      if let pt = pthread_from_mach_thread_np(list[i]) {
        var buf = [CChar](repeating: 0, count: 64)
        pthread_getname_np(pt, &buf, 64)
        let s = String(cString: buf)
        if !s.isEmpty { label = s }
        if pthread_main_np() != 0 && pthread_equal(pt, pthread_self()) != 0 { label = "main" }
      }
      rows.append((label, pct))
    }
    rows.sort { $0.1 > $1.1 }
    return (Int(count), rows.prefix(5).map { String(format: "%@ %.0f%%", $0.0, $0.1) })
  }

  private func tick() {
    let now = machNow()
    let me = getpid()
    guard let u = usage(of: me) else { return }
    let cpu = cpuPercent(pid: me, usage: u, now: now)
    samplesTaken += 1
    if baselineFootprint == 0 { baselineFootprint = u.footprint }

    let (threadCount, hot) = hotThreads()
    var line = String(format: "[SAMPLE] app cpu=%.0f%% mem=%@ rss=%@ threads=%d", cpu, mb(u.footprint), mb(u.rss), threadCount)
    if !hot.isEmpty { line += " | busy threads: " + hot.joined(separator: ", ") }

    var kids: [String] = []
    var kidsCPU = 0.0
    var kidsMem: UInt64 = 0
    var seen = Set<Int32>()
    for pid in children(of: me) where seen.insert(pid).inserted {
      guard let cu = usage(of: pid) else { continue }
      let c = cpuPercent(pid: pid, usage: cu, now: now)
      let n = name(of: pid)
      kidsCPU += c
      kidsMem &+= cu.footprint
      if c >= 1 || cu.footprint > 50 * 1_048_576 { kids.append(String(format: "%@(pid %d) cpu=%.0f%% mem=%@", n, pid, c, mb(cu.footprint))) }
    }
    prev = prev.filter { seen.contains($0.key) || $0.key == me }
    if !kids.isEmpty { line += " | child processes: " + kids.joined(separator: "; ") }
    write(line)
    onSample?(DiagnosticsSample(
      time: Date(), appCPU: cpu, helperCPU: kidsCPU,
      appMemoryMB: Double(u.footprint) / 1_048_576, helperMemoryMB: Double(kidsMem) / 1_048_576))

    // CPU spike: three busy samples in a row (about 6 seconds) saves a call-stack sample.
    if cpu >= 60 { highCPUStreak += 1 } else { highCPUStreak = 0 }
    if highCPUStreak == 3 {
      write(String(format: "[SPIKE] app CPU stayed at %.0f%% for ~6s", cpu))
      captureSample(reason: "high CPU", seconds: 3)
    }

    // Memory: more than 250 MB above where it started, or past 1 GB, saves a memory breakdown.
    let grown = u.footprint > baselineFootprint &+ 250 * 1_048_576
    if (grown || u.footprint > 1_073_741_824) && Date().timeIntervalSince(lastFootprint) > 300 {
      lastFootprint = Date()
      write("[SPIKE] memory is \(mb(u.footprint)) (started at \(mb(baselineFootprint)))")
      captureMemory()
    }
  }

  // MARK: Spike captures (written next to the log)

  private func captureSample(reason: String, seconds: Int) {
    guard Date().timeIntervalSince(lastSample) > 60, let logURL else { return }
    lastSample = Date()
    let f = DateFormatter(); f.dateFormat = "HHmmss"
    let out = logURL.deletingLastPathComponent().appendingPathComponent("spike-sample-\(f.string(from: Date())).txt")
    write("[SPIKE] saving call-stack sample (\(reason)) -> \(out.lastPathComponent)")
    runTool("/usr/bin/sample", ["\(getpid())", "\(seconds)", "-file", out.path])
  }

  private func captureMemory() {
    guard let logURL else { return }
    let f = DateFormatter(); f.dateFormat = "HHmmss"
    let out = logURL.deletingLastPathComponent().appendingPathComponent("spike-memory-\(f.string(from: Date())).txt")
    write("[SPIKE] saving memory breakdown -> \(out.lastPathComponent)")
    runTool("/usr/bin/footprint", ["\(getpid())"], output: out)
  }

  private func runTool(_ path: String, _ args: [String], output: URL? = nil) {
    guard FileManager.default.isExecutableFile(atPath: path) else {
      write("[EVENT] diagnostics: \(path) is not available on this Mac")
      return
    }
    DispatchQueue.global(qos: .utility).async {
      let p = Process()
      p.executableURL = URL(fileURLWithPath: path)
      p.arguments = args
      p.qualityOfService = .utility
      if let output {
        FileManager.default.createFile(atPath: output.path, contents: nil)
        p.standardOutput = try? FileHandle(forWritingTo: output)
      } else {
        p.standardOutput = FileHandle.nullDevice
      }
      p.standardError = FileHandle.nullDevice
      try? p.run()
      p.waitUntilExit()
    }
  }
}
