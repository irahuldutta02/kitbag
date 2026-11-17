import AppKit
import UniformTypeIdentifiers

/// Importing from other authenticator apps (started from the Authenticator page in Settings).
extension AuthenticatorModel {
  func showQRCode(_ e: AuthEntry) { QRCodeWindow.show(e) }

  /// Proton Authenticator and 2FAS: pick the exported file, ask for its password if it has one.
  func importFrom(_ source: ImportSource) {
    let p = NSOpenPanel()
    p.title = "Choose your \(source.name) export"
    p.message = source.howTo
    p.allowedContentTypes = [.json, .plainText, .data]
    p.canChooseDirectories = false
    p.followActiveSpace()
    NSApp.activate(ignoringOtherApps: true)
    guard p.runModal() == .OK, let url = p.url else { return }
    guard let data = try? Data(contentsOf: url) else {
      Dialogs.show("Couldn't read the file", "Check that you can open it, then try again.")
      return
    }
    Task { await runImport(data, source) }
  }

  private func runImport(_ data: Data, _ source: ImportSource) async {
    var password: String?
    var message = "This export is protected with a password."
    while true {
      let attempt = password
      do {
        let result = try await Task.detached(priority: .userInitiated) {
          try ThirdPartyImport.parse(data, as: source, password: attempt)
        }.value
        finishImport(result, source)
        return
      } catch ThirdPartyImport.Failure.needsPassword {
        guard let typed = Self.askPassword("Enter the export password", message, source: source) else { return }
        password = typed
      } catch ThirdPartyImport.Failure.wrongPassword {
        message = "That password didn't unlock the file. Try again."
        guard let typed = Self.askPassword("Wrong password", message, source: source) else { return }
        password = typed
      } catch ThirdPartyImport.Failure.unsupported(let what) {
        Dialogs.show("Can't read this file", "It uses \(what), which this version doesn't understand.")
        return
      } catch {
        Dialogs.show(
          "That isn't a \(source.name) export",
          "Choose the file you exported from \(source.name). \(source.howTo)")
        return
      }
    }
  }

  private func finishImport(_ r: ThirdPartyImport.Result, _ source: ImportSource) {
    guard !r.entries.isEmpty else {
      Dialogs.show("Nothing to import", r.unusable > 0 ? "None of the \(r.unusable) entries in the file can be used here." : "The file has no accounts.")
      return
    }
    let done = importEntries(r.entries)
    var text = "Imported \(done.added) account\(done.added == 1 ? "" : "s") from \(source.name)."
    if done.skipped > 0 { text += " \(done.skipped) \(done.skipped == 1 ? "was" : "were") already here." }
    if r.unusable > 0 {
      text += " \(r.unusable) couldn't be imported (counter-based codes aren't supported, or the entry was damaged)."
    }
    if let e = storageError, done.added == 0 { text = e }
    Dialogs.show(done.added > 0 ? "Import complete" : "Nothing new to import", text)
  }

  /// A small prompt with a hidden text field. Returns nil if cancelled.
  private static func askPassword(_ title: String, _ text: String, source: ImportSource) -> String? {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = "\(text)\n\n\(source.name)"
    a.addButton(withTitle: "Import")
    a.addButton(withTitle: "Cancel")
    let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
    field.placeholderString = "Password"
    a.accessoryView = field
    a.window.followActiveSpace()
    a.window.initialFirstResponder = field
    NSApp.activate(ignoringOtherApps: true)
    guard a.runModal() == .alertFirstButtonReturn else { return nil }
    return field.stringValue
  }
}
