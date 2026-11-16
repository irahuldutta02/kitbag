import AppKit
import ApplicationServices

/// Finds where the text cursor is in the app in front, so the pop-up can open right under it.
/// Uses the Accessibility API; apps that don't report it (or no permission) give nil.
@MainActor
enum CaretLocator {
  /// Never wait long for a busy app: the pop-up must open at once.
  private static let timeout: Float = 0.15
  private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

  private static var asked: Set<pid_t> = []

  /// The text cursor (or, failing that, the small text field being typed in) in AppKit screen coordinates.
  static func caretRect() -> NSRect? {
    guard AXIsProcessTrusted() else { return nil }
    let found = locate()
    // Chromium and Electron apps keep their text hidden from Accessibility until asked. Ask once,
    // so the cursor can be found the next time the pop-up opens in that app.
    if found == nil, let app = NSWorkspace.shared.frontmostApplication, asked.insert(app.processIdentifier).inserted {
      let appElement = AXUIElementCreateApplication(app.processIdentifier)
      AXUIElementSetMessagingTimeout(appElement, timeout)
      AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }
    return found
  }

  private static func locate() -> NSRect? {
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, timeout)
    var focused = element(system, kAXFocusedUIElementAttribute)
    if focused == nil, let app = NSWorkspace.shared.frontmostApplication {
      let appElement = AXUIElementCreateApplication(app.processIdentifier)
      AXUIElementSetMessagingTimeout(appElement, timeout)
      focused = element(appElement, kAXFocusedUIElementAttribute)
    }
    guard let focused else { return nil }
    AXUIElementSetMessagingTimeout(focused, timeout)
    guard let rect = caret(in: focused) ?? fieldFrame(of: focused), let primary = NSScreen.screens.first else {
      return nil
    }
    let flipped = flip(rect, primaryHeight: primary.frame.height)
    // Some apps answer with nonsense; only trust a spot that is really on a screen.
    let probe = NSPoint(x: flipped.minX, y: flipped.midY)
    return NSScreen.screens.contains { $0.frame.insetBy(dx: -1, dy: -1).contains(probe) } ? flipped : nil
  }

  /// Accessibility measures from the top-left of the main screen; AppKit from its bottom-left.
  static func flip(_ r: CGRect, primaryHeight: CGFloat) -> NSRect {
    NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
  }

  private static func caret(in el: AXUIElement) -> CGRect? {
    guard let rangeValue = value(el, kAXSelectedTextRangeAttribute) else { return nil }
    var range = CFRange()
    guard AXValueGetValue(rangeValue, .cfRange, &range) else { return nil }
    if let r = bounds(el, range), r.height > 1 { return r }
    // Some apps can't measure an empty range: measure the character before the cursor instead.
    guard range.location > 0, let r = bounds(el, CFRange(location: range.location - 1, length: 1)), r.height > 1
    else { return nil }
    return CGRect(x: r.maxX, y: r.minY, width: 0, height: r.height)
  }

  private static func bounds(_ el: AXUIElement, _ range: CFRange) -> CGRect? {
    var range = range
    guard let param = AXValueCreate(.cfRange, &range) else { return nil }
    var out: CFTypeRef?
    guard
      AXUIElementCopyParameterizedAttributeValue(
        el, kAXBoundsForRangeParameterizedAttribute as CFString, param, &out) == .success,
      let out, CFGetTypeID(out) == AXValueGetTypeID()
    else { return nil }
    var rect = CGRect.zero
    guard AXValueGetValue(out as! AXValue, .cgRect, &rect), rect != .zero else { return nil }
    return rect
  }

  /// A one-line text field is small enough to open under; a whole editor is not.
  private static func fieldFrame(of el: AXUIElement) -> CGRect? {
    var roleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
    guard let role = roleRef as? String, textRoles.contains(role),
      let p = value(el, kAXPositionAttribute), let s = value(el, kAXSizeAttribute)
    else { return nil }
    var origin = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(p, .cgPoint, &origin), AXValueGetValue(s, .cgSize, &size),
      size.height > 1, size.height <= 80
    else { return nil }
    return CGRect(origin: origin, size: size)
  }

  private static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
    var out: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &out) == .success, let out,
      CFGetTypeID(out) == AXUIElementGetTypeID()
    else { return nil }
    return (out as! AXUIElement)
  }

  private static func value(_ el: AXUIElement, _ name: String) -> AXValue? {
    var out: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &out) == .success, let out,
      CFGetTypeID(out) == AXValueGetTypeID()
    else { return nil }
    return (out as! AXValue)
  }
}
