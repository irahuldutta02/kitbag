import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut: a key plus Carbon modifier flags.
struct ClipShortcut: Equatable {
  var keyCode: UInt32
  var modifiers: UInt32
  var label: String

  static let `default` = ClipShortcut(
    keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey), label: "V")

  var display: String {
    var s = ""
    if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
    if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
    if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
    if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
    return s + label
  }

  static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    var m: UInt32 = 0
    if flags.contains(.control) { m |= UInt32(controlKey) }
    if flags.contains(.option) { m |= UInt32(optionKey) }
    if flags.contains(.shift) { m |= UInt32(shiftKey) }
    if flags.contains(.command) { m |= UInt32(cmdKey) }
    return m
  }

  /// A readable name for the key of a key-down event.
  static func label(for event: NSEvent) -> String {
    let named: [Int: String] = [
      kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete",
      kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
      kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
      kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
    if let n = named[Int(event.keyCode)] { return n }
    return (event.charactersIgnoringModifiers ?? "?").uppercased()
  }

  // MARK: Saved choice

  private static let codeKey = "kitbag.clipboard.key"
  private static let modsKey = "kitbag.clipboard.mods"
  private static let labelKey = "kitbag.clipboard.label"

  static func load(_ d: UserDefaults) -> ClipShortcut {
    guard let code = d.object(forKey: codeKey) as? Int, let mods = d.object(forKey: modsKey) as? Int,
      let label = d.string(forKey: labelKey)
    else { return .default }
    return ClipShortcut(keyCode: UInt32(code), modifiers: UInt32(mods), label: label)
  }

  func save(_ d: UserDefaults) {
    d.set(Int(keyCode), forKey: Self.codeKey)
    d.set(Int(modifiers), forKey: Self.modsKey)
    d.set(label, forKey: Self.labelKey)
  }
}
