import AppKit

/// Makes ⌘/⌃ + C, X, V, A, Z (and ⇧ for redo) work in every text field of Kitbag.
/// Kitbag is a menu-bar app without an Edit menu, so these would otherwise do nothing.
@MainActor
public enum EditShortcuts {
  private static var monitor: Any?

  public static func install() {
    guard monitor == nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      handle(event) ? nil : event
    }
  }

  private static func handle(_ event: NSEvent) -> Bool {
    guard NSApp.keyWindow?.firstResponder is NSText else { return false }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function])
    let ctrl = flags.contains(.control), cmd = flags.contains(.command)
    guard ctrl != cmd, !flags.contains(.option) else { return false }
    let shift = flags.contains(.shift)
    guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
    let action: Selector
    switch (key, shift) {
    case ("c", false): action = #selector(NSText.copy(_:))
    case ("x", false): action = #selector(NSText.cut(_:))
    case ("v", false): action = #selector(NSText.paste(_:))
    case ("a", false): action = #selector(NSText.selectAll(_:))
    case ("z", false): action = Selector(("undo:"))
    case ("z", true), ("y", false): action = Selector(("redo:"))
    default: return false
    }
    return NSApp.sendAction(action, to: nil, from: nil)
  }
}
