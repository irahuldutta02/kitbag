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
  /// Tools that want a quick on/off switch in the Apps tab. The manager passes them to every tool.
  func receiveToolSwitches(_ switches: [ToolSwitch])
  /// The user just switched this tool on (a switch, or opening it from the Apps grid), as opposed to
  /// it starting with the app. Tools that run a service (Video Player's server) can start it here.
  func switchedOnByUser()
}

/// A tool's on/off switch, offered to the Apps tab so it can sit next to the other apps.
public struct ToolSwitch: Identifiable {
  public let id: String
  public let name: LocalizedStringKey
  public let symbol: String
  /// Optional use-case category id (e.g. "dictation") so the Apps tab can group it with related apps.
  public let category: String?
  public let isOn: Bool
  /// Why the tool couldn't start, if it failed.
  public let error: String?
  public let set: @MainActor (Bool) -> Void
  public init(
    id: String, name: LocalizedStringKey, symbol: String, category: String? = nil,
    isOn: Bool, error: String?, set: @escaping @MainActor (Bool) -> Void
  ) {
    self.id = id
    self.name = name
    self.symbol = symbol
    self.category = category
    self.isOn = isOn
    self.error = error
    self.set = set
  }
}

public struct FileSendResult {
  public let success: Bool
  public let message: String?
  public init(success: Bool, message: String? = nil) {
    self.success = success
    self.message = message
  }
}

/// An on/off switch for the app behind a sender (for example Blip), shown on the shelf.
@MainActor
public final class SenderPower: ObservableObject {
  @Published public var isOn = false
  @Published public var isBusy = false
  public let set: @MainActor (Bool) -> Void
  public init(set: @escaping @MainActor (Bool) -> Void) { self.set = set }
}

/// "Send these files with X". Lets one tool offer a destination to another without either
/// knowing about the other.
public struct FileSender: Identifiable {
  public let id: String
  public let title: String
  public let icon: @MainActor () -> AnyView
  /// Sends the files; returns whether it worked and a short status message to show, if any.
  public let send: @MainActor ([URL]) async -> FileSendResult
  /// Manual on/off switch for the destination app, if it can be switched.
  public let power: SenderPower?
  /// Files were dropped on the shelf: get ready (for example start the app).
  public let prepare: (@MainActor () -> Void)?
  /// The shelf is empty again: nothing is waiting to be sent.
  public let release: (@MainActor () -> Void)?

  public init(
    id: String, title: String, icon: @escaping @MainActor () -> AnyView,
    power: SenderPower? = nil, prepare: (@MainActor () -> Void)? = nil,
    release: (@MainActor () -> Void)? = nil,
    send: @escaping @MainActor ([URL]) async -> FileSendResult
  ) {
    self.power = power
    self.prepare = prepare
    self.release = release
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
  public func receiveToolSwitches(_ switches: [ToolSwitch]) {}
  public func switchedOnByUser() {}
  public func menuVisibilityChanged(_ visible: Bool) {}
  public func makeSettingsView() -> AnyView? { nil }
}

/// Cheap, static description of a tool. The tool itself is created lazily via `make`.
public struct ToolDescriptor: Identifiable {
  public let id: String
  public let name: LocalizedStringKey
  public let symbol: String
  public let defaultEnabled: Bool
  /// For brands with no SF Symbol (e.g. an app's own logo); shown instead of `symbol` when set.
  public let customIcon: (@MainActor () -> AnyView)?
  /// For integrations with another app: its bundle id. The tool is offered only if that app is installed.
  public let requiresApp: String?
  /// Homebrew cask that installs `requiresApp`; Settings offers it while the app is missing.
  public let brewCask: String?
  /// False for tools that only add features to other tools and have no tab of their own.
  public let showsTab: Bool
  /// False for tools that have a Settings page but no tab in the menu pop-up.
  public let showsMenuTab: Bool
  /// True to offer this tool's on/off switch in the Apps tab.
  public let listedInApps: Bool
  /// Optional use-case category id when listed in the Apps tab (e.g. "dictation").
  public let appsCategory: String?
  /// True if the tool can open its view as a popup window with a pin option (from the Apps tab).
  public let popsOut: Bool
  public let make: @MainActor () -> any KitbagTool

  public init(
    id: String, name: LocalizedStringKey, symbol: String, defaultEnabled: Bool = false,
    customIcon: (@MainActor () -> AnyView)? = nil, requiresApp: String? = nil, brewCask: String? = nil,
    showsTab: Bool = true, showsMenuTab: Bool = true, listedInApps: Bool = false,
    appsCategory: String? = nil, popsOut: Bool = false,
    make: @escaping @MainActor () -> any KitbagTool
  ) {
    self.customIcon = customIcon
    self.requiresApp = requiresApp
    self.brewCask = brewCask
    self.showsTab = showsTab
    self.showsMenuTab = showsMenuTab
    self.listedInApps = listedInApps
    self.appsCategory = appsCategory
    self.popsOut = popsOut
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
  /// Posted by a tool that is about to open its own window or take a screenshot, so the menu
  /// pop-up gets out of the way first.
  public static let kitbagCloseMenu = Notification.Name("kitbag.closeMenu")
  /// Posted by a tool's global shortcut to open (or toggle) the menu pop-up directly to that tool's tab.
  /// Pass `object: toolID` (String).
  public static let kitbagOpenTab = Notification.Name("kitbag.openTab")
  /// Posted to open the Settings window directly to a given page id (`object: pageID` String).
  /// Posted to open a tool's view as a popup window with a pin option (`object: toolID` String).
  public static let kitbagOpenPopup = Notification.Name("kitbag.openPopup")
  public static let kitbagOpenSettings = Notification.Name("kitbag.openSettings")
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
        // Same point size for every symbol (scaling to fit made wide and narrow glyphs differ in size).
        Image(systemName: descriptor.symbol).font(.system(size: 14, weight: .medium))
      }
    }
    .frame(width: 18, height: 18)
  }
}
