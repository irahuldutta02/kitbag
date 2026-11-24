import KitbagCore
import SwiftUI

/// Quick on/off switches for other apps, so you don't have to open them. To add an app, add it to
/// `AppsModel.catalog`.
@MainActor
public final class AppsTool: KitbagTool {
  public static let descriptor = ToolDescriptor(
    id: "apps", name: "Quick Toggle", symbol: "power", make: { AppsTool() })

  private var model: AppsModel?
  public init() {}

  public func start() throws {
    let m = AppsModel()
    m.observe()
    model = m
  }

  public func stop() {
    model?.stopObserving()
    model = nil
  }

  public func receiveToolSwitches(_ switches: [ToolSwitch]) { model?.toolSwitches = switches }

  public func menuVisibilityChanged(_ visible: Bool) { if visible { model?.refresh() } }

  public func makeMenuView() -> AnyView {
    guard let model else { return AnyView(EmptyView()) }
    return AnyView(AppsView(model: model))
  }

  public func makeSettingsView() -> AnyView? {
    guard let model else { return nil }
    return AnyView(AppsSettingsView(model: model))
  }
}
