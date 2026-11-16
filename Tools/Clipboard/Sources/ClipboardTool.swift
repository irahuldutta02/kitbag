import KitbagCore
import SwiftUI

/// Clipboard history: everything you copy is remembered. Open it from the menu, or press ⌥⌘V
/// anywhere to pick an item at the pointer and paste it.
@MainActor
public final class ClipboardTool: KitbagTool {
  public static let descriptor = ToolDescriptor(
    id: "clipboard", name: "Clipboard", symbol: "doc.on.clipboard", make: { ClipboardTool() })

  private var model: ClipboardModel?
  public init() {}

  public func start() throws {
    let m = ClipboardModel()
    m.start()
    model = m
  }

  public func stop() {
    model?.stop()
    model = nil
  }

  public func makeMenuView() -> AnyView {
    guard let model else { return AnyView(EmptyView()) }
    return AnyView(ClipboardView(model: model))
  }

  public func makeSettingsView() -> AnyView? {
    guard let model else { return nil }
    return AnyView(ClipboardSettingsView(model: model))
  }
}
