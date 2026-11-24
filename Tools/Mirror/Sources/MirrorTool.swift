import KitbagCore
import SwiftUI

/// A mirror: shows the camera as a pinned popup window. The camera runs only while it is open.
@MainActor
public final class MirrorTool: KitbagTool {
  public static let descriptor = ToolDescriptor(
    id: "mirror", name: "Mirror", symbol: "person.crop.square", showsMenuTab: false,
    popsOut: true, make: { MirrorTool() })

  private var model: MirrorModel?
  public init() {}

  public func start() throws { model = MirrorModel() }

  public func stop() {
    model?.stop()
    model = nil
  }

  public func makeMenuView() -> AnyView {
    guard let model else { return AnyView(EmptyView()) }
    return AnyView(MirrorView(model: model))
  }
}
