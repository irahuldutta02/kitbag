import AppKit
import Carbon.HIToolbox
import KitbagCore
import SwiftUI

/// Use-case grouping for companion apps and Kitbag tools shown in the Apps tab.
enum AppCategory: String, CaseIterable, Identifiable {
  case dictation
  case cloudStorage
  case audio

  var id: String { rawValue }

  var name: String {
    switch self {
    case .dictation: return "Dictation"
    case .cloudStorage: return "Cloud Storage"
    case .audio: return "Audio"
    }
  }

  var title: LocalizedStringKey { LocalizedStringKey(name) }

  /// Only one thing in the category can be on at a time (two dictation apps would fight over the hotkey).
  var isExclusive: Bool { self == .dictation }

  var symbol: String {
    switch self {
    case .dictation: return "waveform"
    case .cloudStorage: return "icloud"
    case .audio: return "speaker.wave.2"
    }
  }
}

/// A non-empty group of switches and companion apps rendered together in a category card.
struct AppCategoryGroup: Identifiable {
  let id: String
  let title: LocalizedStringKey
  let symbol: String
  let category: AppCategory?
  let switches: [ToolSwitch]
  let apps: [ManagedApp]
}

/// An app Kitbag can switch on and off.
struct ManagedApp: Identifiable {
  let id: String
  let name: String
  let bundleID: String
  let category: AppCategory
  /// Dictation apps that keep working without a window. When Kitbag switches one on, its window
  /// is kept out of sight (the hotkey would otherwise bring it back every time you dictate).
  var background = false
}

@MainActor
final class AppsModel: ObservableObject {
  static let catalog = [
    ManagedApp(id: "gdrive", name: "Google Drive", bundleID: "com.google.drivefs", category: .cloudStorage),
    ManagedApp(id: "pdrive", name: "Proton Drive", bundleID: "ch.protonmail.drive", category: .cloudStorage),
    ManagedApp(
      id: "wispr", name: "Wispr Flow", bundleID: "com.electron.wispr-flow", category: .dictation,
      background: true),
    ManagedApp(
      id: "openwhispr", name: "OpenWhispr", bundleID: "com.gizmolabs.openwhispr", category: .dictation,
      background: true),
    ManagedApp(id: "finetune", name: "FineTune", bundleID: "com.finetuneapp.FineTune", category: .audio),
  ]

  static let defaultShortcut = KeyShortcut(
    keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(controlKey | optionKey), label: "A")
  private static let shortcutPrefix = "kitbag.apps.shortcut"

  @Published private(set) var running: Set<String> = []
  @Published private(set) var busy: Set<String> = []
  @Published private(set) var installed: Set<String> = []
  @Published var notice: String?
  /// Kitbag's own tools that can be switched here too (for example Dictation).
  @Published var toolSwitches: [ToolSwitch] = []
  /// Apps the user chose not to show in the Apps tab.
  @Published private(set) var hidden: Set<String>
  /// Background apps the user wants to see the window of (turns the keep-out-of-the-way off).
  @Published private(set) var windowAllowed: Set<String>
  /// The key combination that opens the Apps tab anywhere; `nil` when turned off.
  @Published private(set) var shortcut: KeyShortcut?
  /// False if another app already owns the shortcut.
  @Published private(set) var shortcutWorks = true

  private let defaults: UserDefaults
  private let hotKey = GlobalHotKey()
  private var hotKeyEnabled = false

  /// Only apps that are installed and not hidden; anything missing is listed in Settings instead.
  var visible: [ManagedApp] { Self.catalog.filter { installed.contains($0.id) && !hidden.contains($0.id) } }

  /// Groups visible apps and tool switches by use-case category, omitting empty categories.
  /// Any `ToolSwitch` whose `category` is nil or unrecognized lands in a fallback "Kitbag Tools" group.
  func grouped(apps: [ManagedApp]? = nil, switches: [ToolSwitch]? = nil) -> [AppCategoryGroup] {
    let activeApps = apps ?? visible
    let activeSwitches = switches ?? toolSwitches
    var groups: [AppCategoryGroup] = []
    for cat in AppCategory.allCases {
      let catSwitches = activeSwitches.filter {
        $0.category.flatMap(AppCategory.init(rawValue:)) == cat
      }
      let catApps = activeApps.filter { $0.category == cat }
      if !catSwitches.isEmpty || !catApps.isEmpty {
        groups.append(
          AppCategoryGroup(
            id: cat.id, title: cat.title, symbol: cat.symbol,
            category: cat, switches: catSwitches, apps: catApps))
      }
    }
    let fallbackSwitches = activeSwitches.filter {
      $0.category.flatMap(AppCategory.init(rawValue:)) == nil
    }
    if !fallbackSwitches.isEmpty {
      groups.append(
        AppCategoryGroup(
          id: "kitbag-tools", title: "Kitbag Tools", symbol: "square.grid.2x2",
          category: nil, switches: fallbackSwitches, apps: []))
    }
    return groups
  }

  var groupedVisible: [AppCategoryGroup] { grouped() }

  func setShown(_ app: ManagedApp, _ on: Bool) {
    if on { hidden.remove(app.id) } else { hidden.insert(app.id) }
    defaults.set(Array(hidden), forKey: "kitbag.apps.hidden")
  }

  func setWindowAllowed(_ app: ManagedApp, _ on: Bool) {
    if on { windowAllowed.insert(app.id) } else { windowAllowed.remove(app.id) }
    defaults.set(Array(windowAllowed), forKey: "kitbag.apps.windowAllowed")
  }

  /// Apps Kitbag switched on, whose window it keeps out of the way. Remembered across Kitbag restarts.
  private var guarded: Set<String>
  private func setGuarded(_ app: ManagedApp, _ on: Bool) {
    if on { guarded.insert(app.id) } else { guarded.remove(app.id) }
    defaults.set(Array(guarded), forKey: "kitbag.apps.guarded")
  }
  private var lastOtherApp: NSRunningApplication?
  private var guardTasks: [String: Task<Void, Never>] = [:]
  private var observers: [NSObjectProtocol] = []

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    hidden = Set(defaults.stringArray(forKey: "kitbag.apps.hidden") ?? [])
    windowAllowed = Set(defaults.stringArray(forKey: "kitbag.apps.windowAllowed") ?? [])
    guarded = Set(defaults.stringArray(forKey: "kitbag.apps.guarded") ?? [])
    shortcut = KeyShortcut.load(
      from: defaults, prefix: Self.shortcutPrefix, default: Self.defaultShortcut)
  }

  func observe(registerHotKey: Bool = true) {
    if registerHotKey && !hotKeyEnabled {
      hotKeyEnabled = true
      hotKey.onPress = {
        NotificationCenter.default.post(name: .kitbagOpenTab, object: "apps")
      }
      registerShortcut()
    }
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
    hotKey.unregister()
    hotKeyEnabled = false
    guardTasks.values.forEach { $0.cancel() }
    guardTasks = [:]
    observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    observers = []
  }

  // MARK: Shortcut

  private func registerShortcut() {
    guard let s = shortcut else {
      hotKey.unregister()
      shortcutWorks = true
      return
    }
    shortcutWorks = hotKey.register(keyCode: s.keyCode, modifiers: s.modifiers)
  }

  /// Switches to a new shortcut (or turns it off with `nil`). If another app already owns it,
  /// the old one stays and this returns false.
  @discardableResult
  func setShortcut(_ new: KeyShortcut?) -> Bool {
    if hotKeyEnabled, let new {
      guard hotKey.register(keyCode: new.keyCode, modifiers: new.modifiers) else {
        if let old = shortcut { hotKey.register(keyCode: old.keyCode, modifiers: old.modifiers) }
        return false
      }
    } else if hotKeyEnabled {
      hotKey.unregister()
    }
    shortcut = new
    shortcutWorks = true
    KeyShortcut.save(new, to: defaults, prefix: Self.shortcutPrefix)
    return true
  }

  /// While a new shortcut is being typed, the current one must not fire.
  func pauseHotKey(_ pause: Bool) {
    guard hotKeyEnabled else { return }
    if pause { hotKey.unregister() } else { registerShortcut() }
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

  /// Switches one of Kitbag's own tools. In an exclusive category (dictation) the other tools and apps go off.
  func setSwitch(_ sw: ToolSwitch, on: Bool) {
    if on, let cat = sw.category.flatMap(AppCategory.init(rawValue:)), cat.isExclusive {
      turnOffOthers(in: cat, except: sw.id)
    }
    sw.set(on)
  }

  private func turnOffOthers(in cat: AppCategory, except id: String) {
    for other in toolSwitches where other.id != id && other.isOn
      && other.category.flatMap(AppCategory.init(rawValue:)) == cat
    {
      other.set(false)
    }
    for app in Self.catalog where app.id != id && app.category == cat && running.contains(app.id) {
      set(app, on: false)
    }
  }

  /// Starts or quits the app without taking focus from what you're doing.
  func set(_ app: ManagedApp, on: Bool) {
    if on && app.category.isExclusive { turnOffOthers(in: app.category, except: app.id) }
    guard !busy.contains(app.id) else { return }
    busy.insert(app.id)
    notice = nil
    Task {
      defer { busy.remove(app.id); refresh() }
      if on {
        guard let url = url(app) else { return notice = String(localized: "\(app.name) isn't installed.") }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        // Only dictation apps (Wispr Flow) open a window we need to keep away; hiding other apps
        // (e.g. menu bar apps like FineTune) would also close their menu bar popover.
        config.hides = app.background
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
