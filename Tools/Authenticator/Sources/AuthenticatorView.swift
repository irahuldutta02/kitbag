import KitbagCore
import SwiftUI

@MainActor private final class TabState: ObservableObject {
  @Published var query = ""
  /// The "add an account" choices are showing.
  @Published var adding = false
  /// The account whose options (copy next, QR, pin, edit, remove) are open.
  @Published var expanded: UUID?
  @Published var hovered: UUID?
}

/// The tab in the menu pop-up: search, live codes, and inline account options.
struct AuthenticatorView: View {
  @ObservedObject var model: AuthenticatorModel
  @StateObject private var ui = TabState()

  var body: some View {
    let list = model.filtered(ui.query)
    return content(list)
      .onAppear {
        model.unlock(interactive: false)  // silent; stays locked if macOS would ask for a password
        model.refreshOrder()
      }
  }

  private func content(_ list: [AuthEntry]) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 8) {
        SearchFieldBar(
          "Search accounts…", text: $ui.query, autoFocus: true,
          plainPlaceholder: String(localized: "Search accounts…")
        ) {
          if let first = model.filtered(ui.query).first { model.copyCode(first) }
        }
        Button {
          withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) { ui.adding.toggle() }
        } label: {
          Image(systemName: ui.adding ? "xmark" : "plus")
            .font(.system(size: 12.5, weight: .bold))
            .foregroundStyle(ui.adding ? Color.secondary : Color.white)
            .frame(width: 30, height: 30)
            .background(
              ui.adding ? Color.primary.opacity(0.09) : Color.accentColor,
              in: Circle()
            )
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(ui.adding ? "Close" : "Add an account")
        .accessibilityLabel(ui.adding ? "Close" : "Add an account")
      }

      if ui.adding {
        AddChoices(model: model) {
          withAnimation(.easeOut(duration: 0.15)) { ui.adding = false }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }

      if let err = model.storageError {
        Label(err, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(KitbagUI.danger)
      }

      if model.shortcut != nil, !model.shortcutWorks {
        Label("Shortcut is taken by another app.", systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(KitbagUI.warning)
      }

      if model.locked {
        LockedState(model: model)
      } else if model.entries.isEmpty {
        if !ui.adding { EmptyState(model: model) }
      } else if list.isEmpty {
        VStack(spacing: 6) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 20, weight: .light))
            .foregroundStyle(.tertiary)
          Text("No matching accounts")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
      } else {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
          ScrollView {
            LazyVStack(spacing: 6) {
              ForEach(list) { entry in
                EntryRow(
                  model: model,
                  entry: entry,
                  date: ctx.date,
                  open: ui.expanded == entry.id,
                  hovered: ui.hovered == entry.id,
                  hover: {
                    ui.hovered = $0 ? entry.id : (ui.hovered == entry.id ? nil : ui.hovered)
                  },
                  toggle: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                      ui.expanded = ui.expanded == entry.id ? nil : entry.id
                    }
                  },
                  close: {
                    withAnimation(.easeInOut(duration: 0.15)) { ui.expanded = nil }
                  }
                )
              }
            }
          }
          .frame(height: min(CGFloat(list.count) * 92 + (ui.expanded == nil ? 0 : 72), 360))
        }
      }

      if !model.entries.isEmpty {
        Divider().opacity(0.45)
        HStack {
          Text(model.entries.count == 1 ? "1 account" : "\(model.entries.count) accounts")
          Spacer()
          Text("Click any card to copy")
          if let s = model.shortcut { KeycapBadge(s.display) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .card(padding: 11)
  }
}

/// Every way of adding an account, as interactive list rows.
private struct AddChoices: View {
  let model: AuthenticatorModel
  let done: () -> Void
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    VStack(spacing: 2) {
      choice("Scan QR on Screen", "viewfinder", "Snip a QR code anywhere on screen") {
        model.scanScreen()
      }
      choice("Scan with Camera", "camera", "Hold a QR code up to your Mac") {
        model.scanCamera()
      }
      choice("Scan from Image…", "photo", nil) { model.scanImageFile() }
      choice("Paste from Clipboard", "doc.on.clipboard", nil) { model.pasteFromClipboard() }
      choice("Enter Manually…", "keyboard", nil) { model.addManually() }
    }
    .padding(5)
    .background(
      scheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.045),
      in: RoundedRectangle(cornerRadius: 11, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .strokeBorder(
          scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
          lineWidth: 0.5
        )
    )
  }

  private func choice(
    _ title: LocalizedStringKey, _ symbol: String, _ hint: LocalizedStringKey?,
    _ action: @escaping () -> Void
  ) -> some View {
    Button {
      done()
      action()
    } label: {
      HStack(spacing: 10) {
        Image(systemName: symbol)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.accentColor)
          .frame(width: 24, height: 24)
          .background(
            Color.accentColor.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
          )
        VStack(alignment: .leading, spacing: 1) {
          Text(title).font(.callout.weight(.medium))
          if let hint { Text(hint).font(.caption2).foregroundStyle(.secondary) }
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 9.5, weight: .semibold))
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 7)
      .padding(.vertical, 5)
      .hoverHighlight(cornerRadius: 8)
      .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(PressableStyle())
  }
}

private struct LockedState: View {
  let model: AuthenticatorModel
  var body: some View {
    VStack(spacing: 9) {
      ZStack {
        Circle().fill(Color.accentColor.opacity(0.11)).frame(width: 46, height: 46)
        Image(systemName: "lock.fill")
          .font(.system(size: 20))
          .foregroundStyle(Color.accentColor)
      }
      Text("Your accounts are locked").font(.callout.weight(.semibold))
      Text("Your accounts are safe in your Keychain. macOS needs your Mac password once to let this version of Kitbag read them.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Button {
        model.unlock(interactive: true)
      } label: {
        Label("Unlock Accounts", systemImage: "key.fill")
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
      .padding(.top, 2)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 16)
  }
}

private struct EmptyState: View {
  let model: AuthenticatorModel
  var body: some View {
    VStack(spacing: 9) {
      ZStack {
        Circle().fill(Color.accentColor.opacity(0.11)).frame(width: 46, height: 46)
        Image(systemName: "lock.shield.fill")
          .font(.system(size: 21))
          .foregroundStyle(Color.accentColor)
      }
      Text("No accounts yet").font(.callout.weight(.semibold))
      Text("Scan a website's 2FA QR code or enter your secret key by hand.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      HStack(spacing: 8) {
        Button {
          model.scanScreen()
        } label: {
          Label("Scan QR Code", systemImage: "viewfinder")
        }
        .buttonStyle(.borderedProminent)
        Button("Enter Manually") { model.addManually() }
          .buttonStyle(.bordered)
      }
      .controlSize(.small)
      .padding(.top, 2)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 16)
  }
}

/// Account row: avatar, issuer & options on top; prominent code, next code & countdown ring below.
private struct EntryRow: View {
  let model: AuthenticatorModel
  let entry: AuthEntry
  let date: Date
  let open: Bool
  let hovered: Bool
  let hover: (Bool) -> Void
  let toggle: () -> Void
  let close: () -> Void
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let remaining = entry.remaining(at: date)
    let low = remaining <= 5
    let copied = model.copiedID == entry.id
    let fill =
      scheme == .dark
      ? Color.white.opacity(hovered ? 0.10 : 0.055)
      : Color.black.opacity(hovered ? 0.065 : 0.038)
    let stroke =
      scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)

    VStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .center, spacing: 10) {
          Avatar(name: entry.primary)

          VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
              Text(entry.primary)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
              if entry.pinned {
                Image(systemName: "pin.fill")
                  .font(.system(size: 8.5))
                  .foregroundStyle(KitbagUI.warning)
              }
              if entry.copies > 0 {
                HStack(spacing: 2) {
                  Image(systemName: "doc.on.doc.fill").font(.system(size: 7))
                  Text(entry.copies > 999 ? "999+" : "\(entry.copies)")
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(scheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.07)))
                .help(entry.copies == 1 ? "Used 1 time" : "Used \(entry.copies) times")
                .accessibilityLabel("Used \(entry.copies) times")
              }
            }
            if let s = entry.secondary {
              Text(s)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
          }

          Spacer(minLength: 6)

          Button(action: toggle) {
            Image(systemName: open ? "ellipsis.circle.fill" : "ellipsis")
              .font(.system(size: open ? 15 : 13, weight: .semibold))
              .foregroundStyle(open ? Color.accentColor : Color.secondary)
              .frame(width: 26, height: 26)
              .contentShape(Circle())
          }
          .buttonStyle(PressableStyle())
          .capsuleHoverHighlight()
          .help("Account options")
          .accessibilityLabel("Options for \(entry.primary)")
        }

        HStack(alignment: .center, spacing: 8) {
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(OTP.grouped(entry.code(at: date), kind: entry.kind))
              .font(.system(size: 22, weight: .bold, design: .monospaced))
              .foregroundStyle(low ? KitbagUI.danger : Color.primary)
              .lineLimit(1)
              .fixedSize(horizontal: true, vertical: false)

            HStack(spacing: 4) {
              Text("Next")
                .font(.system(size: 10, weight: .medium))
              Text(OTP.grouped(entry.nextCode(at: date), kind: entry.kind))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(low ? Color.primary.opacity(0.85) : Color.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Next code \(entry.nextCode(at: date))")
          }

          Spacer(minLength: 4)

          CountdownRing(remaining: remaining, period: entry.period)
        }
      }
      .contentShape(Rectangle())
      .onTapGesture { model.copyCode(entry, at: date) }

      if open {
        Divider().opacity(0.45)
        VStack(spacing: 6) {
          HStack(spacing: 6) {
            action("Copy Next", "forward.end.fill", prominent: true) {
              model.copyNextCode(entry, at: date)
              close()
            }
            action("QR Code", "qrcode") {
              close()
              model.showQRCode(entry)
            }
            action(entry.pinned ? "Unpin" : "Pin", entry.pinned ? "pin.slash" : "pin") {
              model.togglePin(entry.id)
              close()
            }
          }
          HStack(spacing: 6) {
            action("Edit", "pencil") {
              close()
              model.edit(entry)
            }
            action("Remove", "trash", destructive: true) {
              close()
              model.confirmDelete(entry)
            }
          }
        }
        .transition(.opacity)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 9)
    .background(fill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .strokeBorder(low ? KitbagUI.danger.opacity(0.35) : stroke, lineWidth: low ? 1 : 0.5)
    )
    .overlay {
      if copied {
        HStack(spacing: 11) {
          Image(systemName: "checkmark.circle.fill").font(.system(size: 24))
          VStack(alignment: .leading, spacing: 1) {
            Text(model.copiedNext ? "Next code copied" : "Code copied")
              .font(.callout.weight(.semibold))
            Text(OTP.grouped(model.copiedCode, kind: entry.kind))
              .font(.system(size: 13, weight: .semibold, design: .monospaced))
              .opacity(0.92)
          }
          Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KitbagUI.success, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
    }
    .animation(.easeOut(duration: 0.16), value: copied)
    .onHover(perform: hover)
    .help("Click to copy code")
    .accessibilityElement(children: .contain)
    .accessibilityAction(named: "Copy code") { model.copyCode(entry, at: date) }
  }

  private func action(
    _ title: LocalizedStringKey, _ symbol: String, prominent: Bool = false,
    destructive: Bool = false, _ run: @escaping () -> Void
  ) -> some View {
    Button(action: run) {
      Label(title, systemImage: symbol)
        .font(.caption.weight(.medium))
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5.5)
        .foregroundStyle(prominent ? Color.white : (destructive ? KitbagUI.danger : Color.primary))
        .background(
          prominent
            ? Color.accentColor
            : (destructive ? KitbagUI.danger.opacity(0.12) : Color.primary.opacity(0.08)),
          in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .hoverHighlight(
          cornerRadius: 7, tint: prominent ? .white : (destructive ? KitbagUI.danger : nil)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
    .buttonStyle(PressableStyle())
  }
}

/// Rounded-square gradient avatar seeded by service name.
private struct Avatar: View {
  let name: String
  var body: some View {
    let hue =
      Double(name.lowercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360
    Text(String(name.first.map { Character($0.uppercased()) } ?? "?"))
      .font(.system(size: 14, weight: .bold, design: .rounded))
      .foregroundStyle(.white)
      .frame(width: 32, height: 32)
      .background(
        Color(hue: hue, saturation: 0.56, brightness: 0.78).gradient,
        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
  }
}

/// Time left until the code changes; shifts to red for the last 5 seconds.
struct CountdownRing: View {
  let remaining: Double
  let period: Int
  var body: some View {
    let low = remaining <= 5
    let progress = min(1, max(0.02, remaining / Double(max(period, 1))))
    ZStack {
      Canvas { ctx, size in
        let lineWidth: CGFloat = 2.5
        let radius = min(size.width, size.height) / 2 - lineWidth / 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        var track = Path()
        track.addArc(
          center: center, radius: radius, startAngle: .zero, endAngle: .degrees(360),
          clockwise: false)
        ctx.stroke(track, with: .color(Color.primary.opacity(0.14)), lineWidth: lineWidth)

        var arc = Path()
        arc.addArc(
          center: center,
          radius: radius,
          startAngle: .degrees(-90),
          endAngle: .degrees(-90 + 360 * progress),
          clockwise: false
        )
        ctx.stroke(
          arc,
          with: .color(low ? KitbagUI.danger : Color.accentColor),
          style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
      }
      Text("\(Int(remaining.rounded(.up)))")
        .font(.system(size: 9, weight: .semibold).monospacedDigit())
        .foregroundStyle(low ? KitbagUI.danger : Color.secondary)
    }
    .frame(width: 26, height: 26)
    .accessibilityLabel("\(Int(remaining.rounded(.up))) seconds left")
  }
}
