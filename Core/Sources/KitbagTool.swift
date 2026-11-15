import SwiftUI

/// A self-contained tool. Instances exist only while the tool is enabled.
@MainActor
public protocol KitbagTool: AnyObject {
  /// Acquire resources. Throwing marks the tool as failed without affecting others.
  func start() throws
  /// Release everything (timers, observers, security scopes). Called before the instance is dropped.
  func stop()
  /// Called when this tool's tab becomes visible/hidden; pause polling while hidden.
  func menuVisibilityChanged(_ visible: Bool)
  /// Built only when the menu is shown.
  func makeMenuView() -> AnyView
  func makeSettingsView() -> AnyView?
  /// True if the tool's tab should be offered while files are being dragged over the menu icon.
  var acceptsFileDrops: Bool { get }
  /// Ways this tool offers to send files somewhere (for example another app). The manager passes
  /// the senders of all active tools to every tool through `receiveFileSenders`.
  var fileSenders: [FileSender] { get }
  func receiveFileSenders(_ senders: [FileSender])
}

public struct FileSendResult {
  public let success: Bool
  public let message: String?
  public init(success: Bool, message: String? = nil) {
    self.success = success
    self.message = message
  }
}

/// "Send these files with X". Lets one tool offer a destination to another without either
/// knowing about the other.
public struct FileSender: Identifiable {
  public let id: String
  public let title: String
  public let icon: @MainActor () -> AnyView
  /// Sends the files; returns whether it worked and a short status message to show, if any.
  public let send: @MainActor ([URL]) async -> FileSendResult

  public init(
    id: String, title: String, icon: @escaping @MainActor () -> AnyView,
    send: @escaping @MainActor ([URL]) async -> FileSendResult
  ) {
    self.id = id
    self.title = title
    self.icon = icon
    self.send = send
  }
}

extension KitbagTool {
  public var acceptsFileDrops: Bool { false }
  public var fileSenders: [FileSender] { [] }
  public func receiveFileSenders(_ senders: [FileSender]) {}
  public func menuVisibilityChanged(_ visible: Bool) {}
  public func makeSettingsView() -> AnyView? { nil }
}

/// Cheap, static description of a tool. The tool itself is created lazily via `make`.
public struct ToolDescriptor: Identifiable {
  public let id: String
  public let name: LocalizedStringKey
  public let symbol: String
  public let defaultEnabled: Bool
  /// For brands with no SF Symbol (e.g. Bluetooth); shown instead of `symbol` when set.
  public let customIcon: (@MainActor () -> AnyView)?
  /// For integrations with another app: its bundle id. The tool is offered only if that app is installed.
  public let requiresApp: String?
  /// Homebrew cask that installs `requiresApp`; Settings offers it while the app is missing.
  public let brewCask: String?
  /// False for tools that only add features to other tools and have no tab of their own.
  public let showsTab: Bool
  public let make: @MainActor () -> any KitbagTool

  public init(
    id: String, name: LocalizedStringKey, symbol: String, defaultEnabled: Bool = true,
    customIcon: (@MainActor () -> AnyView)? = nil, requiresApp: String? = nil, brewCask: String? = nil,
    showsTab: Bool = true,
    make: @escaping @MainActor () -> any KitbagTool
  ) {
    self.customIcon = customIcon
    self.requiresApp = requiresApp
    self.brewCask = brewCask
    self.showsTab = showsTab
    self.id = id
    self.name = name
    self.symbol = symbol
    self.defaultEnabled = defaultEnabled
    self.make = make
  }
}

extension Notification.Name {
  /// Posted by a tool when a file drag ended over it (dropped or left), so the menu can show all tabs again.
  public static let kitbagFileDropFinished = Notification.Name("kitbag.fileDropFinished")
}

/// The tool's icon: its custom glyph if it has one, otherwise its SF Symbol. Every icon is fitted
/// into the same square so tab bars and lists look even.
public struct ToolIcon: View {
  let descriptor: ToolDescriptor
  public init(_ descriptor: ToolDescriptor) { self.descriptor = descriptor }
  public var body: some View {
    Group {
      if let custom = descriptor.customIcon {
        custom()
      } else {
        Image(systemName: descriptor.symbol).resizable().scaledToFit().frame(width: 16, height: 16)
      }
    }
    .frame(width: 18, height: 18)
  }
}
