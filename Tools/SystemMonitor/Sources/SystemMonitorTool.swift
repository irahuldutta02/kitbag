import KitbagCore
import SwiftUI

@MainActor
public final class SystemMonitorTool: KitbagTool {
  public static let descriptor = ToolDescriptor(
    id: "systemmonitor", name: "System Monitor", symbol: "gauge.with.dots.needle.50percent",
    make: { SystemMonitorTool() })

  private var model: MonitorModel?
  public init() {}

  public func start() throws { model = MonitorModel() }

  public func stop() {
    model?.stopTimer()
    model = nil
  }

  public func menuVisibilityChanged(_ visible: Bool) { model?.setActive(visible) }

  public func makeMenuView() -> AnyView {
    guard let model else { return AnyView(EmptyView()) }
    return AnyView(MonitorView(model: model))
  }

  public func makeSettingsView() -> AnyView? {
    guard let model else { return nil }
    return AnyView(MonitorSettingsView(model: model))
  }
}
