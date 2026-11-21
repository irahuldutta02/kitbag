import AppKit
import Carbon.HIToolbox
import Foundation
import Speech

/// A global keyboard shortcut: a key plus Carbon modifier flags.
struct Shortcut: Equatable {
  var keyCode: UInt32
  var modifiers: UInt32
  var label: String

  static let `default` = Shortcut(
    keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), label: "Space")

  /// The Globe / fn key on its own. It can't be a Carbon hot key, so it is watched separately.
  static let fn = Shortcut(keyCode: UInt32(kVK_Function), modifiers: 0, label: "fn")
  var isFn: Bool { keyCode == UInt32(kVK_Function) && modifiers == 0 }

  var display: String {
    if isFn { return "🌐 fn" }
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
}

/// What the person picked for dictation; saved in UserDefaults.
@MainActor
final class DictationSettings: ObservableObject {
  struct ModelChoice: Identifiable {
    let id: String
    let name: String
  }

  static let models = [
    ModelChoice(id: "claude-haiku-5-5", name: "Haiku 5.5 (fastest)"),
    ModelChoice(id: "claude-haiku-4-5", name: "Haiku 4.5"),
    ModelChoice(id: "claude-sonnet-5-5", name: "Sonnet 5.5"),
    ModelChoice(id: "claude-opus-5-5", name: "Opus 5.5"),
  ]

  /// Effort levels Antigravity and Codex accept; "" leaves the model's own default.
  static let simpleEfforts = [
    ModelChoice(id: "low", name: "Low (fastest)"),
    ModelChoice(id: "medium", name: "Medium"),
    ModelChoice(id: "high", name: "High"),
    ModelChoice(id: "", name: "Model default"),
  ]

  /// Models the Antigravity CLI (`agy models`) offers for clean-up.
  static let agyModels = [
    ModelChoice(id: "gemini-3.8-flash-low", name: "Gemini 3.8 Flash (fastest)"),
    ModelChoice(id: "gemini-3.8-flash-medium", name: "Gemini 3.8 Flash (Medium)"),
    ModelChoice(id: "gemini-4-neon-low", name: "Gemini 4 Neon (Low)"),
    ModelChoice(id: "gemini-4-neon-medium", name: "Gemini 4 Neon (Medium)"),
    ModelChoice(id: "gemini-4-neon-high", name: "Gemini 4 Neon (High)"),
    ModelChoice(id: "gemini-4-argon-low", name: "Gemini 4 Argon (Low)"),
    ModelChoice(id: "gemini-4-argon-medium", name: "Gemini 4 Argon (Medium)"),
    ModelChoice(id: "gemini-4-hydrogen-low", name: "Gemini 4 Hydrogen (Low)"),
    ModelChoice(id: "claude-sonnet-5-5-low", name: "Claude Sonnet 5.5 (Low)"),
  ]

  /// Models the Codex CLI can use; "" leaves Codex's own default (works on every plan).
  static let codexModels = [
    ModelChoice(id: "", name: "Codex default"),
    ModelChoice(id: "gpt-5.6-terra", name: "GPT-5.6 Terra"),
    ModelChoice(id: "gpt-6-luna", name: "GPT-6 Luna"),
    ModelChoice(id: "gpt-5.4-mini", name: "GPT-5.4 Mini"),
    ModelChoice(id: "gpt-5.4", name: "GPT-5.4"),
  ]

  /// Effort levels Claude Code accepts; "" leaves the model's own default.
  static let efforts = [
    ModelChoice(id: "low", name: "Low (fastest)"),
    ModelChoice(id: "medium", name: "Medium"),
    ModelChoice(id: "high", name: "High"),
    ModelChoice(id: "xhigh", name: "Extra high"),
    ModelChoice(id: "max", name: "Max"),
    ModelChoice(id: "", name: "Model default"),
  ]

  /// Languages Apple's speech recognizer can listen for, by name.
  static let languages: [ModelChoice] = {
    let current = Locale.current
    return SFSpeechRecognizer.supportedLocales().map {
      ModelChoice(id: $0.identifier, name: current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier)
    }.sorted { $0.name < $1.name }
  }()

  private let defaults: UserDefaults

  @Published var shortcut: Shortcut { didSet { save() } }
  /// Who cleans the transcript up: "claude", "antigravity", "codex", "gemma" (local, through Ollama) or "off".
  @Published var provider: String { didSet { defaults.set(provider, forKey: "dictation.provider") } }
  /// Who turns speech into text: "apple" (built in) or "whisper" (whisper.cpp on this Mac).
  @Published var engine: String { didSet { defaults.set(engine, forKey: "dictation.engine") } }
  @Published var whisperModel: String { didSet { defaults.set(whisperModel, forKey: "dictation.whisperModel") } }
  @Published var whisperLanguage: String { didSet { defaults.set(whisperLanguage, forKey: "dictation.whisperLanguage") } }
  /// Languages you picked, as Whisper codes joined by commas. Empty means any language.
  @Published var whisperAllowed: String { didSet { defaults.set(whisperAllowed, forKey: "dictation.whisperAllowed") } }
  /// An Ollama model tag, for example "gemma3:4b".
  @Published var gemmaModel: String { didSet { defaults.set(gemmaModel, forKey: "dictation.gemmaModel") } }
  @Published var model: String { didSet { defaults.set(model, forKey: "dictation.model") } }
  /// Language the recognizer listens for (a locale id such as "hi-IN"); "" follows the system language.
  @Published var language: String { didSet { defaults.set(language, forKey: "dictation.language") } }
  @Published var effort: String { didSet { defaults.set(effort, forKey: "dictation.effort") } }
  @Published var agyModel: String { didSet { defaults.set(agyModel, forKey: "dictation.agyModel") } }
  @Published var agyEffort: String { didSet { defaults.set(agyEffort, forKey: "dictation.agyEffort") } }
  @Published var codexModel: String { didSet { defaults.set(codexModel, forKey: "dictation.codexModel") } }
  @Published var codexEffort: String { didSet { defaults.set(codexEffort, forKey: "dictation.codexEffort") } }
  /// The instructions every clean-up provider gets. Empty falls back to the built-in default.
  @Published var cleanupPrompt: String { didSet { defaults.set(cleanupPrompt, forKey: "dictation.cleanupPrompt") } }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let wasOff = defaults.object(forKey: "dictation.refine") as? Bool == false  // older versions
    provider = defaults.string(forKey: "dictation.provider") ?? (wasOff ? "off" : "claude")
    engine = defaults.string(forKey: "dictation.engine") ?? "apple"
    whisperModel = defaults.string(forKey: "dictation.whisperModel") ?? "large-v3-turbo-q5_0"
    whisperLanguage = defaults.string(forKey: "dictation.whisperLanguage") ?? "auto"
    whisperAllowed = defaults.string(forKey: "dictation.whisperAllowed") ?? ""
    gemmaModel = defaults.string(forKey: "dictation.gemmaModel") ?? "gemma3:4b"
    model = defaults.string(forKey: "dictation.model") ?? Self.models[0].id
    effort = defaults.string(forKey: "dictation.effort") ?? "low"
    language = defaults.string(forKey: "dictation.language") ?? ""
    agyModel = defaults.string(forKey: "dictation.agyModel") ?? Self.agyModels[0].id
    agyEffort = defaults.string(forKey: "dictation.agyEffort") ?? "low"
    codexModel = defaults.string(forKey: "dictation.codexModel") ?? ""
    codexEffort = defaults.string(forKey: "dictation.codexEffort") ?? "low"
    cleanupPrompt = defaults.string(forKey: "dictation.cleanupPrompt") ?? ClaudeCLI.instructions
    if let code = defaults.object(forKey: "dictation.key") as? Int,
      let mods = defaults.object(forKey: "dictation.mods") as? Int,
      let label = defaults.string(forKey: "dictation.label")
    {
      shortcut = Shortcut(keyCode: UInt32(code), modifiers: UInt32(mods), label: label)
    } else {
      shortcut = .fn
    }
  }

  /// The prompt to send: what the person wrote, or the default when it is blank.
  var effectivePrompt: String {
    let t = cleanupPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? ClaudeCLI.instructions : t
  }

  var isCustomPrompt: Bool { effectivePrompt != ClaudeCLI.instructions.trimmingCharacters(in: .whitespacesAndNewlines) }

  func resetPrompt() { cleanupPrompt = ClaudeCLI.instructions }

  var allowedLanguages: [String] { whisperAllowed.split(separator: ",").map(String.init) }

  func setAllowed(_ code: String, _ on: Bool) {
    var set = allowedLanguages.filter { $0 != code }
    if on { set.append(code) }
    whisperAllowed = set.joined(separator: ",")
  }

  private func save() {
    defaults.set(Int(shortcut.keyCode), forKey: "dictation.key")
    defaults.set(Int(shortcut.modifiers), forKey: "dictation.mods")
    defaults.set(shortcut.label, forKey: "dictation.label")
  }
}
