import KitbagCore
import SwiftUI

/// Press a shortcut anywhere, speak, and the cleaned-up text is pasted into the app in front.
@MainActor
public final class DictationTool: KitbagTool {
  public static let descriptor = ToolDescriptor(
    id: "dictation", name: "Dictation", symbol: "mic.fill", defaultEnabled: false,
    showsMenuTab: false, listedInApps: true, appsCategory: "dictation", make: { DictationTool() })

  private var model: DictationModel?
  public init() {}

  public func start() throws {
    let m = DictationModel()
    try m.start()
    model = m
  }

  public func stop() {
    model?.stop()
    model = nil
  }

  public func menuVisibilityChanged(_ visible: Bool) { if visible { model?.refreshStatus() } }

  public func makeMenuView() -> AnyView {
    guard let model else { return AnyView(EmptyView()) }
    return AnyView(DictationView(model: model))
  }

  public func makeSettingsView() -> AnyView? {
    guard let model else { return nil }
    return AnyView(DictationSettingsView(model: model, settings: model.settings, local: model.local))
  }
}
