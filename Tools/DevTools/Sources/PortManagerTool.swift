import KitbagCore
import SwiftUI

/// Lists what is listening on TCP ports; stop one, or a whole named group, in a click.
/// Opens as a pinned popup from the Dev Tools tab.
@MainActor
public final class PortManagerTool: KitbagTool {
  public static let descriptor = ToolDescriptor(
    id: "portmanager", name: "Port Manager", symbol: "network", showsMenuTab: false,
    popsOut: true, make: { PortManagerTool() })

  private var model: PortManagerModel?
  public init() {}

  public func start() throws { model = PortManagerModel() }

  public func stop() {
    model?.stopPolling()
    model = nil
  }

  public func makeMenuView() -> AnyView {
    guard let model else { return AnyView(EmptyView()) }
    return AnyView(PortManagerView(model: model))
  }
}
