import Carbon.HIToolbox
import KitbagCore
import XCTest

@testable import Dictation

final class DictationTests: XCTestCase {
  func testShortcutDisplay() {
    XCTAssertEqual(Shortcut.default.display, "⌃⌥Space")
    XCTAssertEqual(Shortcut.fn.display, "🌐 fn")
    let s = Shortcut(keyCode: 2, modifiers: UInt32(cmdKey | shiftKey), label: "D")
    XCTAssertEqual(s.display, "⇧⌘D")
  }

  func testCleanStripsQuotesAndWhitespace() {
    XCTAssertEqual(ClaudeCLI.clean("  \"Hello there.\"\n"), "Hello there.")
    XCTAssertEqual(ClaudeCLI.clean("It's fine."), "It's fine.")
    XCTAssertEqual(ClaudeCLI.clean("\n"), "")
  }

  func testWhisperLanguageDetectionHelpers() {
    XCTAssertEqual(WhisperCapture.parseDetected("x\nwhisper_full_with_state: auto-detected language: xx (p = 0.93)\n"), "xx")
    XCTAssertNil(WhisperCapture.parseDetected("nothing here"))
    XCTAssertEqual(WhisperCapture.resolve("xx", allowed: ["aa"]), "aa")
    XCTAssertEqual(WhisperCapture.resolve("bb", allowed: ["aa", "bb"]), "bb")
    XCTAssertEqual(WhisperCapture.resolve("cc", allowed: ["aa", "bb"]), "cc")
    XCTAssertEqual(WhisperCapture.resolve("cc", allowed: []), "cc")
  }

  func testWhisperTidyDropsMarkers() {
    XCTAssertEqual(WhisperCapture.tidy(" [BLANK_AUDIO]\n"), "")
    XCTAssertEqual(WhisperCapture.tidy("Hello there.\n [MUSIC] How are you?"), "Hello there. How are you?")
  }

  @MainActor func testDefaultsAndModelChoices() {
    let d = UserDefaults(suiteName: "kitbag.dictation.test")!
    d.removePersistentDomain(forName: "kitbag.dictation.test")
    let s = DictationSettings(defaults: d)
    XCTAssertEqual(s.model, "claude-haiku-5-5")
    XCTAssertEqual(s.provider, "claude")
    XCTAssertEqual(s.engine, "apple")
    s.shortcut = Shortcut(keyCode: 2, modifiers: UInt32(cmdKey), label: "D")
    XCTAssertEqual(DictationSettings(defaults: d).shortcut.label, "D")
  }

  // MARK: Editable prompt and new providers

  @MainActor private func freshSettings(_ name: String) -> (DictationSettings, UserDefaults) {
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return (DictationSettings(defaults: d), d)
  }

  @MainActor func testCleanupPromptPersistsFallsBackAndResets() {
    let (s, d) = freshSettings("kitbag.dictation.prompt.test")
    XCTAssertFalse(s.isCustomPrompt)
    XCTAssertEqual(s.effectivePrompt, ClaudeCLI.instructions.trimmingCharacters(in: .whitespacesAndNewlines))
    s.cleanupPrompt = "  Fix typos only.  "
    XCTAssertTrue(s.isCustomPrompt)
    XCTAssertEqual(s.effectivePrompt, "Fix typos only.")
    XCTAssertEqual(DictationSettings(defaults: d).cleanupPrompt, "  Fix typos only.  ")
    s.cleanupPrompt = "   \n "
    XCTAssertEqual(s.effectivePrompt, ClaudeCLI.instructions)
    s.cleanupPrompt = "custom"
    s.resetPrompt()
    XCTAssertFalse(s.isCustomPrompt)
  }

  @MainActor func testAntigravityAndCodexSettings() {
    let (s, d) = freshSettings("kitbag.dictation.providers.test")
    XCTAssertEqual(s.agyModel, "gemini-3.8-flash-low")
    XCTAssertEqual(s.agyEffort, "low")
    XCTAssertEqual(s.codexModel, "")
    XCTAssertEqual(s.codexEffort, "low")
    XCTAssertEqual(DictationSettings.agyModels.count, 9)
    XCTAssertEqual(DictationSettings.codexModels.first?.id, "")
    s.agyModel = "gemini-4-neon-high"
    s.codexModel = "gpt-5.4"
    s.provider = "codex"
    let again = DictationSettings(defaults: d)
    XCTAssertEqual(again.agyModel, "gemini-4-neon-high")
    XCTAssertEqual(again.codexModel, "gpt-5.4")
    XCTAssertEqual(again.provider, "codex")
  }

  func testAntigravityParse() {
    let ok = Data(
      #"{"conversation_id":"c","status":"SUCCESS","response":"\"Hello there.\"\n","usage":{"input_tokens":12,"output_tokens":3,"total_tokens":15}}"#.utf8)
    let r = AntigravityCLI.parse(ok)
    XCTAssertEqual(r?.text, "Hello there.")
    XCTAssertEqual(r?.usage.inputTokens, 12)
    XCTAssertEqual(r?.usage.outputTokens, 3)
    XCTAssertNil(AntigravityCLI.parse(Data(#"{"status":"ERROR","response":"nope"}"#.utf8)))
    XCTAssertNil(AntigravityCLI.parse(Data("not json".utf8)))
  }

  func testCodexParse() {
    let stream = #"""
      {"type":"thread.started","thread_id":"t"}
      {"type":"turn.started"}
      {"type":"item.completed","item":{"id":"1","type":"reasoning","text":"thinking"}}
      {"type":"item.completed","item":{"id":"2","type":"agent_message","text":"\"Ship it on Monday.\""}}
      {"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":7}}
      """#
    let r = CodexCLI.parse(Data(stream.utf8))
    XCTAssertEqual(r?.text, "Ship it on Monday.")
    XCTAssertEqual(r?.usage.inputTokens, 100)
    XCTAssertEqual(r?.usage.outputTokens, 7)
    XCTAssertNil(CodexCLI.parse(Data()))
    XCTAssertNil(CodexCLI.parse(Data("{\"type\":\"error\",\"message\":\"x\"}\n".utf8)))
  }

  func testProviderParsers() {
    XCTAssertEqual(ProviderManager.parseVersion("2.1.330 (Claude Code)", for: .claude), "v2.1.330")
    XCTAssertEqual(ProviderManager.parseVersion("codex-cli 0.171.0\n", for: .codex), "v0.171.0")
    XCTAssertEqual(ProviderManager.parseVersion("1.5.14", for: .antigravity), "v1.5.14")
    XCTAssertNil(ProviderManager.parseVersion("no digits", for: .codex))

    let claude = ProviderManager.parseClaudeAuthStatus(
      #"{"loggedIn":true,"authMethod":"claude.ai","email":"a@b.co","subscriptionType":"pro","planTier":"pro"}"#)
    XCTAssertTrue(claude.authenticated)
    XCTAssertEqual(claude.summary, "Authenticated · Claude Pro Subscription")
    XCTAssertEqual(claude.detail, "a@b.co")
    XCTAssertFalse(ProviderManager.parseClaudeAuthStatus(#"{"loggedIn":false}"#).authenticated)
    XCTAssertEqual(ProviderManager.parseClaudeAuthStatus("garbage").summary, "Not signed in")

    XCTAssertEqual(
      ProviderManager.parseCodexLoginStatus("Logged in using ChatGPT", exitCode: 0).summary,
      "Authenticated · ChatGPT")
    XCTAssertEqual(
      ProviderManager.parseCodexLoginStatus("Logged in using API key", exitCode: 0).summary,
      "Authenticated · API key")
    XCTAssertFalse(ProviderManager.parseCodexLoginStatus("Not logged in", exitCode: 1).authenticated)
  }
}
