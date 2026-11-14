import AppKit
import ApplicationServices

/// Opens the real macOS Wi-Fi / Bluetooth dropdowns. There is no public API for this; it uses
/// the Accessibility API, which needs the Accessibility permission.
///
/// If the item is shown in the menu bar, it is pressed. If it isn't, Control Center is opened and
/// the matching tile is expanded instead.
public enum MenuExtra {
  public enum Outcome: Equatable { case opened, needsPermission, notFound }

  /// Pure matching rule: by accessibility identifier, or by title/description as a fallback.
  static func matches(identifier: String?, text: String?, wantedID: String, wantedText: String)
    -> Bool
  {
    identifier == wantedID || (text?.localizedCaseInsensitiveContains(wantedText) ?? false)
  }

  /// `controlCenterTile` is the tile's accessibility identifier inside Control Center.
  @MainActor
  public static func open(identifier: String, title: String, controlCenterTile: String) async
    -> Outcome
  {
    guard AXIsProcessTrusted() else { return .needsPermission }

    if let item = menuBarItem(identifier: identifier, title: title) {
      return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
        ? .opened : .notFound
    }

    // Not in the menu bar: open Control Center and expand the tile there.
    guard
      let center = menuBarItem(identifier: "com.apple.menuextra.controlcenter", title: "Control"),
      AXUIElementPerformAction(center, kAXPressAction as CFString) == .success
    else { return .notFound }
    for _ in 0..<20 {
      try? await Task.sleep(nanoseconds: 100_000_000)  // the panel takes a moment to appear
      if let tile = controlCenterElement(identifier: controlCenterTile) {
        showDetails(of: tile)
        break
      }
    }
    return .opened  // Control Center itself is open even if the tile couldn't be expanded
  }

  // MARK: Finding elements

  private static let hosts = ["com.apple.MenuBarAgent", "com.apple.controlcenter"]

  /// Recent macOS keeps the menu bar items in MenuBarAgent; older versions in Control Center.
  private static func menuBarItem(identifier: String, title: String) -> AXUIElement? {
    for bundle in hosts {
      guard let proc = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first,
        let bar: AXUIElement = attribute(
          AXUIElementCreateApplication(proc.processIdentifier), "AXExtrasMenuBar"),
        let item = find(
          in: bar, depth: 4,
          where: { element in
            let id: String? = attribute(element, kAXIdentifierAttribute)
            let text: String? =
              attribute(element, kAXDescriptionAttribute) ?? attribute(element, kAXTitleAttribute)
            let role: String? = attribute(element, kAXRoleAttribute)
            return role == kAXMenuBarItemRole as String
              && matches(identifier: id, text: text, wantedID: identifier, wantedText: title)
          })
      else { continue }
      return item
    }
    return nil
  }

  private static func controlCenterElement(identifier: String) -> AXUIElement? {
    guard
      let proc = NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.apple.controlcenter"
      ).first,
      let windows: [AXUIElement] = attribute(
        AXUIElementCreateApplication(proc.processIdentifier), kAXWindowsAttribute)
    else { return nil }
    for w in windows {
      if let found = find(
        in: w, depth: 6,
        where: { (attribute($0, kAXIdentifierAttribute) as String?) == identifier })
      {
        return found
      }
    }
    return nil
  }

  /// Pressing a tile would switch Wi-Fi/Bluetooth off; its "show details" action expands it.
  private static func showDetails(of tile: AXUIElement) {
    var names: CFArray?
    guard AXUIElementCopyActionNames(tile, &names) == .success,
      let action = (names as? [String])?.first(where: {
        $0.localizedCaseInsensitiveContains("show details")
      })
    else { return }
    AXUIElementPerformAction(tile, action as CFString)
  }

  /// The items sit inside nested groups, so search the tree a few levels deep.
  private static func find(
    in element: AXUIElement, depth: Int, where match: (AXUIElement) -> Bool
  ) -> AXUIElement? {
    if match(element) { return element }
    guard depth > 0, let kids: [AXUIElement] = attribute(element, kAXChildrenAttribute) else {
      return nil
    }
    for kid in kids {
      if let found = find(in: kid, depth: depth - 1, where: match) { return found }
    }
    return nil
  }

  private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
      return nil
    }
    return value as? T
  }
}
