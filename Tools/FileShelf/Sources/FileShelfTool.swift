import KitbagCore
import SwiftUI

@MainActor
public final class FileShelfTool: KitbagTool {
  public static let descriptor = ToolDescriptor(
    id: "fileshelf", name: "File Shelf", symbol: "tray.and.arrow.down",
    make: { FileShelfTool() })

  private var model: ShelfModel?
  public init() {}

  public var acceptsFileDrops: Bool { true }

  public func start() throws { model = ShelfModel() }

  public func receiveFileSenders(_ senders: [FileSender]) { model?.senders = senders }

  public func stop() {
    model?.shutdown()
    model = nil
  }

  public func menuVisibilityChanged(_ visible: Bool) {
    if visible { model?.refresh() }
  }

  public func makeMenuView() -> AnyView {
    guard let model else { return AnyView(EmptyView()) }
    return AnyView(ShelfView(model: model))
  }

  public func makeSettingsView() -> AnyView? {
    guard let model else { return nil }
    return AnyView(ShelfSettingsView(model: model))
  }
}

struct ShelfSettingsView: View {
  @ObservedObject var model: ShelfModel

  var body: some View {
    Toggle("Clear the shelf after items are dropped", isOn: $model.clearAfterDrop)
  }
}
