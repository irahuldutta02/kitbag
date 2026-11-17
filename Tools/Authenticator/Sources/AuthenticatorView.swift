import KitbagCore
import SwiftUI

/// The "about to change" red. An explicit color: the system red loses its color inside the glass card.
private enum Warning {
  static let color = Color(red: 0.95, green: 0.27, blue: 0.23)
  static let success = Color(red: 0.18, green: 0.70, blue: 0.36)
}

@MainActor private final class TabState: ObservableObject {
  @Published var query = ""
  /// The "add an account" choices are showing.
  @Published var adding = false
  /// The account whose options (copy, pin, edit, remove) are open.
  @Published var expanded: UUID?
  @Published var hovered: UUID?
}

/// The tab in the menu pop-up: search, the codes, and each account's options.
///
/// Choices are plain inline buttons rather than pop-up menus: a menu opening inside a menu-bar
/// pop-up can take focus away and close it before the choice is made.
struct AuthenticatorView: View {
  @ObservedObject var model: AuthenticatorModel
  @StateObject private var ui = TabState()

  var body: some View {
    let list = model.filtered(ui.query)
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        HStack(spacing: 6) {
          Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
          TextField("Search", text: $ui.query).textFieldStyle(.plain)
          if !ui.query.isEmpty {
            Button { ui.query = "" } label: { Image(systemName: "xmark.circle.fill") }
              .buttonStyle(.plain).foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 8).frame(height: 28)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        Button {
          withAnimation(.easeInOut(duration: 0.15)) { ui.adding.toggle() }
        } label: {
          Image(systemName: ui.adding ? "xmark.circle.fill" : "plus.circle.fill")
            .font(.system(size: 24)).foregroundStyle(ui.adding ? Color.secondary : Color.accentColor)
            .frame(width: 30, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help(ui.adding ? "Close" : "Add an account")
        .accessibilityLabel(ui.adding ? "Close" : "Add an account")
      }
      if ui.adding { AddChoices(model: model, done: { ui.adding = false }) }
      if let err = model.storageError {
        Label(err, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Warning.color)
      }
      if model.entries.isEmpty {
        if !ui.adding { EmptyState(model: model) }
      } else if list.isEmpty {
        Text("No matches").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 18)
      } else {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
          ScrollView {
            LazyVStack(spacing: 6) {
              ForEach(list) { entry in
                EntryRow(
                  model: model, entry: entry, date: ctx.date, open: ui.expanded == entry.id,
                  hovered: ui.hovered == entry.id,
                  hover: { ui.hovered = $0 ? entry.id : (ui.hovered == entry.id ? nil : ui.hovered) },
                  toggle: { withAnimation(.easeInOut(duration: 0.15)) { ui.expanded = ui.expanded == entry.id ? nil : entry.id } },
                  close: { withAnimation(.easeInOut(duration: 0.15)) { ui.expanded = nil } })
              }
            }
          }
          .frame(height: min(CGFloat(list.count) * 106 + (ui.expanded == nil ? 0 : 74), 350))
        }
      }
      if !model.entries.isEmpty {
        HStack {
          Text(model.entries.count == 1 ? "1 account" : "\(model.entries.count) accounts")
          Spacer()
          Text("Click a card to copy its code")
        }
        .font(.caption).foregroundStyle(.secondary)
      }
    }
    .card()
  }
}

/// Every way of adding an account, as ordinary buttons.
private struct AddChoices: View {
  let model: AuthenticatorModel
  let done: () -> Void

  var body: some View {
    VStack(spacing: 2) {
      choice("Scan QR Code on Screen", "viewfinder", "Drag over a code on your screen") { model.scanScreen() }
      choice("Scan QR Code with Camera", "camera", "Hold a code up to your Mac's camera") { model.scanCamera() }
      choice("Scan QR Code from Image…", "photo", nil) { model.scanImageFile() }
      choice("Paste Link or QR from Clipboard", "doc.on.clipboard", nil) { model.pasteFromClipboard() }
      choice("Enter Manually…", "keyboard", nil) { model.addManually() }
    }
    .padding(4)
    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private func choice(_ title: LocalizedStringKey, _ symbol: String, _ hint: LocalizedStringKey?, _ action: @escaping () -> Void) -> some View {
    Button {
      done()
      action()
    } label: {
      HStack(spacing: 10) {
        Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 22)
        VStack(alignment: .leading, spacing: 0) {
          Text(title).font(.callout)
          if let hint { Text(hint).font(.caption2).foregroundStyle(.secondary) }
        }
        Spacer()
      }
      .padding(.horizontal, 8).padding(.vertical, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(PressableStyle())
  }
}

private struct EmptyState: View {
  let model: AuthenticatorModel
  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "lock.shield").font(.system(size: 30)).foregroundStyle(.tertiary)
      Text("No accounts yet").font(.headline)
      Text("Scan the QR code a website shows when you set up two-factor sign-in, or enter the secret by hand.")
        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
      HStack {
        Button { model.scanScreen() } label: { Label("Scan QR Code", systemImage: "viewfinder") }
          .buttonStyle(.borderedProminent)
        Button("Enter Manually") { model.addManually() }
      }
      .controlSize(.small)
    }
    .frame(maxWidth: .infinity).padding(.vertical, 14)
  }
}

/// One account: the name, the current code in full, the next code smaller beneath it, a countdown
/// and a ⋯ button that opens its options.
private struct EntryRow: View {
  let model: AuthenticatorModel
  let entry: AuthEntry
  let date: Date
  let open: Bool
  let hovered: Bool
  let hover: (Bool) -> Void
  let toggle: () -> Void
  let close: () -> Void

  var body: some View {
    let remaining = entry.remaining(at: date)
    let low = remaining <= 5
    let copied = model.copiedID == entry.id
    VStack(spacing: 8) {
      HStack(alignment: .top, spacing: 10) {
        Avatar(name: entry.primary)
        VStack(alignment: .leading, spacing: 1) {
          HStack(spacing: 4) {
            Text(entry.primary).font(.callout.weight(.medium)).lineLimit(1)
            if entry.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.orange) }
          }
          if let s = entry.secondary { Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
          Text(OTP.grouped(entry.code(at: date), kind: entry.kind))
            .font(.system(size: 22, weight: .semibold, design: .monospaced))
            .foregroundStyle(low ? Warning.color : Color.accentColor)
            .padding(.top, 2)
          HStack(spacing: 5) {
            Text("Next").font(.system(size: 10, weight: .medium))
            Text(OTP.grouped(entry.nextCode(at: date), kind: entry.kind))
              .font(.system(size: 12, weight: .medium, design: .monospaced))
          }
          .foregroundStyle(.secondary)
          .accessibilityLabel("Next code \(entry.nextCode(at: date))")
        }
        Spacer(minLength: 4)
        VStack(alignment: .trailing, spacing: 6) {
          Button(action: toggle) {
            Image(systemName: "ellipsis.circle\(open ? ".fill" : "")").font(.system(size: 16))
              .foregroundStyle(open ? Color.accentColor : Color.secondary)
              .frame(width: 24, height: 22).contentShape(Rectangle())
          }
          .buttonStyle(PressableStyle())
          .help("Options")
          .accessibilityLabel("Options for \(entry.primary)")
          CountdownRing(remaining: remaining, period: entry.period)
        }
      }
      // Clicking anywhere on the card, the code itself included, copies the current code. The ⋯ button
      // is a real button, so it keeps its own clicks.
      .contentShape(Rectangle())
      .onTapGesture { model.copyCode(entry, at: date) }
      if open {
        VStack(spacing: 6) {
          HStack(spacing: 6) {
            action("Copy Next", "forward.end", prominent: true) { model.copyNextCode(entry, at: date); close() }
            action("Scanner", "qrcode") { close(); model.showQRCode(entry) }
            action(entry.pinned ? "Unpin" : "Pin", entry.pinned ? "pin.slash" : "pin") { model.togglePin(entry.id); close() }
          }
          HStack(spacing: 6) {
            action("Edit", "pencil") { close(); model.edit(entry) }
            action("Remove", "trash", destructive: true) { close(); model.confirmDelete(entry) }
          }
        }
        .transition(.opacity)
      }
    }
    .padding(.horizontal, 10).padding(.vertical, 8)
    .background(Color.primary.opacity(hovered ? 0.11 : 0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      // Unmistakable confirmation: the whole card turns green and says what is now on the clipboard.
      if copied {
        HStack(spacing: 12) {
          Image(systemName: "checkmark.circle.fill").font(.system(size: 28))
          VStack(alignment: .leading, spacing: 2) {
            Text(model.copiedNext ? "Next code copied" : "Code copied").font(.system(size: 15, weight: .semibold))
            Text(OTP.grouped(model.copiedCode, kind: entry.kind))
              .font(.system(size: 13, weight: .medium, design: .monospaced)).opacity(0.9)
          }
          Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Warning.success, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
    }
    .animation(.easeOut(duration: 0.16), value: copied)
    .onHover(perform: hover)
    .help("Click to copy the code")
    .accessibilityElement(children: .contain)
    .accessibilityAction(named: "Copy code") { model.copyCode(entry, at: date) }
  }

  private func action(_ title: LocalizedStringKey, _ symbol: String, prominent: Bool = false, destructive: Bool = false, _ run: @escaping () -> Void) -> some View {
    Button(action: run) {
      Label(title, systemImage: symbol).font(.caption.weight(.medium)).labelStyle(.titleAndIcon)
        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity).padding(.vertical, 5)
        .foregroundStyle(prominent ? Color.white : (destructive ? Warning.color : Color.primary))
        .background(prominent ? Color.accentColor : Color.primary.opacity(0.08), in: Capsule())
        .contentShape(Capsule())
    }
    .buttonStyle(PressableStyle())
  }
}

/// A colored circle with the first letter of the service, the same color every time.
private struct Avatar: View {
  let name: String
  var body: some View {
    let hue = Double(name.lowercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360
    Text(String(name.first.map { Character($0.uppercased()) } ?? "?"))
      .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
      .frame(width: 32, height: 32)
      .background(Color(hue: hue, saturation: 0.55, brightness: 0.78).gradient, in: Circle())
  }
}

/// Time left until the code changes; turns red for the last five seconds.
struct CountdownRing: View {
  let remaining: Double
  let period: Int
  var body: some View {
    let low = remaining <= 5
    ZStack {
      Circle().stroke(Color.primary.opacity(0.12), lineWidth: 3)
      Circle().trim(from: 0, to: max(0.02, remaining / Double(max(period, 1))))
        .stroke(low ? Warning.color : Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        .rotationEffect(.degrees(-90))
      Text("\(Int(remaining.rounded(.up)))").font(.system(size: 9, weight: .medium).monospacedDigit())
        .foregroundStyle(low ? Warning.color : Color.secondary)
    }
    .frame(width: 26, height: 26)
    .accessibilityLabel("\(Int(remaining.rounded(.up))) seconds left")
  }
}
