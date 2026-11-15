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
    Picker("After converting", selection: $model.afterConvert) {
      Text("Keep the shelf as it is").tag(AfterConvert.keep)
      Text("Replace originals with converted files").tag(AfterConvert.replace)
      Text("Remove converted originals").tag(AfterConvert.remove)
    }
    LabeledContent("Image quality (JPG, HEIC)") {
      HStack(spacing: 10) {
        Slider(value: $model.convertQuality, in: 0.3...1).frame(width: 200)
        Text("\(Int((model.convertQuality * 100).rounded()))%")
          .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
          .frame(width: 40, alignment: .trailing)
      }
    }
  }
}
