import AppKit
import Foundation

/// Shows or hides another app's own menu bar icon. macOS remembers a status item's visibility in
/// that app's preferences (the same switch as the app's "Allow in the Menu Bar" entry or ⌘-dragging
/// the icon out), and reads it when the item is created, so a change applies the next time the app
/// starts. Both the current key (`VisibleCC`) and the older one (`Visible`) are written.
public enum AppMenuIcon {
  private static let keys = ["NSStatusItem VisibleCC Item-0", "NSStatusItem Visible Item-0"]

  /// Whether the icon is shown; `unset` is what the app does when nothing has been chosen yet.
  public static func isVisible(_ bundleIDs: [String], unset: Bool = true) -> Bool {
    for id in bundleIDs {
      for key in keys {
        if let v = CFPreferencesCopyAppValue(key as CFString, id as CFString) as? Bool { return v }
      }
    }
    return unset
  }

  public static func setVisible(_ visible: Bool, _ bundleIDs: [String]) {
    for id in bundleIDs {
      for key in keys {
        CFPreferencesSetAppValue(key as CFString, visible as CFBoolean, id as CFString)
      }
      CFPreferencesAppSynchronize(id as CFString)
    }
  }

  /// macOS also has its own per-app "Allow in the Menu Bar" switch (System Settings ▸ Menu Bar).
  /// If that is off the icon never appears, whatever the app's own setting says. It can only be
  /// changed by the user, so this opens the pane.
  public static func openSystemSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
      NSWorkspace.shared.open(url)
    }
  }
}
