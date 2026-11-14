import KitbagCore
import SwiftUI

@MainActor
public final class SpeedTestTool: KitbagTool {
  public static let descriptor = ToolDescriptor(
    id: "speedtest", name: "Speed Test", symbol: "arrow.up.arrow.down", make: { SpeedTestTool() })

  private var model: SpeedTestModel?
  public init() {}

  public func start() throws { model = SpeedTestModel() }

  public func stop() {
    model?.cancel()
    model = nil
  }

  /// Leaving the tab (or closing the menu) stops a running test and clears its results.
  public func menuVisibilityChanged(_ visible: Bool) {
    if !visible { model?.reset() }
  }

  public func makeMenuView() -> AnyView {
    guard let model else { return AnyView(EmptyView()) }
    return AnyView(SpeedTestView(model: model))
  }
}
