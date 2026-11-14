import AppKit
import Foundation

enum Metric { case cpu, memory }

@MainActor
final class MonitorModel: ObservableObject {
  static let intervals: [TimeInterval] = [1, 2, 5, 10]
  private static let intervalKey = "systemmonitor.interval"

  @Published private(set) var snapshot: SystemSnapshot?
  @Published private(set) var expanded: Metric?
  @Published private(set) var groups: [ProcessGroup] = []
  @Published var notice: String?
  @Published private(set) var openGroups: Set<String> = []
  /// Filters the app list (both CPU and memory) by app or process name.
  @Published var query = ""

  @Published var interval: TimeInterval {
    didSet {
      defaults.set(interval, forKey: Self.intervalKey)
      if timer != nil { startTimer() }
    }
  }

  private let defaults: UserDefaults
  private var sampler = SystemSampler()
  private var processes = ProcessSampler()
  private(set) var timer: Timer?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let saved = defaults.double(forKey: Self.intervalKey)
    interval = Self.intervals.contains(saved) ? saved : 2
  }

  /// Polling runs only while this tool's tab is visible.
  func setActive(_ on: Bool) {
    if on {
      startTimer()
    } else {
      stopTimer()
      collapse()
      snapshot = nil  // leaving the tab discards its data
    }
  }

  private func startTimer() {
    timer?.invalidate()
    sampler.reset()
    _ = sampler.sample()  // baseline so the first delta is meaningful
    let t = Timer(fire: Date().addingTimeInterval(0.5), interval: interval, repeats: true) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    t.tolerance = interval * 0.25
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  func tick() {
    snapshot = sampler.sample()
    if expanded != nil { groups = processes.sample() }
  }

  // MARK: Per-app breakdown (sampled only while a tile is expanded)

  func toggle(_ m: Metric) {
    if expanded == m { return collapse() }
    let first = expanded == nil
    expanded = m
    guard first else { return }
    groups = processes.sample()  // baseline: memory is right, CPU fills in a second later
    Task {
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      if expanded != nil, timer != nil { groups = processes.sample() }
    }
  }

  func collapse() {
    expanded = nil
    groups = []
    openGroups = []
    query = ""
    processes = ProcessSampler()
  }

  /// Every group matching the search, busiest first for the expanded metric.
  var sortedGroups: [ProcessGroup] {
    let q = query.trimmingCharacters(in: .whitespaces)
    let matching =
      q.isEmpty
      ? groups
      : groups.filter { g in
        g.name.localizedCaseInsensitiveContains(q)
          || g.members.contains { $0.name.localizedCaseInsensitiveContains(q) }
      }
    return expanded == .memory
      ? matching.sorted { $0.memory > $1.memory } : matching.sorted { $0.cpu > $1.cpu }
  }

  func members(of g: ProcessGroup) -> [ProcessEntry] {
    expanded == .memory
      ? g.members.sorted { $0.memory > $1.memory } : g.members.sorted { $0.cpu > $1.cpu }
  }

  func toggleGroup(_ id: String) {
    if openGroups.contains(id) { openGroups.remove(id) } else { openGroups.insert(id) }
  }

  func quit(_ g: ProcessGroup) { quit(name: g.name, appPath: g.appPath, pids: g.pids) }
  func quit(_ e: ProcessEntry) { quit(name: e.name, appPath: nil, pids: [e.pid]) }

  private func quit(name: String, appPath: String?, pids: [pid_t]) {
    guard !pids.contains(getpid()) else { return }  // never quits itself from here
    let alert = NSAlert()
    alert.messageText = String(localized: "Quit “\(name)”?")
    alert.informativeText =
      appPath == nil && pids.count == 1
      ? String(localized: "This ends one process. Other apps may be affected.")
      : String(localized: "Unsaved changes in it may be lost.")
    alert.addButton(withTitle: String(localized: "Quit"))
    alert.addButton(withTitle: String(localized: "Cancel"))
    NSApp.activate(ignoringOtherApps: true)
    guard alert.runModal() == .alertFirstButtonReturn else { return }

    notice = nil
    var failed = false
    for pid in pids {
      // Polite quit for regular apps; plain SIGTERM for helpers and services.
      if let app = NSRunningApplication(processIdentifier: pid), app.terminate() { continue }
      if kill(pid, SIGTERM) != 0 { failed = true }
    }
    if failed { notice = String(localized: "Couldn't quit “\(name)” (not permitted).") }
    Task {
      try? await Task.sleep(nanoseconds: 1_500_000_000)
      if expanded != nil, timer != nil { groups = processes.sample() }
    }
  }
}
