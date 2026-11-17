import AppKit
import KitbagCore

/// An app Kitbag can switch on and off.
struct ManagedApp: Identifiable {
  let id: String
  let name: String
  let bundleID: String
  /// Dictation apps that keep working without a window. When Kitbag switches one on, its window
  /// is kept out of sight (the hotkey would otherwise bring it back every time you dictate).
  var background = false
}

@MainActor
final class AppsModel: ObservableObject {
  static let catalog = [
    ManagedApp(id: "gdrive", name: "Google Drive", bundleID: "com.google.drivefs"),
    ManagedApp(id: "pdrive", name: "Proton Drive", bundleID: "ch.protonmail.drive"),
    ManagedApp(id: "wispr", name: "Wispr Flow", bundleID: "com.electron.wispr-flow", background: true),
    ManagedApp(id: "openwhispr", name: "OpenWhispr", bundleID: "com.gizmolabs.openwhispr", background: true),
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
  /// Background apps the user wants to see the window of (turns the keep-out-of-the-way off).
  @Published private(set) var windowAllowed: Set<String> = Set(
    UserDefaults.standard.stringArray(forKey: "kitbag.apps.windowAllowed") ?? [])

  func setWindowAllowed(_ app: ManagedApp, _ on: Bool) {
    if on { windowAllowed.insert(app.id) } else { windowAllowed.remove(app.id) }
    UserDefaults.standard.set(Array(windowAllowed), forKey: "kitbag.apps.windowAllowed")
  }

  /// Apps Kitbag switched on, whose window it keeps out of the way. Remembered across Kitbag restarts.
  private var guarded: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "kitbag.apps.guarded") ?? [])
  private func setGuarded(_ app: ManagedApp, _ on: Bool) {
    if on { guarded.insert(app.id) } else { guarded.remove(app.id) }
    UserDefaults.standard.set(Array(guarded), forKey: "kitbag.apps.guarded")
  }
  private var lastOtherApp: NSRunningApplication?
  private var guardTasks: [String: Task<Void, Never>] = [:]
  private var observers: [NSObjectProtocol] = []

  func observe() {
    guard observers.isEmpty else { return }
    let ws = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
      observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in self?.refresh() }
      })
    }
    observers.append(
      ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        Task { @MainActor in self?.activated(app) }
      })
    refresh()
  }

  func stopObserving() {
    guardTasks.values.forEach { $0.cancel() }
    guardTasks = [:]
    observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    observers = []
  }

  func url(_ app: ManagedApp) -> URL? {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)
  }

  func refresh() {
    running = Set(Self.catalog.filter { isRunning($0) }.map(\.id))
    installed = Set(Self.catalog.filter { url($0).map { FileManager.default.fileExists(atPath: $0.path) } == true }.map(\.id))
    for id in guarded where !running.contains(id) { guarded.remove(id) }  // it quit, so stop guarding
  }

  // MARK: Keeping a background app's window out of the way

  /// An app came to the front. If Kitbag switched it on as a background service, put it away again
  /// (Wispr Flow shows its window every time the dictation key is pressed).
  private func activated(_ app: NSRunningApplication?) {
    guard let app, let id = app.bundleIdentifier else { return }
    guard let managed = Self.catalog.first(where: { $0.bundleID == id }) else {
      if id != Bundle.main.bundleIdentifier { lastOtherApp = app }
      return
    }
    guard managed.background, guarded.contains(managed.id), !windowAllowed.contains(managed.id) else { return }
    // You opened it on purpose (Dock, Spotlight, its own menu bar icon, ⌘-Tab): leave the window alone, and
    // stop any put-away that is still running. Only a dictation hotkey (fn, ⌃, ⌥ or ⇧ held, without ⌘)
    // is treated as the app popping its window up by itself.
    if Self.isDeliberateOpen(NSEvent.modifierFlags) {
      guardTasks[managed.id]?.cancel()
      guardTasks[managed.id] = nil
      return
    }
    keepAway(managed)
  }

  /// Whether an app coming to the front looks like something you did, judging by the keys held.
  nonisolated static func isDeliberateOpen(_ keys: NSEvent.ModifierFlags) -> Bool {
    if keys.contains(.command) { return true }  // ⌘-Tab
    return keys.intersection([.function, .control, .option, .shift]).isEmpty  // no hotkey held
  }

  /// Dismisses the app's window for a couple of seconds, since it may open a moment after it activates.
  private func keepAway(_ app: ManagedApp, rounds: Int = 10) {
    guardTasks[app.id]?.cancel()
    guardTasks[app.id] = Task { [weak self] in
      for _ in 0..<rounds {
        guard let self, !Task.isCancelled else { return }
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) {
          self.putAway(running)
        }
        try? await Task.sleep(nanoseconds: 250_000_000)
      }
    }
  }

  private func putAway(_ app: NSRunningApplication) {
    let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    if AXIsProcessTrusted() {
      // Close only its big window; the small dictation indicator stays where it is.
      WindowCloser.closeMainWindows(of: app.processIdentifier)
    } else if frontmost {
      app.hide()  // no Accessibility access: hiding is all that's possible
    }
    if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
      let back = lastOtherApp, !back.isTerminated
    {
      back.activate()  // give focus back to what you were typing in
    }
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
        // Apps that still open a window while starting are put away again, for a few seconds.
        if app.background && !windowAllowed.contains(app.id) {
          setGuarded(app, true)
          for _ in 0..<15 {
            for r in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) { putAway(r) }
            try? await Task.sleep(nanoseconds: 300_000_000)
          }
        } else {
          for _ in 0..<15 {
            NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).forEach { $0.hide() }
            try? await Task.sleep(nanoseconds: 300_000_000)
          }
        }
        await wait(app, running: true)
        if app.background { setGuarded(app, true) }
      } else {
        setGuarded(app, false)
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
