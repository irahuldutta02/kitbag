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
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
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
    for d in descriptors where isEnabled(d.id) && isAvailable(d) { activate(d) }
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

  private func activate(_ d: ToolDescriptor) {
    guard active[d.id] == nil else { return }
    let tool = d.make()
    do {
      try tool.start()
      active[d.id] = tool
      errors[d.id] = nil
      tool.menuVisibilityChanged(d.id == visibleToolID)
      publishFileSenders()
    } catch {
      tool.stop()
      errors[d.id] = error.localizedDescription
    }
  }

  private func deactivate(_ id: String) {
    active.removeValue(forKey: id)?.stop()
    errors[id] = nil
    publishFileSenders()
  }
}
