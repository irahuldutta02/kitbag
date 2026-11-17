import AppKit
import ApplicationServices

/// Closes another app's ordinary windows (needs Accessibility access) while leaving its small
/// floating panels, such as a dictation indicator, alone.
enum WindowCloser {
  /// Windows smaller than this are treated as indicators, not the app's main window.
  private static let minimumSize = CGSize(width: 320, height: 220)

  @discardableResult
  static func closeMainWindows(of pid: pid_t) -> Int {
    let app = AXUIElementCreateApplication(pid)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
      let windows = value as? [AXUIElement]
    else { return 0 }
    var closed = 0
    for window in windows where isMainWindow(window) {
      if press(window, kAXCloseButtonAttribute) {
        closed += 1
      } else if AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success {
        closed += 1
      }
    }
    return closed
  }

  private static func isMainWindow(_ window: AXUIElement) -> Bool {
    if string(window, kAXSubroleAttribute) != (kAXStandardWindowSubrole as String) { return false }
    if bool(window, kAXMinimizedAttribute) == true { return false }
    var size = CGSize.zero
    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success, let v = value,
      CFGetTypeID(v) == AXValueGetTypeID()
    {
      AXValueGetValue(v as! AXValue, .cgSize, &size)
    }
    return size.width >= minimumSize.width && size.height >= minimumSize.height
  }

  private static func press(_ element: AXUIElement, _ attribute: String) -> Bool {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let v = value,
      CFGetTypeID(v) == AXUIElementGetTypeID()
    else { return false }
    return AXUIElementPerformAction(v as! AXUIElement, kAXPressAction as CFString) == .success
  }

  private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value as? String
  }

  private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value as? Bool
  }
}
