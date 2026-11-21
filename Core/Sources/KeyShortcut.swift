import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A customizable global keyboard shortcut (virtual key code + Carbon modifier flags).
public struct KeyShortcut: Equatable, Sendable {
  public var keyCode: UInt32
  public var modifiers: UInt32
  public var label: String

  public init(keyCode: UInt32, modifiers: UInt32, label: String) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.label = label
  }

  public var display: String {
    var s = ""
    if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
    if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
    if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
    if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
    return s + label
  }

  public static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    var m: UInt32 = 0
    if flags.contains(.control) { m |= UInt32(controlKey) }
    if flags.contains(.option) { m |= UInt32(optionKey) }
    if flags.contains(.shift) { m |= UInt32(shiftKey) }
    if flags.contains(.command) { m |= UInt32(cmdKey) }
    return m
  }

  /// A readable name for the key of a key-down event.
  public static func label(for event: NSEvent) -> String {
    let named: [Int: String] = [
      kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete",
      kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
      kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
      kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
    if let n = named[Int(event.keyCode)] { return n }
    return (event.charactersIgnoringModifiers ?? "?").uppercased()
  }

  // MARK: Persistence

  /// Loads a saved shortcut, returning `nil` if the user explicitly cleared it, or `fallback` if never set.
  public static func load(from d: UserDefaults, prefix: String, default fallback: KeyShortcut?)
    -> KeyShortcut?
  {
    if d.bool(forKey: "\(prefix).disabled") { return nil }
    guard let code = d.object(forKey: "\(prefix).key") as? Int,
      let mods = d.object(forKey: "\(prefix).mods") as? Int,
      let label = d.string(forKey: "\(prefix).label")
    else { return fallback }
    return KeyShortcut(keyCode: UInt32(code), modifiers: UInt32(mods), label: label)
  }

  public static func save(_ shortcut: KeyShortcut?, to d: UserDefaults, prefix: String) {
    if let s = shortcut {
      d.set(false, forKey: "\(prefix).disabled")
      d.set(Int(s.keyCode), forKey: "\(prefix).key")
      d.set(Int(s.modifiers), forKey: "\(prefix).mods")
      d.set(s.label, forKey: "\(prefix).label")
    } else {
      d.set(true, forKey: "\(prefix).disabled")
      d.removeObject(forKey: "\(prefix).key")
      d.removeObject(forKey: "\(prefix).mods")
      d.removeObject(forKey: "\(prefix).label")
    }
  }
}

@MainActor private final class RecorderBox: ObservableObject {
  @Published var recording = false
  @Published var errorMessage: String?
  var monitor: Any?
}

/// Reusable Settings row for recording, resetting, or clearing a global keyboard shortcut.
public struct ShortcutRecorderRow: View {
  let title: LocalizedStringKey
  let current: KeyShortcut?
  let defaultShortcut: KeyShortcut
  let onPause: (Bool) -> Void
  let onSet: (KeyShortcut?) -> Bool

  @StateObject private var box = RecorderBox()

  public init(
    _ title: LocalizedStringKey,
    current: KeyShortcut?,
    defaultShortcut: KeyShortcut,
    onPause: @escaping (Bool) -> Void,
    onSet: @escaping (KeyShortcut?) -> Bool
  ) {
    self.title = title
    self.current = current
    self.defaultShortcut = defaultShortcut
    self.onPause = onPause
    self.onSet = onSet
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      LabeledContent(title) {
        HStack(spacing: 8) {
          Text(
            box.recording
              ? "Press new keys…"
              : (current?.display ?? "Off")
          )
          .font(.system(.body, design: .rounded).weight(.medium))
          .foregroundStyle(
            box.recording ? Color.accentColor : (current == nil ? .secondary : .primary)
          )
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(
            .quaternary.opacity(0.6),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
          )
          if current != defaultShortcut && !box.recording {
            Button("Reset") {
              box.errorMessage = nil
              if !onSet(defaultShortcut) {
                box.errorMessage = "\(defaultShortcut.display) is taken by another app."
              }
            }
            .controlSize(.small)
          }
          if current != nil && !box.recording {
            Button("Clear") {
              box.errorMessage = nil
              _ = onSet(nil)
            }
            .controlSize(.small)
          }
          Button(box.recording ? "Cancel" : "Change") {
            box.recording ? stopRecording() : startRecording()
          }
          .controlSize(.small)
        }
      }
      if let err = box.errorMessage {
        Text(err).font(.caption).foregroundStyle(KitbagUI.danger)
      }
    }
    .onDisappear { if box.recording { stopRecording() } }
  }

  private func startRecording() {
    box.errorMessage = nil
    box.recording = true
    onPause(true)
    box.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
      if e.keyCode == 53 {  // Esc
        stopRecording()
        return nil
      }
      let mods = KeyShortcut.carbonModifiers(e.modifierFlags)
      guard mods != 0 else {
        NSSound.beep()
        return nil
      }
      let next = KeyShortcut(
        keyCode: UInt32(e.keyCode), modifiers: mods, label: KeyShortcut.label(for: e))
      stopRecording()
      if !onSet(next) {
        box.errorMessage = "\(next.display) is taken by another app. Try a different one."
      }
      return nil
    }
  }

  private func stopRecording() {
    if let m = box.monitor { NSEvent.removeMonitor(m) }
    box.monitor = nil
    box.recording = false
    onPause(false)
  }
}
