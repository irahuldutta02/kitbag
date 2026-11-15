import KitbagCore
import SwiftUI

@MainActor
public final class DevToolsTool: KitbagTool {
  public static let descriptor = ToolDescriptor(
    id: "devtools", name: "Dev Tools", symbol: "chevron.left.forwardslash.chevron.right",
    make: { DevToolsTool() })

  private var model: DevToolsModel?
  private let services = ServicesModel()
  public init() {}

  public func start() throws {
    model = DevToolsModel()
    services.startObserving()
  }

  public func stop() {
    services.setPolling(false)
    services.stopObserving()
    model?.stop()
    model = nil
  }

  public func menuVisibilityChanged(_ visible: Bool) { services.setPolling(visible) }

  public func makeSettingsView() -> AnyView? { AnyView(DevToolsSettingsView(model: services)) }

  public func makeMenuView() -> AnyView {
    guard let model else { return AnyView(EmptyView()) }
    return AnyView(DevToolsView(model: model, services: services))
  }
}
