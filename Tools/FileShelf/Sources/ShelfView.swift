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
            HStack(spacing: 8) {
              Button { model.addFromPicker() } label: { Label("Add files…", systemImage: "plus") }
              Button { model.pasteFromClipboard() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                .keyboardShortcut("v", modifiers: .command)
            }
            .controlSize(.small)
          }
          .frame(maxWidth: .infinity, minHeight: 150)
        } else {
          VStack(spacing: 10) {
            StackView(model: model)
            Text("Drag the stack to a folder or app").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
              Button { model.listExpanded.toggle() } label: {
                HStack(spacing: 4) {
                  Text(footer).font(.caption.weight(.medium))
                  Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(model.listExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .help(model.listExpanded ? "Hide files" : "Show files")
              Spacer()
              Button { model.pasteFromClipboard() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                .controlSize(.small).keyboardShortcut("v", modifiers: .command)
                .help("Paste a copied file, image, link or text (⌘V)")
              Button { model.addFromPicker() } label: { Label("Add", systemImage: "plus") }
                .controlSize(.small).help("Add files from your Mac")
              Button(role: .destructive) {
                model.clear()
              } label: {
                Label("Clear All", systemImage: "trash")
              }
              .controlSize(.small)
            }
            if model.listExpanded { ItemList(model: model) }
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

      if !model.items.isEmpty, !model.convertFormats.isEmpty || model.converting != nil || model.pendingConvert != nil {
        ConvertRow(model: model)
      }

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
    let n = model.items.count == 1
      ? String(localized: "1 item") : String(localized: "\(model.items.count) items")
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

/// "Convert to" with one button per format that fits what is on the shelf. Tapping one shows what
/// will happen (sizes before and after) and asks where to save. While a conversion runs it becomes
/// a progress bar with a Cancel button.
private struct ConvertRow: View {
  @ObservedObject var model: ShelfModel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let p = model.converting {
        progress(p)
      } else if let request = model.pendingConvert {
        confirm(request)
      } else {
        picker
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glass(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .animation(.default, value: model.pendingConvert)
  }

  // MARK: Step 1: pick a format

  private var picker: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Convert to", systemImage: "arrow.triangle.2.circlepath")
        .font(.callout.weight(.semibold)).lineLimit(1)
      HStack(spacing: 6) {
        ForEach(model.convertFormats) { f in
          Button { model.requestConvert(.format(f)) } label: {
            Text(f.label).font(.callout.weight(.semibold))
              .frame(maxWidth: .infinity).padding(.vertical, 7)
              .background(Color.accentColor.opacity(0.2), in: Capsule())
              .contentShape(Capsule())
          }
          .buttonStyle(PressableStyle())
          .help("Convert to \(f.label)")
        }
      }
      if model.canOptimize {
        HStack(spacing: 6) {
          action("Compress", "arrow.down.right.and.arrow.up.left") { model.requestConvert(.compress) }
          action("Remove data", "eye.slash") { model.requestConvert(.cleanOnly) }
        }
      }
      if model.canMerge {
        Button { model.requestConvert(.mergePDF) } label: {
          Label("Combine into one PDF", systemImage: "doc.on.doc.fill")
            .font(.callout.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 7)
            .background(Color.primary.opacity(0.08), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func action(_ title: LocalizedStringKey, _ symbol: String, run: @escaping () -> Void) -> some View {
    Button(action: run) {
      Label(title, systemImage: symbol).font(.callout.weight(.medium)).lineLimit(1)
        .frame(maxWidth: .infinity).padding(.vertical, 7)
        .background(Color.primary.opacity(0.1), in: Capsule())
        .contentShape(Capsule())
    }
    .buttonStyle(PressableStyle())
  }

  // MARK: Step 2: what will happen, then where to save

  private func confirm(_ request: ConvertRequest) -> some View {
    let plan = model.plan(for: request)
    let sameFormat = request == .compress || request == .cleanOnly
    let compressing = model.compressEnabled && request != .mergePDF
    let nothingToDo = sameFormat && !model.compressEnabled && !model.cleanEnabled
    return VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(heading(request)).font(.callout.weight(.semibold)).lineLimit(1)
        Spacer()
        Button("Cancel") { model.cancelRequest() }.controlSize(.small).buttonStyle(.borderless)
      }
      SizeComparison(rows: model.estimateRows, estimating: model.estimating)
      if request != .mergePDF {
        Toggle("Compress", isOn: $model.compressEnabled).toggleStyle(.checkbox).font(.callout)
        if compressing {
          Picker("Strength", selection: $model.compressLevel) {
            ForEach(CompressLevel.allCases) { Text($0.label).tag($0) }
          }
          .pickerStyle(.segmented).labelsHidden()
        }
      }
      if sameFormat {
        Toggle("Remove hidden data", isOn: $model.cleanEnabled).toggleStyle(.checkbox).font(.callout)
          .help("Camera info, location and AI details such as prompts and content credentials")
      } else if plan.hasMetadata {
        Toggle("Remove hidden data", isOn: $model.stripMetadata).toggleStyle(.checkbox).font(.callout)
          .help("Camera info, location and AI details such as prompts and content credentials")
      }
      VStack(spacing: 8) {
        HStack(spacing: 8) {
          choice("Original location", "folder") { model.runPending(saveTo: .original) }
          choice("Choose folder…", "folder.badge.plus") { model.chooseFolderAndRun() }
        }
        if sameFormat {
          choice("Replace originals", "arrow.triangle.2.circlepath") { model.runPending(saveTo: .replace) }
        }
      }
      .disabled(nothingToDo)
      .opacity(nothingToDo ? 0.5 : 1)
    }
  }

  private func progress(_ p: ConvertProgress) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
        Text("\(p.done) of \(p.total)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        Button("Cancel") { model.cancelConvert() }.controlSize(.small)
      }
      Text("Converting to \(p.title)…").font(.caption).foregroundStyle(.secondary)
    }
  }

  private func heading(_ r: ConvertRequest) -> String {
    switch r {
    case .format(let f): return String(localized: "Convert to \(f.label)")
    case .mergePDF: return String(localized: "Combine into one PDF")
    case .compress, .cleanOnly:
      switch (model.compressEnabled, model.cleanEnabled) {
      case (true, true): return String(localized: "Compress and remove data")
      case (false, true): return String(localized: "Remove hidden data")
      case (true, false): return String(localized: "Compress")
      default: return String(localized: "Choose what to do")
      }
    }
  }

  private func choice(_ title: LocalizedStringKey, _ symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Label(title, systemImage: symbol).font(.callout.weight(.medium)).lineLimit(1)
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.2), in: Capsule())
        .contentShape(Capsule())
    }
    .buttonStyle(PressableStyle())
  }
}

/// Total size now and after converting, with the saving.
private struct SizeComparison: View {
  let rows: [EstimateRow]
  let estimating: Bool

  private static let formatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f
  }()

  private func bytes(_ n: Int64) -> String { Self.formatter.string(fromByteCount: n) }

  var body: some View {
    let done = rows.filter { $0.after != nil }
    let before = done.map(\.before).reduce(0, +)
    let after = done.compactMap(\.after).reduce(0, +)
    HStack(spacing: 6) {
      if done.isEmpty {
        if estimating { ProgressView().controlSize(.small) }
        Text(estimating ? "Working out sizes…" : "Size can't be estimated")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        Text("\(bytes(before)) → \(bytes(after))").font(.callout.weight(.semibold).monospacedDigit())
        let c = ShelfFormat.change(before, after)
        Text(c.text).font(.caption.weight(.semibold)).foregroundStyle(c.color)
        if estimating { ProgressView().controlSize(.mini) }
      }
    }
  }
}

enum ShelfFormat {
  static let formatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f
  }()

  static func bytes(_ n: Int64) -> String { formatter.string(fromByteCount: n) }

  static func change(_ before: Int64, _ after: Int64) -> (text: String, color: Color) {
    guard before > 0 else { return ("", .secondary) }
    let pct = Int((Double(after - before) / Double(before) * 100).rounded())
    if pct == 0 { return (String(localized: "same size"), .secondary) }
    return pct < 0
      ? (String(localized: "\(-pct)% smaller"), .green) : (String(localized: "\(pct)% larger"), .orange)
  }
}

/// Every file on the shelf, with its size (or before → after while converting) and a remove button.
private struct ItemList: View {
  @ObservedObject var model: ShelfModel

  var body: some View {
    ScrollView {
      VStack(spacing: 2) {
        ForEach(model.items) { item in
          let missing = model.missing.contains(item.id)
          let est = model.estimateRows.first { $0.id == item.id }
          HStack(spacing: 8) {
            Image(nsImage: model.icon(for: item.id, size: 18)).resizable().frame(width: 18, height: 18)
            Text(item.name).font(.caption).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            if missing {
              Text("missing").font(.caption2).foregroundStyle(.red)
            } else if let est, let after = est.after {
              Text("\(ShelfFormat.bytes(est.before)) → \(ShelfFormat.bytes(after))")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            } else if let size = model.fileSize(for: item.id) {
              Text(ShelfFormat.bytes(size)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            Button { model.remove(item.id) } label: { Image(systemName: "xmark.circle.fill") }
              .buttonStyle(.plain).foregroundStyle(.tertiary).help("Remove from the shelf")
              .accessibilityLabel("Remove \(item.name)")
          }
          .padding(.vertical, 2)
        }
      }
    }
    .frame(maxHeight: 150)
  }
}
