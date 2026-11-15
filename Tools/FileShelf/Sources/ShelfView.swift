import AppKit
import KitbagCore
import SwiftUI

struct ShelfView: View {
  @ObservedObject var model: ShelfModel

  var body: some View {
    VStack(spacing: 10) {
      ModeSwitch(mode: $model.mode)
      Text(
        model.mode == .copy
          ? "Dragging out copies the files." : "Dragging out moves the files."
      )
      .font(.caption).foregroundStyle(.secondary)

      Group {
        if model.items.isEmpty {
          VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down.fill")
              .font(.system(size: 34, weight: .light))
              .foregroundStyle(model.dropTargeted ? Color.accentColor : .secondary)
            Text("Drop files or folders here").font(.callout.weight(.medium))
            Text("They wait here until you drag them out.")
              .font(.caption).foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, minHeight: 150)
        } else {
          VStack(spacing: 10) {
            StackView(model: model)
            Text("Drag the stack to a folder or app").font(.caption).foregroundStyle(.secondary)
            HStack {
              Text(footer).font(.caption.weight(.medium))
              Spacer()
              Button(role: .destructive) {
                model.clear()
              } label: {
                Label("Clear All", systemImage: "trash")
              }
              .controlSize(.small)
            }
          }
        }
      }
      .card()
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(Color.accentColor.opacity(model.dropTargeted ? 0.12 : 0))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .strokeBorder(
            model.dropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
            style: StrokeStyle(
              lineWidth: model.dropTargeted ? 2 : 1,
              dash: model.items.isEmpty ? [5, 4] : []))
      )

      // Each destination app (Blip) shows its on/off switch while it is off or nothing is on the
      // shelf; once it is on and there is something to send, only "Send with …" is shown.
      ForEach(model.senders) { sender in
        SenderSlot(sender: sender, model: model)
      }

      if let m = model.message {
        Text(m).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      }
    }
    .dropDestination(for: URL.self) { urls, _ in
      model.add(urls)
      NotificationCenter.default.post(name: .kitbagFileDropFinished, object: nil)
      return !urls.isEmpty
    } isTargeted: {
      model.dropTargeted = $0
      if !$0 { NotificationCenter.default.post(name: .kitbagFileDropFinished, object: nil) }
    }
  }

  private var footer: String {
    let n = String(localized: "\(model.items.count) items")
    return model.missing.isEmpty
      ? n : n + " · " + String(localized: "\(model.missing.count) missing")
  }
}

/// Two-option pill matching the tab bar style.
private struct ModeSwitch: View {
  @Binding var mode: TransferMode

  var body: some View {
    HStack(spacing: 2) {
      option(.copy, "Copy", "doc.on.doc")
      option(.move, "Move", "arrow.right.circle")
    }
    .padding(3)
    .background(.quaternary.opacity(0.6), in: Capsule())
    .accessibilityElement(children: .contain)
    .accessibilityLabel("When dropped in a folder")
  }

  private func option(_ value: TransferMode, _ title: LocalizedStringKey, _ symbol: String)
    -> some View
  {
    let on = mode == value
    return Button {
      mode = value
    } label: {
      Label(title, systemImage: symbol)
        .font(.callout.weight(.medium))
        .foregroundStyle(on ? Color.white : Color.secondary)
        .frame(maxWidth: .infinity, minHeight: 26)
        .background(on ? Color.accentColor : .clear, in: Capsule())
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(on ? .isSelected : [])
  }
}

/// All items as one pile of icons; dragging it drags every item.
private struct StackView: View {
  @ObservedObject var model: ShelfModel

  var body: some View {
    let shown = Array(model.items.suffix(3))
    ZStack {
      ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
        let depth = shown.count - 1 - index  // 0 = top of the pile
        let side: Double = depth.isMultiple(of: 2) ? 1 : -1
        Image(nsImage: model.icon(for: item.id, size: 72))
          .resizable().frame(width: 72, height: 72)
          .rotationEffect(.degrees(depth == 0 ? 0 : side * Double(depth) * 7))
          .offset(x: depth == 0 ? 0 : side * Double(depth) * 9, y: Double(depth) * -4)
          .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 110)
    .overlay(alignment: .topTrailing) {
      Text("\(model.items.count)")
        .font(.caption.bold().monospacedDigit()).foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(Color.accentColor))
    }
    .overlay(DragSource(model: model))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Stack of \(model.items.count) files. Drag to copy or move them out.")
  }
}

private struct DragSource: NSViewRepresentable {
  let model: ShelfModel
  func makeNSView(context: Context) -> DragNSView {
    let v = DragNSView()
    v.model = model
    return v
  }
  func updateNSView(_ v: DragNSView, context: Context) { v.model = model }
}

/// Starts a multi-file drag; the Copy/Move switch decides the allowed operation.
private final class DragNSView: NSView, NSDraggingSource {
  weak var model: ShelfModel?
  private var ids: [UUID] = []

  override func mouseDown(with event: NSEvent) {}  // lets mouseDragged arrive

  override func mouseDragged(with event: NSEvent) {
    guard let model else { return }
    let entries = model.items.compactMap { item in model.url(for: item.id).map { (item.id, $0) } }
    guard !entries.isEmpty else { return }
    ids = entries.map(\.0)
    let items = entries.enumerated().map { i, entry -> NSDraggingItem in
      let item = NSDraggingItem(pasteboardWriter: entry.1 as NSURL)
      let frame = NSRect(
        x: bounds.midX - 24 + CGFloat(min(i, 3)) * 4, y: bounds.midY - 24 - CGFloat(min(i, 3)) * 4,
        width: 48, height: 48)
      item.setDraggingFrame(frame, contents: i < 4 ? model.icon(for: entry.0, size: 48) : nil)
      return item
    }
    beginDraggingSession(with: items, event: event, source: self)
  }

  func draggingSession(_ s: NSDraggingSession, sourceOperationMaskFor c: NSDraggingContext)
    -> NSDragOperation
  {
    guard c == .outsideApplication else { return [] }
    return model?.mode == .move ? .move : .copy
  }

  func draggingSession(_ s: NSDraggingSession, endedAt p: NSPoint, operation: NSDragOperation) {
    // Moved (or trashed) by the receiver: the originals are gone. A copy clears only if configured.
    let gone = operation.contains(.move) || operation.contains(.delete)
    if gone || (model?.clearAfterDrop == true && !operation.isEmpty) {
      for id in ids { model?.remove(id) }
    }
    ids = []
  }
}

/// One row per destination app (Blip), always the same shape so nothing jumps: icon and name on
/// the left, the on/off switch on the right, and a "Send" button between them once the app is on
/// and there is something on the shelf. Files can also be dropped straight onto the row.
private struct SenderSlot: View {
  let sender: FileSender
  @ObservedObject var model: ShelfModel

  var body: some View {
    if let power = sender.power {
      SenderRow(sender: sender, model: model, power: power)
    } else if !model.items.isEmpty {
      PlainSenderButton(sender: sender, model: model)
    }
  }
}

private struct SenderRow: View {
  let sender: FileSender
  @ObservedObject var model: ShelfModel
  @ObservedObject var power: SenderPower

  private var canSend: Bool { power.isOn && !model.items.isEmpty }

  var body: some View {
    HStack(spacing: 8) {
      sender.icon().frame(width: 20, height: 20)
      VStack(alignment: .leading, spacing: 0) {
        Text(sender.title).font(.callout.weight(.medium))
        Text(power.isBusy ? "Working…" : (power.isOn ? "On" : "Off"))
          .font(.caption2).foregroundStyle(power.isOn ? Color.green : .secondary)
      }
      Spacer(minLength: 6)
      if canSend {
        Button { model.send(with: sender) } label: {
          Label("Send", systemImage: "paperplane.fill").font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Color.accentColor, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Send the shelf with \(sender.title)")
      }
      if power.isBusy { ProgressView().controlSize(.small) }
      Toggle("\(sender.title) service", isOn: Binding(get: { power.isOn }, set: { power.set($0) }))
        .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(power.isBusy)
    }
    .padding(.horizontal, 10).padding(.vertical, 7)
    .glass(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12).strokeBorder(
        Color.accentColor, lineWidth: model.targetedSender == sender.id ? 2 : 0)
    )
    .dropDestination(for: URL.self) { urls, _ in
      model.send(with: sender, urls: urls)
      NotificationCenter.default.post(name: .kitbagFileDropFinished, object: nil)
      return !urls.isEmpty
    } isTargeted: {
      model.targetedSender = $0 ? sender.id : nil
    }
    .animation(.default, value: canSend)
  }
}

/// "Send with X" for destinations that have no on/off switch.
private struct PlainSenderButton: View {
  let sender: FileSender
  @ObservedObject var model: ShelfModel

  var body: some View {
    Button {
      model.send(with: sender)
    } label: {
      HStack(spacing: 8) {
        sender.icon().frame(width: 20, height: 20)
        Text("Send with \(sender.title)").font(.callout)
        Spacer()
        Image(systemName: "paperplane").foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 10).padding(.vertical, 7)
    .glass(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12).strokeBorder(
        Color.accentColor, lineWidth: model.targetedSender == sender.id ? 2 : 0)
    )
    .dropDestination(for: URL.self) { urls, _ in
      model.send(with: sender, urls: urls)
      NotificationCenter.default.post(name: .kitbagFileDropFinished, object: nil)
      return !urls.isEmpty
    } isTargeted: {
      model.targetedSender = $0 ? sender.id : nil
    }
  }
}
