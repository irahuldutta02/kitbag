import AppKit
import KitbagCore
import SwiftUI

/// What the New Entry / Edit Entry window is editing.
@MainActor
final class EntryForm: ObservableObject {
  let model: AuthenticatorModel
  private let original: AuthEntry?
  let editing: Bool

  @Published var title = ""
  @Published var secret = ""
  @Published var issuer = ""
  @Published var digits = 6
  @Published var period = 30
  @Published var algorithm = OTPAlgorithm.sha1
  @Published var kind = OTPKind.totp {
    didSet {
      guard kind != oldValue, kind == .steam else { return }
      digits = 5  // Steam Guard codes are always five characters, from a 30-second SHA-1 code
      period = 30
      algorithm = .sha1
    }
  }
  @Published var showSecret = false
  @Published var message: String?

  init(model: AuthenticatorModel, editing: AuthEntry?, draft: AuthEntry?) {
    self.model = model
    original = editing
    self.editing = editing != nil
    if let e = editing ?? draft { apply(e) }
  }

  func apply(_ e: AuthEntry) {
    title = e.title
    issuer = e.issuer
    secret = e.secret
    digits = e.digits
    period = e.period
    algorithm = e.algorithm
    kind = e.kind
    if e.kind == .steam { digits = 5; period = 30; algorithm = .sha1 }
  }

  var secretIsValid: Bool { Base32.decode(secret) != nil }
  var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && secretIsValid }

  /// Shown under the secret field only once there is something to complain about.
  var secretProblem: String? {
    secret.trimmingCharacters(in: .whitespaces).isEmpty || secretIsValid
      ? nil : "That isn't a valid secret. It uses the letters A–Z and the digits 2–7."
  }

  func makeEntry() -> AuthEntry {
    var e = original ?? AuthEntry()
    e.title = title.trimmingCharacters(in: .whitespaces)
    e.issuer = issuer.trimmingCharacters(in: .whitespaces)
    e.secret = Base32.normalize(secret)
    e.digits = digits
    e.period = period
    e.algorithm = algorithm
    e.kind = kind
    return e
  }

  /// Seconds the picker offers, plus whatever an imported account uses.
  var periods: [Int] { Array(Set([15, 30, 45, 60, 90, period])).sorted() }

  func save() {
    guard canSave else { return }
    let e = makeEntry()
    if editing {
      if model.update(e) { EntryEditor.close() } else { message = model.storageError }
      return
    }
    switch model.add(e) {
    case .added: EntryEditor.close()
    case .duplicate:
      message = "You already have this account in Authenticator."
    case .failed: message = model.storageError ?? "Couldn't save."
    }
  }

  // MARK: Filling the form from a QR code

  func scanScreen() {
    guard !model.scanning else { return }
    model.scanning = true
    EntryEditor.hide()  // get the window out of the way of the code
    Task {
      let outcome = await QRScanner.snipScreen()
      model.scanning = false
      EntryEditor.reveal()
      switch outcome {
      case .cancelled: break
      case .found(let m): fill(from: m)
      case .none: model.noCodeFound()
      case .failed(let why): message = why
      }
    }
  }

  func scanImage() {
    let p = NSOpenPanel()
    p.title = "Choose a picture of a QR code"
    p.allowedContentTypes = [.image]
    p.canChooseDirectories = false
    p.followActiveSpace()
    guard p.runModal() == .OK, let url = p.url else { return }
    let found = QRScanner.messages(inFile: url)
    found.isEmpty ? model.noCodeFound(fromScreen: false) : fill(from: found)
  }

  private func fill(from messages: [String]) {
    let found = messages.flatMap(OTPImport.parse)
    if found.count == 1 {
      apply(found[0])
      message = nil
    } else if found.isEmpty {
      message = "That QR code isn't for an authenticator account."
    } else {
      model.handleScanned(messages)  // an export with several accounts: add them all
      EntryEditor.close()
    }
  }
}

/// The window itself. One at a time.
@MainActor
enum EntryEditor {
  private static var window: NSWindow?

  static func show(model: AuthenticatorModel, editing: AuthEntry?, draft: AuthEntry?) {
    let form = EntryForm(model: model, editing: editing, draft: draft)
    let host = NSHostingController(rootView: EntryFormView(form: form))
    let w =
      window
      ?? {
        let w = NSWindow(
          contentRect: NSRect(x: 0, y: 0, width: 460, height: 640), styleMask: [.titled, .closable],
          backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.followActiveSpace()
        w.center()
        window = w
        return w
      }()
    w.title = editing == nil ? String(localized: "New Entry") : String(localized: "Edit Entry")
    w.contentViewController = host
    w.setContentSize(NSSize(width: 460, height: 640))
    NSApp.activate(ignoringOtherApps: true)
    w.makeKeyAndOrderFront(nil)
  }

  static func hide() { window?.orderOut(nil) }
  static func reveal() {
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }

  static func close() {
    window?.orderOut(nil)
    window?.contentViewController = nil
  }
}

struct EntryFormView: View {
  @ObservedObject var form: EntryForm

  var body: some View {
    VStack(spacing: 0) {
      Form {
        if !form.editing {
          Section {
            HStack(spacing: 10) {
              Button { form.scanScreen() } label: {
                Label("Scan QR Code on Screen", systemImage: "viewfinder")
              }
              Button { form.scanImage() } label: { Label("From Image…", systemImage: "photo") }
              Spacer()
            }
            .controlSize(.regular)
          } footer: {
            Text("Drag over a QR code on your screen and the fields below are filled in for you.")
          }
        }
        Section {
          TextField("Title", text: $form.title, prompt: Text("Required"))
          HStack {
            Group {
              if form.showSecret {
                TextField("Secret", text: $form.secret, prompt: Text("Required"))
              } else {
                SecureField("Secret", text: $form.secret, prompt: Text("Required"))
              }
            }
            .autocorrectionDisabled()
            Button { form.showSecret.toggle() } label: {
              Image(systemName: form.showSecret ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless).help(form.showSecret ? "Hide secret" : "Show secret")
          }
          if let problem = form.secretProblem { Text(problem).font(.caption).foregroundStyle(.red) }
          TextField("Issuer", text: $form.issuer, prompt: Text("Optional, e.g. GitHub"))
        }
        Section {
          Picker("Digits", selection: $form.digits) {
            ForEach(form.kind == .steam ? [5] : [6, 7, 8], id: \.self) { Text("\($0)").tag($0) }
          }
          Picker("Time interval", selection: $form.period) {
            ForEach(form.periods, id: \.self) { Text("\($0) seconds").tag($0) }
          }
          Picker("Algorithm", selection: $form.algorithm) {
            ForEach(OTPAlgorithm.allCases) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)
          Picker("Type", selection: $form.kind) {
            ForEach(OTPKind.allCases) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)
        } header: {
          Text("Advanced")
        } footer: {
          if form.kind == .steam { Text("Steam Guard always uses 5-character codes that change every 30 seconds.") }
        }
        if form.secretIsValid {
          Section("Preview") { Preview(entry: form.makeEntry()) }
        }
      }
      .formStyle(.grouped)
      Divider()
      HStack {
        if let m = form.message { Text(m).font(.caption).foregroundStyle(.red).lineLimit(2) }
        Spacer()
        Button("Cancel") { EntryEditor.close() }.keyboardShortcut(.cancelAction)
        Button(form.editing ? "Save" : "Add") { form.save() }
          .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!form.canSave)
      }
      .padding(14)
    }
    .frame(width: 460, height: 640)
  }
}

/// The code this account would show right now, so a wrong secret or setting is noticed before saving.
private struct Preview: View {
  let entry: AuthEntry
  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { ctx in
      HStack {
        Text(OTP.grouped(entry.code(at: ctx.date), kind: entry.kind))
          .font(.system(size: 24, weight: .semibold, design: .monospaced))
        Spacer()
        CountdownRing(remaining: entry.remaining(at: ctx.date), period: entry.period)
      }
    }
  }
}
