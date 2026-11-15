import AppKit
import KitbagCore

@MainActor
final class BlipModel: ObservableObject {
  @Published private(set) var running = false {
    didSet { power.isOn = running }
  }
  @Published private(set) var busy = false {
    didSet { power.isBusy = busy }
  }
  @Published var notice: String?

  /// The shelf's on/off switch for Blip. Flipping it by hand is always allowed.
  private(set) lazy var power = SenderPower { [weak self] on in
    guard let self else { return }
    Task { on ? await self.start() : await self.quit() }
  }

  // Blip is switched on and off by hand only; Kitbag never starts or stops it by itself.

  static let iconIDs = [BlipTool.bundleID]
  var iconVisible: Bool {
    get { AppMenuIcon.isVisible(Self.iconIDs, unset: false) }
    set {
      AppMenuIcon.setVisible(newValue, Self.iconIDs)
      objectWillChange.send()
      // The icon is read when Blip starts: restart an idle Blip so the change shows now.
      if running, !hasWindow {
        Task { await quit(); await start() }
      }
    }
  }

  private var appURL: URL? {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: BlipTool.bundleID)
  }

  private var observers: [NSObjectProtocol] = []

  /// Blip starting or quitting (from anywhere) updates the switch immediately.
  func observe() {
    guard observers.isEmpty else { return }
    let ws = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
      observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
        let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
        guard id == BlipTool.bundleID else { return }
        Task { @MainActor in self?.refresh() }
      })
    }
    refresh()
  }

  func stopObserving() {
    observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    observers = []
  }

  func refresh() {
    running = !NSRunningApplication.runningApplications(withBundleIdentifier: BlipTool.bundleID)
      .isEmpty
  }

  private func waitUntil(running want: Bool) async {
    for _ in 0..<25 {  // up to ~5 s
      refresh()
      if running == want { return }
      try? await Task.sleep(nanoseconds: 200_000_000)
    }
  }

  /// Starts Blip (a menu bar app) without taking focus away from what you're doing.
  func start() async {
    refresh()
    guard !running else { return }
    guard let url = appURL else { return notice = String(localized: "Blip isn't installed.") }
    notice = nil
    busy = true
    defer { busy = false }
    let config = NSWorkspace.OpenConfiguration()
    config.activates = false
    do {
      _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
    } catch {
      notice = error.localizedDescription
    }
    await waitUntil(running: true)
  }

  func quit() async {
    busy = true
    defer { busy = false }
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: BlipTool.bundleID)
    apps.forEach { $0.terminate() }
    await waitUntil(running: false)
    if running {  // ignored the polite request
      apps.forEach { $0.forceTerminate() }
      await waitUntil(running: false)
    }
  }

  /// Blip shows a normal window while you pick who to send to or a transfer is running.
  private var hasWindow: Bool {
    let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: BlipTool.bundleID).map(\.processIdentifier))
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.contains { w in
      guard let pid = w[kCGWindowOwnerPID as String] as? Int32, pids.contains(pid),
        (w[kCGWindowLayer as String] as? Int) == 0,
        let b = w[kCGWindowBounds as String] as? [String: Double]
      else { return false }
      return (b["Width"] ?? 0) > 80 && (b["Height"] ?? 0) > 80
    }
  }

  /// Brings Blip forward; for a menu bar app this makes it show its window.
  func open() {
    guard let url = appURL else { return }
    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    Task { _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config) }
  }

  /// Hands the files to Blip through its "Blip…" Service, so Blip shows its own list of people
  /// and devices to send them to. Blip has no way for other apps to pick the device.
  func send(_ urls: [URL]) async -> FileSendResult {
    let files = urls.filter(\.isFileURL)
    guard !files.isEmpty else { return FileSendResult(success: false) }
    guard running else {
      return FileSendResult(success: false, message: String(localized: "Blip is off. Turn it on first."))
    }
    try? await Task.sleep(nanoseconds: 600_000_000)  // let a freshly started Blip settle
    let ok = Self.performService(files)
    return ok
      ? FileSendResult(
        success: true,
        message: String(
          localized: "Sent \(files.count) item(s) to Blip. Choose who to send to in Blip."))
      : FileSendResult(
        success: false,
        message: String(localized: "Blip didn't accept the files. Try Services ▸ Blip… in Finder."))
  }

  static func performService(_ files: [URL]) -> Bool {
    let pb = NSPasteboard(name: NSPasteboard.Name("com.irahuldutta.kitbag.blip"))
    pb.clearContents()
    pb.writeObjects(files as [NSURL])
    return NSPerformService("Blip…", pb)
  }
}
