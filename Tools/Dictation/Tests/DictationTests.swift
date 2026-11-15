import Carbon.HIToolbox
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
}
