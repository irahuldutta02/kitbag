import AppKit
import ApplicationServices
import KitbagCore
import SwiftUI

/// What the tab remembers while it is open.
@MainActor private final class TabState: ObservableObject {
  @Published var query = ""
  @Published var copied: UUID?
  @Published var hovered: UUID?
}

@MainActor private final class TrustState: ObservableObject {
  @Published var trusted = AXIsProcessTrusted()
}

@MainActor private final class ShortcutPicker: ObservableObject {
  @Published var recording = false
  @Published var message: String?
  var monitor: Any?
}

/// The tab in the menu pop-up: recording status, search, history, and Clear.
struct ClipboardView: View {
  @ObservedObject var model: ClipboardModel
  @StateObject private var ui = TabState()

  var body: some View {
    let items = model.filtered(ui.query)
    VStack(alignment: .leading, spacing: 9) {
      // Status strip
      HStack(spacing: 8) {
        StatusDot(
          color: model.paused ? KitbagUI.warning : KitbagUI.success,
          active: !model.paused,
          size: 7
        )
        VStack(alignment: .leading, spacing: 1) {
          Text(model.paused ? "History paused" : "Recording copies")
            .font(.callout.weight(.semibold))
          HStack(spacing: 4) {
            if model.paused {
              Text("New copies won't be saved").font(.caption).foregroundStyle(.secondary)
            } else {
              KeycapBadge(model.shortcut.display)
              Text("opens at cursor").font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        Spacer(minLength: 4)
        Toggle(
          "Save what I copy",
          isOn: Binding(get: { !model.paused }, set: { model.paused = !$0 })
        )
        .toggleStyle(.switch)
        .controlSize(.small)
        .labelsHidden()
        .help(model.paused ? "Resume recording" : "Pause recording")
      }

      if !model.shortcutWorks {
        Label(
          "\(model.shortcut.display) is taken by another app. Pick another in Settings.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(KitbagUI.warning)
      }

      SearchFieldBar("Search clipboard…", text: $ui.query)

      if items.isEmpty {
        VStack(spacing: 6) {
          Image(systemName: ui.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(.tertiary)
          Text(ui.query.isEmpty ? "Nothing copied yet" : "No matches")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
      } else {
        ScrollView {
          LazyVStack(spacing: 2) {
            ForEach(items) { item in row(item) }
          }
        }
        .frame(height: min(Self.height(items), 300))
      }

      Divider().opacity(0.45)

      HStack {
        Text(model.items.count == 1 ? "1 item" : "\(model.items.count) items")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Menu {
          Button("Clear History (Keep Pinned)") { model.clear(keepPinned: true) }
          Button("Clear Everything", role: .destructive) { model.clear(keepPinned: false) }
        } label: {
          HStack(spacing: 3) {
            Text("Clear")
            Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .bold))
          }
          .font(.caption.weight(.medium))
          .foregroundStyle(model.items.isEmpty ? .tertiary : .secondary)
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .hoverHighlight(cornerRadius: 6)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.items.isEmpty)
      }
    }
    .card(padding: 11)
  }

  private static func height(_ items: [ClipItem]) -> CGFloat {
    items.reduce(0) { $0 + ($1.kind == .image ? 48 : 32) }
  }

  private func row(_ item: ClipItem) -> some View {
    ClipRow(model: model, item: item)
      .overlay(alignment: .trailing) {
        if ui.copied == item.id {
          Label("Copied", systemImage: "checkmark")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(KitbagUI.success, in: Capsule())
            .padding(.trailing, 4)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
        } else if ui.hovered == item.id {
          HStack(spacing: 2) {
            Button {
              model.togglePin(item.id)
            } label: {
              Image(systemName: item.pinned ? "pin.slash" : "pin")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Circle())
            }
            .capsuleHoverHighlight()
            .help(item.pinned ? "Unpin" : "Pin to top")

            Button {
              model.delete(item.id)
            } label: {
              Image(systemName: "trash")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(KitbagUI.danger)
                .frame(width: 22, height: 22)
                .contentShape(Circle())
            }
            .capsuleHoverHighlight(tint: KitbagUI.danger)
            .help("Delete")
          }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 3)
          .padding(.vertical, 2)
          .background(.regularMaterial, in: Capsule())
          .padding(.trailing, 4)
        }
      }
      .background {
        if ui.hovered == item.id {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.075))
        }
      }
      .animation(.easeOut(duration: 0.14), value: ui.copied == item.id)
      .contentShape(Rectangle())
      .onTapGesture {
        model.copy(item)
        ui.copied = item.id
        Task {
          try? await Task.sleep(nanoseconds: 1_200_000_000)
          if ui.copied == item.id { ui.copied = nil }
        }
      }
      .onHover { ui.hovered = $0 ? item.id : (ui.hovered == item.id ? nil : ui.hovered) }
      .help("Click to copy")
  }
}

struct ClipboardSettingsView: View {
  @ObservedObject var model: ClipboardModel
  @StateObject private var access = TrustState()
  @StateObject private var picker = ShortcutPicker()
  private let guide = AccessibilityGuide()

  private func reset() {
    picker.message =
      model.setShortcut(.default)
      ? nil : "\(ClipShortcut.default.display) is taken by another app."
  }

  private func startRecording() {
    picker.message = nil
    picker.recording = true
    model.pauseHotKey(true)
    picker.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
      if e.keyCode == 53 {  // esc
        stopRecording()
        return nil
      }
      let mods = ClipShortcut.carbonModifiers(e.modifierFlags)
      guard mods != 0 else {
        NSSound.beep()
        return nil
      }  // needs at least one modifier key
      let new = ClipShortcut(
        keyCode: UInt32(e.keyCode), modifiers: mods, label: ClipShortcut.label(for: e))
      stopRecording()
      if !model.setShortcut(new) {
        picker.message = "\(new.display) is taken by another app. Try a different one."
      }
      return nil
    }
  }

  private func stopRecording() {
    if let m = picker.monitor { NSEvent.removeMonitor(m) }
    picker.monitor = nil
    picker.recording = false
    model.pauseHotKey(false)
  }

  var body: some View {
    Toggle(
      "Save what I copy",
      isOn: Binding(get: { !model.paused }, set: { model.paused = !$0 })
    )
    Picker("Keep the last", selection: $model.limit) {
      ForEach(ClipboardModel.limits, id: \.self) { Text("\($0) items").tag($0) }
    }
    LabeledContent("Open the history") {
      HStack(spacing: 8) {
        Text(picker.recording ? "Press new keys…" : model.shortcut.display)
          .font(.system(.body, design: .rounded).weight(.medium))
          .foregroundStyle(picker.recording ? Color.accentColor : .primary)
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(
            .quaternary.opacity(0.6),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
          )
        if model.shortcut != .default && !picker.recording {
          Button("Reset") { reset() }.controlSize(.small)
        }
        Button(picker.recording ? "Cancel" : "Change") {
          picker.recording ? stopRecording() : startRecording()
        }
        .controlSize(.small)
      }
    }
    if let m = picker.message { Text(m).font(.caption).foregroundStyle(KitbagUI.danger) }
    LabeledContent("Paste into the app in front") {
      if access.trusted {
        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(KitbagUI.success)
      } else {
        Button("Allow Accessibility…") { guide.begin { access.trusted = true } }
      }
    }
    Text(
      "Passwords copied from password managers are never saved. Pinned items stay until you remove them."
    )
    .font(.caption)
    .foregroundStyle(.secondary)
    .onDisappear { if picker.recording { stopRecording() } }
  }
}
