import AppKit
import SwiftUI

/// Central registry: owns enable state and the live instances of enabled tools.
@MainActor
public final class ToolManager: ObservableObject {
  public let descriptors: [ToolDescriptor]
  @Published public private(set) var active: [String: any KitbagTool] = [:]
  @Published public private(set) var errors: [String: String] = [:]
  private let defaults: UserDefaults
  private let isInstalled: (String) -> Bool
  private var visibleToolID: String?

  public init(
    descriptors: [ToolDescriptor], defaults: UserDefaults = .standard,
    isInstalled: @escaping (String) -> Bool = ToolManager.systemHasApp
  ) {
    self.descriptors = descriptors
    self.defaults = defaults
    self.isInstalled = isInstalled
  }

  public nonisolated static func systemHasApp(_ bundleID: String) -> Bool {
    // LaunchServices can still list removed apps, or Homebrew's backup copy in the Caskroom,
    // so only count a copy that really sits in an Applications folder.
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
      return false
    }
    let roots = ["/Applications/", NSHomeDirectory() + "/Applications/", "/System/Applications/"]
    return roots.contains { url.path.hasPrefix($0) } && FileManager.default.fileExists(atPath: url.path)
  }

  /// Tools that need another app are available only while that app is installed.
  public func isAvailable(_ d: ToolDescriptor) -> Bool {
    d.requiresApp.map(isInstalled) ?? true
  }

  private func key(_ id: String) -> String { "kitbag.enabled.\(id)" }

  public func isEnabled(_ id: String) -> Bool {
    if let v = defaults.object(forKey: key(id)) as? Bool { return v }
    return descriptors.first { $0.id == id }?.defaultEnabled ?? false
  }

  /// Creates instances for enabled tools only.
  public func bootstrap() {
    startWatching()
    for d in descriptors where isEnabled(d.id) && isAvailable(d) { activate(d) }
  }

  private var observers: [(NotificationCenter, NSObjectProtocol)] = []
  private var dirWatchers: [DispatchSourceFileSystemObject] = []

  /// Keeps the tool list in step with what is installed: on wake, on focus, and whenever an app
  /// is added to or removed from the Applications folders.
  private func startWatching() {
    guard observers.isEmpty else { return }
    let sync: @Sendable () -> Void = { [weak self] in Task { @MainActor in self?.refreshAvailability() } }
    let ws = NSWorkspace.shared.notificationCenter
    observers.append((ws, ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in sync() }))
    let nc = NotificationCenter.default
    observers.append((nc, nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in sync() }))
    for path in ["/Applications", NSHomeDirectory() + "/Applications"] {
      let fd = open(path, O_EVTONLY)
      guard fd >= 0 else { continue }
      let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
      src.setEventHandler { DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: sync) }  // let the copy finish
      src.setCancelHandler { close(fd) }
      src.resume()
      dirWatchers.append(src)
    }
  }

  /// Call after installing an app: activates enabled tools that just became available.
  public func refreshAvailability() {
    for d in descriptors where !isAvailable(d) { deactivate(d.id) }  // app was uninstalled
    bootstrap()
    objectWillChange.send()
  }

  public func setEnabled(_ id: String, _ on: Bool) {
    guard let d = descriptors.first(where: { $0.id == id }) else { return }
    defaults.set(on, forKey: key(id))
    if on && isAvailable(d) { activate(d) } else { deactivate(id) }
  }

  public var enabledTools: [(descriptor: ToolDescriptor, tool: any KitbagTool)] {
    descriptors.compactMap { d in active[d.id].map { (d, $0) } }
  }

  /// Only the tool whose tab is showing counts as visible; nil means the menu is closed.
  public func setVisibleTool(_ id: String?) {
    visibleToolID = id
    for (toolID, tool) in active { tool.menuVisibilityChanged(toolID == id) }
  }

  /// Tells every active tool which file senders exist, so tools can offer them.
  private func publishFileSenders() {
    let senders = descriptors.compactMap { active[$0.id] }.flatMap(\.fileSenders)
    for tool in active.values { tool.receiveFileSenders(senders) }
  }

  /// Tells every active tool which on/off switches the Apps tab can show.
  private func publishToolSwitches() {
    let switches = descriptors.filter(\.listedInApps).map { d in
      ToolSwitch(
        id: d.id, name: d.name, symbol: d.symbol, category: d.appsCategory,
        isOn: isEnabled(d.id) && isAvailable(d), error: errors[d.id],
        set: { [weak self] on in self?.setEnabled(d.id, on) })
    }
    for tool in active.values { tool.receiveToolSwitches(switches) }
  }

  private func activate(_ d: ToolDescriptor) {
    guard active[d.id] == nil else { return }
    let tool = d.make()
    do {
      try tool.start()
      active[d.id] = tool
      errors[d.id] = nil
      tool.menuVisibilityChanged(d.id == visibleToolID)
      publishFileSenders()
      publishToolSwitches()
    } catch {
      tool.stop()
      errors[d.id] = error.localizedDescription
      publishToolSwitches()
    }
  }

  private func deactivate(_ id: String) {
    active.removeValue(forKey: id)?.stop()
    errors[id] = nil
    publishFileSenders()
    publishToolSwitches()
  }
}
