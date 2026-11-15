import AppKit
import KitbagCore
import SwiftUI

/// Integration with the Blip app: adds "Send with Blip" to the File Shelf. It has no tab of its own.
@MainActor
public final class BlipTool: KitbagTool {
  public nonisolated static let bundleID = "net.blip.macos"

  public static let descriptor = ToolDescriptor(
    id: "blip", name: "Blip", symbol: "paperplane.fill",
    customIcon: { BlipTool.appIcon(size: 18) },
    requiresApp: bundleID, brewCask: "blip", showsTab: false, make: { BlipTool() })

  static func appIcon(size: CGFloat) -> AnyView {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
      return AnyView(Image(systemName: "paperplane.fill"))
    }
    let icon = NSWorkspace.shared.icon(forFile: url.path)
    icon.size = NSSize(width: size, height: size)
    return AnyView(Image(nsImage: icon))
  }

  private var model: BlipModel?
  public init() {}

  public func start() throws {
    model = BlipModel()
    model?.observe()
  }
  public func stop() {
    model?.stopObserving()
    model = nil
  }

  public var fileSenders: [FileSender] {
    guard let model else { return [] }
    return [
      FileSender(
        id: "blip", title: "Blip", icon: { BlipTool.appIcon(size: 20) },
        send: { await model.send($0) })
    ]
  }

  public func makeMenuView() -> AnyView { AnyView(EmptyView()) }
}
