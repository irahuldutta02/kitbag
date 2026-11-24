import KitbagCore
import SwiftUI

/// A small calculator that opens as a popup window (with a pin option) from the Apps tab.
@MainActor
public final class CalculatorTool: KitbagTool {
  public static let descriptor = ToolDescriptor(
    id: "calculator", name: "Calculator", symbol: "plus.forwardslash.minus",
    showsMenuTab: false, popsOut: true,
    make: { CalculatorTool() })

  private var model: CalculatorModel?
  public init() {}

  public func start() throws { model = CalculatorModel() }
  public func stop() { model = nil }

  public func makeMenuView() -> AnyView {
    guard let model else { return AnyView(EmptyView()) }
    return AnyView(CalculatorView(model: model))
  }
}
