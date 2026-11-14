import AppKit
import KitbagCore

@MainActor
final class BlipModel: ObservableObject {
  @Published private(set) var running = false

  private var appURL: URL? {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: BlipTool.bundleID)
  }

  func refresh() {
    running = !NSRunningApplication.runningApplications(withBundleIdentifier: BlipTool.bundleID)
      .isEmpty
  }

  /// Starts Blip (a menu bar app) without taking focus away from what you're doing.
  func start() async {
    refresh()
    guard let url = appURL, !running else { return }
    let config = NSWorkspace.OpenConfiguration()
    config.activates = false
    _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
    refresh()
  }

  func open() {
    NSRunningApplication.runningApplications(withBundleIdentifier: BlipTool.bundleID).first?
      .activate()
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
