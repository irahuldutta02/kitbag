import AppKit
import ApplicationServices

/// Types the text into whatever app is in front by pasting it, then puts the old clipboard back.
@MainActor
enum Paster {
  /// Returns true if it was pasted. Without Accessibility access the text stays on the clipboard instead.
  static func paste(_ text: String) -> Bool {
    let pb = NSPasteboard.general
    let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pb.pasteboardItems ?? []).map { item in
      item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
    }
    pb.clearContents()
    pb.setString(text, forType: .string)
    // Marks this as a passing copy, so clipboard histories (Kitbag's own included) don't keep it.
    pb.setString("", forType: .init("org.nspasteboard.TransientType"))
    let ours = pb.changeCount
    guard AXIsProcessTrusted() else { return false }

    let src = CGEventSource(stateID: .combinedSessionState)
    for down in [true, false] {
      let e = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: down)  // V
      e?.flags = .maskCommand
      e?.post(tap: .cghidEventTap)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
      guard pb.changeCount == ours, !saved.isEmpty else { return }
      pb.clearContents()
      for types in saved {
        let item = NSPasteboardItem()
        for (t, d) in types { item.setData(d, forType: t) }
        pb.writeObjects([item])
      }
    }
    return true
  }
}
