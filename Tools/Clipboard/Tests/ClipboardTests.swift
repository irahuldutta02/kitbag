import AppKit
import Foundation
import Testing

@testable import Clipboard

@MainActor @Suite struct ClipboardTests {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kitbag-clip-\(UUID().uuidString)")
  let suite = "kitbag.clip.tests.\(UUID().uuidString)"
  let pb = NSPasteboard(name: .init("kitbag.clip.tests.\(UUID().uuidString)"))

  private func makeModel() -> ClipboardModel {
    let m = ClipboardModel(dir: dir, defaults: UserDefaults(suiteName: suite)!, pasteboard: pb)
    m.start(shortcut: false)
    return m
  }

  private func text(_ s: String) -> ClipCapture { ClipCapture(kind: .text, text: s, payload: [:], detail: nil) }

  private func copyText(_ s: String) {
    pb.clearContents()
    pb.setString(s, forType: .string)
  }

  @Test func newestFirst() {
    let m = makeModel()
    m.add(text("one"), date: Date(timeIntervalSince1970: 1))
    m.add(text("two"), date: Date(timeIntervalSince1970: 2))
    #expect(m.items.map(\.text) == ["two", "one"])
  }

  @Test func copyingTheSameThingAgainMovesItToTheTop() {
    let m = makeModel()
    m.add(text("one"), date: Date(timeIntervalSince1970: 1))
    m.add(text("two"), date: Date(timeIntervalSince1970: 2))
    m.add(text("one"), date: Date(timeIntervalSince1970: 3))
    #expect(m.items.map(\.text) == ["one", "two"])
  }

  @Test func pinnedStayOnTopAndSurviveTrimmingAndClear() {
    let m = makeModel()
    m.limit = 50
    m.add(text("keep"), date: Date(timeIntervalSince1970: 0))
    m.togglePin(m.items[0].id)
    for i in 1...60 { m.add(text("n\(i)"), date: Date(timeIntervalSince1970: Double(i))) }
    #expect(m.items.count == 51)
    #expect(m.items.first?.text == "keep" && m.items.last?.text == "n11")
    m.clear(keepPinned: true)
    #expect(m.items.map(\.text) == ["keep"])
    m.clear(keepPinned: false)
    #expect(m.items.isEmpty)
  }

  @Test func watchesThePasteboardAndPauses() {
    let m = makeModel()
    copyText("hello")
    m.poll()
    #expect(m.items.map(\.text) == ["hello"])
    m.paused = true
    copyText("secret while paused")
    m.poll()
    m.paused = false
    m.poll()  // resuming must not pick up what was copied while paused
    #expect(m.items.map(\.text) == ["hello"])
  }

  @Test func passwordManagerCopiesAreSkipped() {
    let m = makeModel()
    pb.clearContents()
    pb.setString("hunter2", forType: .string)
    pb.setString("", forType: .init("org.nspasteboard.ConcealedType"))
    m.poll()
    #expect(m.items.isEmpty)
  }

  @Test func ownCopyIsNotRecordedTwiceAndRichTextRoundTrips() throws {
    let m = makeModel()
    pb.clearContents()
    let entry = NSPasteboardItem()
    entry.setString("bold", forType: .string)
    entry.setData(Data("{\\rtf1 bold}".utf8), forType: .rtf)
    pb.writeObjects([entry])
    m.poll()
    let item = try #require(m.items.first)
    #expect(item.hasPayload)
    copyText("other")
    m.poll()
    m.copy(item)
    m.poll()
    #expect(m.items.map(\.text) == ["bold", "other"])
    #expect(pb.data(forType: .rtf) == Data("{\\rtf1 bold}".utf8) && pb.string(forType: .string) == "bold")
    m.copy(item, plainText: true)
    #expect(pb.data(forType: .rtf) == nil && pb.string(forType: .string) == "bold")
    m.delete(item.id)
    #expect(m.payload(item) == nil)
  }

  @Test func filesAreKeptAsFiles() throws {
    let m = makeModel()
    pb.clearContents()
    pb.writeObjects([URL(fileURLWithPath: "/tmp/a.txt") as NSURL])
    m.poll()
    let item = try #require(m.items.first)
    #expect(item.kind == .files && item.title == "a.txt")
  }

  @Test func shortcutIsCustomizableAndRemembered() {
    let m = makeModel()
    #expect(m.shortcut == .default && m.shortcut.display == "⌥⌘V")
    m.setShortcut(ClipShortcut(keyCode: 8, modifiers: 256 | 4096, label: "C"))
    #expect(m.shortcut.display == "⌃⌘C")
    let again = ClipboardModel(dir: dir, defaults: UserDefaults(suiteName: suite)!, pasteboard: pb)
    #expect(again.shortcut.display == "⌃⌘C")
  }

  @Test func historyIsSavedAndSearchable() {
    let m = makeModel()
    m.add(text("Hello World"))
    m.add(text("other"))
    #expect(m.filtered("hello").map(\.text) == ["Hello World"])
    m.stop()
    let again = makeModel()
    #expect(again.items.count == 2)
  }

  @Test func popupOpensUnderTheCursorAndStaysOnScreen() {
    let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let size = NSSize(width: ClipboardPopup.width, height: 300)
    let caret = NSRect(x: 500, y: 600, width: 0, height: 18)
    #expect(ClipboardPopup.frame(anchor: caret, size: size, screens: [screen]).origin == NSPoint(x: 500, y: 294))
    // No room below: it opens above the cursor instead of covering it.
    let low = NSRect(x: 500, y: 100, width: 0, height: 18)
    #expect(ClipboardPopup.frame(anchor: low, size: size, screens: [screen]).minY == 124)
    let corner = ClipboardPopup.frame(anchor: NSRect(x: 1439, y: 1, width: 0, height: 0), size: size, screens: [screen])
    #expect(screen.contains(corner))
  }

  @Test func popupIsOnlyAsTallAsItsRows() {
    let few = (1...3).map { ClipItem(id: UUID(), kind: .text, text: "\($0)", hash: "\($0)", date: Date()) }
    let many = (1...40).map { ClipItem(id: UUID(), kind: .text, text: "\($0)", hash: "\($0)", date: Date()) }
    #expect(ClipboardPopup.height(for: few) == 70 + 12 + 3 * 29)
    #expect(ClipboardPopup.height(for: many) == ClipboardPopup.maxHeight)
    #expect(CaretLocator.flip(CGRect(x: 10, y: 100, width: 0, height: 20), primaryHeight: 900) == NSRect(x: 10, y: 780, width: 0, height: 20))
  }
}
