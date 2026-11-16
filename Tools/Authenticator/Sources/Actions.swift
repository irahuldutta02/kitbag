import AppKit
import KitbagCore
import UniformTypeIdentifiers

extension NSWindow {
  /// Opens on the desktop you are looking at (also over a full-screen app) instead of pulling you
  /// to the desktop the window was last on.
  func followActiveSpace() {
    collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    level = .floating
    hidesOnDeactivate = false
  }
}

/// Plain macOS alerts, brought to the front even though Kitbag has no Dock icon.
@MainActor
enum Dialogs {
  /// Returns true if the second button was pressed.
  @discardableResult
  static func show(_ title: String, _ text: String, second: String? = nil, destructive: Bool = false) -> Bool {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = text
    a.alertStyle = destructive ? .warning : .informational
    a.addButton(withTitle: second == nil ? "OK" : (destructive ? "Cancel" : "OK"))
    if let second {
      a.addButton(withTitle: second)
      if destructive { a.buttons[1].hasDestructiveAction = true }
    }
    a.window.followActiveSpace()
    NSApp.activate(ignoringOtherApps: true)
    return a.runModal() == .alertSecondButtonReturn
  }

  static let screenRecordingPane = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
  static func openScreenRecordingSettings() {
    if let url = URL(string: screenRecordingPane) { NSWorkspace.shared.open(url) }
  }
}

/// Everything you can start from a button or a menu: add, scan, back up, restore.
extension AuthenticatorModel {
  func addManually() {
    NotificationCenter.default.post(name: .kitbagCloseMenu, object: nil)
    EntryEditor.show(model: self, editing: nil, draft: nil)
  }
  func edit(_ e: AuthEntry) { EntryEditor.show(model: self, editing: e, draft: nil) }

  func confirmDelete(_ e: AuthEntry) {
    if Dialogs.show(
      "Remove “\(e.primary)”?",
      "You will no longer see codes for this account here. Make sure you can still sign in to it another way, or that you have a backup, before removing it.",
      second: "Remove", destructive: true)
    { delete(e.id) }
  }

  func confirmRemoveAll() {
    if Dialogs.show(
      "Remove all \(entries.count) accounts?",
      "This can't be undone. Back up first if you may need them again.", second: "Remove All", destructive: true)
    { removeAll() }
  }

  // MARK: Scanning

  /// Snip a QR code from the screen.
  func scanScreen() {
    guard !scanning else { return }
    scanning = true
    NotificationCenter.default.post(name: .kitbagCloseMenu, object: nil)  // keep the pop-up out of the picture
    Task {
      try? await Task.sleep(nanoseconds: 300_000_000)  // let it finish fading out
      let outcome = await QRScanner.snipScreen()
      scanning = false
      switch outcome {
      case .cancelled: break
      case .found(let messages): handleScanned(messages)
      case .none: noCodeFound()
      case .failed(let why): Dialogs.show("Couldn't take the screenshot", why)
      }
    }
  }

  func scanImageFile() {
    let p = NSOpenPanel()
    p.title = "Choose a picture of a QR code"
    p.allowedContentTypes = [.image]
    p.canChooseDirectories = false
    NotificationCenter.default.post(name: .kitbagCloseMenu, object: nil)
    p.followActiveSpace()
    NSApp.activate(ignoringOtherApps: true)
    guard p.runModal() == .OK, let url = p.url else { return }
    let found = QRScanner.messages(inFile: url)
    found.isEmpty ? noCodeFound(fromScreen: false) : handleScanned(found)
  }

  /// A copied `otpauth://` link, or a copied picture of a QR code.
  func pasteFromClipboard() {
    let pb = NSPasteboard.general
    var found = (pb.string(forType: .string).map { [$0] } ?? [])
    if found.flatMap(OTPImport.parse).isEmpty { found = QRScanner.messages(inPasteboard: pb) }
    if found.flatMap(OTPImport.parse).isEmpty {
      Dialogs.show("Nothing to paste", "Copy an otpauth:// link or a picture of a QR code first, then try again.")
    } else {
      handleScanned(found)
    }
  }

  func handleScanned(_ messages: [String]) {
    let found = messages.flatMap(OTPImport.parse)
    switch found.count {
    case 0:
      Dialogs.show(
        "That isn't an authenticator code",
        "The QR code was read, but it isn't a code for an authenticator account (it should start with otpauth://).")
    case 1:
      EntryEditor.show(model: self, editing: nil, draft: found[0])  // let the person check the name first
    default:
      summarize(importEntries(found), what: "from the QR code")
    }
  }

  private func summarize(_ r: (added: Int, skipped: Int), what: String) {
    var text = r.added == 1 ? "Added 1 account \(what)." : "Added \(r.added) accounts \(what)."
    if r.skipped > 0 { text += " \(r.skipped) were already here." }
    Dialogs.show(r.added > 0 ? "Done" : "Nothing new to add", text)
  }

  func noCodeFound(fromScreen: Bool = true) {
    var text = "Make sure the whole QR code is inside the selection and is clearly visible."
    let permission = fromScreen && !CGPreflightScreenCaptureAccess()
    if permission {
      text += "\n\nKitbag may also need permission to capture your screen. Allow it in System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording, then try again."
    }
    if Dialogs.show("No QR code found", text, second: permission ? "Open Settings" : nil) {
      Dialogs.openScreenRecordingSettings()
    }
  }

  // MARK: Backup and restore

  func backUp() {
    guard !entries.isEmpty else {
      Dialogs.show("Nothing to back up", "Add an account first.")
      return
    }
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    let p = NSSavePanel()
    p.title = "Back up your accounts"
    p.message = "The file contains your secrets in plain text. Keep it somewhere private."
    p.nameFieldStringValue = "Kitbag Authenticator Backup \(f.string(from: Date())).json"
    p.allowedContentTypes = [.json]
    p.canCreateDirectories = true
    p.followActiveSpace()
    NSApp.activate(ignoringOtherApps: true)
    guard p.runModal() == .OK, let url = p.url else { return }
    do {
      try exportBackup().write(to: url, options: .atomic)
      try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)  // only you
      markBackedUp()
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } catch {
      Dialogs.show("Couldn't save the backup", error.localizedDescription)
    }
  }

  func restoreBackup() {
    let p = NSOpenPanel()
    p.title = "Restore accounts from a backup"
    p.message = "Accounts you already have are kept as they are; only new ones are added."
    p.allowedContentTypes = [.json, .plainText]
    p.canChooseDirectories = false
    p.followActiveSpace()
    NSApp.activate(ignoringOtherApps: true)
    guard p.runModal() == .OK, let url = p.url else { return }
    guard let data = try? Data(contentsOf: url) else {
      Dialogs.show("Couldn't read the file", "Check that you can open it, then try again.")
      return
    }
    let r = restore(from: data)
    if !r.recognized {
      Dialogs.show("That isn't a backup", "Choose a JSON backup made by Kitbag, or a text file of otpauth:// links.")
      return
    }
    var text = "Restored \(r.added) account\(r.added == 1 ? "" : "s")."
    if r.skipped > 0 { text += " \(r.skipped) were already here." }
    if r.invalid > 0 { text += " \(r.invalid) couldn't be used because their secret was missing or invalid." }
    Dialogs.show(r.added > 0 ? "Backup restored" : "Nothing new to restore", text)
  }
}
