import Foundation

/// What the menu bar pop-up shows: which tabs, and the Wi-Fi / Bluetooth buttons. Everything is
/// shown unless switched off; the choice is remembered.
@MainActor
public final class MenuLayout: ObservableObject {
  public static let shared = MenuLayout()
  public static let wifi = "wifi"
  public static let bluetooth = "bluetooth"

  private static let key = "kitbag.menu.hidden"
  @Published public private(set) var hidden: Set<String>

  private init() {
    hidden = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
  }

  public func isShown(_ id: String) -> Bool { !hidden.contains(id) }

  public func setShown(_ id: String, _ on: Bool) {
    if on { hidden.remove(id) } else { hidden.insert(id) }
    UserDefaults.standard.set(Array(hidden), forKey: Self.key)
  }
}
