import KitbagCore
import SwiftUI

@MainActor
public final class DevToolsTool: KitbagTool {
  public static let descriptor = ToolDescriptor(
    id: "devtools", name: "Dev Tools", symbol: "chevron.left.forwardslash.chevron.right",
    make: { DevToolsTool() })

  private var model: DevToolsModel?
  public init() {}

  public func start() throws { model = DevToolsModel() }

  public func stop() {
    model?.stop()
    model = nil
  }

  public func makeMenuView() -> AnyView {
    guard let model else { return AnyView(EmptyView()) }
    return AnyView(DevToolsView(model: model))
  }
}
