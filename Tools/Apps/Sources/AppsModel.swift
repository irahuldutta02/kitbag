import AppKit
import KitbagCore

/// An app Kitbag can switch on and off.
struct ManagedApp: Identifiable {
  let id: String
  let name: String
  let bundleID: String
}

@MainActor
final class AppsModel: ObservableObject {
  static let catalog = [
    ManagedApp(id: "gdrive", name: "Google Drive", bundleID: "com.google.drivefs"),
    ManagedApp(id: "pdrive", name: "Proton Drive", bundleID: "ch.protonmail.drive"),
    ManagedApp(id: "wispr", name: "Wispr Flow", bundleID: "com.electron.wispr-flow"),
    ManagedApp(id: "openwhispr", name: "OpenWhispr", bundleID: "com.gizmolabs.openwhispr"),
    ManagedApp(id: "finetune", name: "FineTune", bundleID: "com.finetuneapp.FineTune"),
  ]

  @Published private(set) var running: Set<String> = []
  @Published private(set) var busy: Set<String> = []
  @Published private(set) var installed: Set<String> = []
  @Published var notice: String?
  /// Kitbag's own tools that can be switched here too (for example Dictation).
  @Published var toolSwitches: [ToolSwitch] = []
  /// Apps the user chose not to show in the Apps tab.
  @Published private(set) var hidden: Set<String> = Set(
    UserDefaults.standard.stringArray(forKey: "kitbag.apps.hidden") ?? [])

  /// Only apps that are installed and not hidden; anything missing is listed in Settings instead.
  var visible: [ManagedApp] { Self.catalog.filter { installed.contains($0.id) && !hidden.contains($0.id) } }

  func setShown(_ app: ManagedApp, _ on: Bool) {
    if on { hidden.remove(app.id) } else { hidden.insert(app.id) }
    UserDefaults.standard.set(Array(hidden), forKey: "kitbag.apps.hidden")
  }
  private var observers: [NSObjectProtocol] = []

  func observe() {
    guard observers.isEmpty else { return }
    let ws = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
      observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in self?.refresh() }
      })
    }
    refresh()
  }

  func stopObserving() {
    observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    observers = []
  }

  func url(_ app: ManagedApp) -> URL? {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)
  }

  func refresh() {
    running = Set(Self.catalog.filter { isRunning($0) }.map(\.id))
    installed = Set(Self.catalog.filter { url($0).map { FileManager.default.fileExists(atPath: $0.path) } == true }.map(\.id))
  }

  private func isRunning(_ app: ManagedApp) -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
  }

  func icon(_ app: ManagedApp, size: CGFloat) -> NSImage {
    let i = url(app).map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(named: NSImage.applicationIconName)!
    i.size = NSSize(width: size, height: size)
    return i
  }

  /// Starts or quits the app without taking focus from what you're doing.
  func set(_ app: ManagedApp, on: Bool) {
    guard !busy.contains(app.id) else { return }
    busy.insert(app.id)
    notice = nil
    Task {
      defer { busy.remove(app.id); refresh() }
      if on {
        guard let url = url(app) else { return notice = String(localized: "\(app.name) isn't installed.") }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true  // start in the background; some apps (Wispr Flow) open a window otherwise
        do { _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config) } catch {
          notice = error.localizedDescription
        }
        // Apps that still open a window while starting are hidden again, for a few seconds.
        for _ in 0..<15 {
          NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).forEach { $0.hide() }
          try? await Task.sleep(nanoseconds: 300_000_000)
        }
        await wait(app, running: true)
      } else {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
        apps.forEach { $0.terminate() }
        await wait(app, running: false)
        if isRunning(app) {  // ignored the polite request
          apps.forEach { $0.forceTerminate() }
          await wait(app, running: false)
        }
      }
    }
  }

  private func wait(_ app: ManagedApp, running want: Bool) async {
    for _ in 0..<25 {  // up to ~5 s
      refresh()
      if isRunning(app) == want { return }
      try? await Task.sleep(nanoseconds: 200_000_000)
    }
  }
}
