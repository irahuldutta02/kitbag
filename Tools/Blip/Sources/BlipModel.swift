import AppKit
import KitbagCore

@MainActor
final class BlipModel: ObservableObject {
  @Published private(set) var running = false
  @Published private(set) var busy = false
  @Published var notice: String?

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
    if !running { await start() }
    guard running else {
      return FileSendResult(success: false, message: String(localized: "Couldn't start Blip."))
    }
    try? await Task.sleep(nanoseconds: 600_000_000)  // let a freshly started Blip settle
    return Self.performService(files)
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
