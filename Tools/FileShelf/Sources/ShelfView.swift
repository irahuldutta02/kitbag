import AppKit
import KitbagCore
import SwiftUI

struct ShelfView: View {
  @ObservedObject var model: ShelfModel

  var body: some View {
    VStack(spacing: 10) {
      ModeSwitch(mode: $model.mode)

      Group {
        if model.items.isEmpty {
          VStack(spacing: 9) {
            ZStack {
              Circle()
                .fill(
                  model.dropTargeted
                    ? Color.accentColor.opacity(0.18)
                    : Color.accentColor.opacity(0.10)
                )
                .frame(width: 48, height: 48)
              Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(
                  model.dropTargeted ? Color.accentColor : Color.accentColor.opacity(0.85)
                )
                .scaleEffect(model.dropTargeted ? 1.1 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: model.dropTargeted)
            }
            VStack(spacing: 2) {
              Text(model.dropTargeted ? "Release to add to shelf" : "Drop files or folders here")
                .font(.callout.weight(.semibold))
              Text(
                model.mode == .copy
                  ? "Hold items temporarily, then drag out to copy."
                  : "Hold items temporarily, then drag out to move."
              )
              .font(.caption)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
            }
            HStack(spacing: 8) {
              Button {
                model.addFromPicker()
              } label: {
                Label("Add Files…", systemImage: "plus")
              }
              .buttonStyle(.borderedProminent)
              Button {
                model.pasteFromClipboard()
              } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
              }
              .buttonStyle(.bordered)
              .keyboardShortcut("v", modifiers: .command)
            }
            .controlSize(.small)
            .padding(.top, 2)
          }
          .frame(maxWidth: .infinity, minHeight: 152)
        } else {
          VStack(spacing: 10) {
            StackView(model: model)
            Text(
              model.mode == .copy
                ? "Drag stack out to copy" : "Drag stack out to move"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 6) {
              Button {
                withAnimation(.easeInOut(duration: 0.16)) { model.listExpanded.toggle() }
              } label: {
                HStack(spacing: 4) {
                  Text(footer).font(.caption.weight(.semibold))
                  Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .rotationEffect(.degrees(model.listExpanded ? 90 : 0))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
              }
              .buttonStyle(.plain)
              .hoverHighlight(cornerRadius: 6)
              .help(model.listExpanded ? "Hide files" : "Show files")

              Spacer(minLength: 4)

              compactAction("doc.on.clipboard", label: "Paste", help: "Paste from clipboard (⌘V)") {
                model.pasteFromClipboard()
              }
              .keyboardShortcut("v", modifiers: .command)

              compactAction("plus", label: "Add", help: "Add files from your Mac") {
                model.addFromPicker()
              }

              Button(role: .destructive) {
                model.clear()
              } label: {
                Image(systemName: "trash")
                  .font(.system(size: 11.5, weight: .medium))
                  .foregroundStyle(KitbagUI.danger)
                  .frame(width: 24, height: 24)
                  .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
              }
              .buttonStyle(.plain)
              .hoverHighlight(cornerRadius: 6, tint: KitbagUI.danger)
              .help("Clear all items")
              .accessibilityLabel("Clear All")
            }

            if model.listExpanded {
              Divider().opacity(0.45)
              ItemList(model: model)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
          }
        }
      }
      .card(padding: 12)
      .background(
        RoundedRectangle(cornerRadius: KitbagUI.cardRadius, style: .continuous)
          .fill(Color.accentColor.opacity(model.dropTargeted ? 0.10 : 0))
      )
      .overlay(
        RoundedRectangle(cornerRadius: KitbagUI.cardRadius, style: .continuous)
          .strokeBorder(
            model.dropTargeted
              ? Color.accentColor
              : (model.items.isEmpty ? Color.secondary.opacity(0.28) : Color.clear),
            style: StrokeStyle(
              lineWidth: model.dropTargeted ? 1.75 : 1,
              dash: model.items.isEmpty ? [5, 4] : []
            )
          )
      )
      .animation(.easeOut(duration: 0.15), value: model.dropTargeted)

      if !model.items.isEmpty,
        !model.convertFormats.isEmpty || model.converting != nil || model.pendingConvert != nil
      {
        ConvertRow(model: model)
      }

      ForEach(model.senders) { sender in
        SenderSlot(sender: sender, model: model)
      }

      if let m = model.message {
        HStack(spacing: 6) {
          Image(systemName: "info.circle.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(m)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
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

  private func compactAction(
    _ symbol: String, label: LocalizedStringKey, help: LocalizedStringKey,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 4) {
        Image(systemName: symbol).font(.system(size: 11, weight: .medium))
        Text(label).font(.caption.weight(.medium))
      }
      .foregroundStyle(.primary)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(
        Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous)
      )
      .hoverHighlight(cornerRadius: 6)
      .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    .buttonStyle(PressableStyle())
    .help(help)
  }

  private var footer: String {
    let n =
      model.items.count == 1
      ? String(localized: "1 item") : String(localized: "\(model.items.count) items")
    return model.missing.isEmpty
      ? n : n + " · " + String(localized: "\(model.missing.count) missing")
  }
}

/// Two-option segmented switch with smooth sliding active indicator.
private struct ModeSwitch: View {
  @Binding var mode: TransferMode
  @Namespace private var ns
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    HStack(spacing: 2) {
      option(.copy, "Copy on drag", "doc.on.doc")
      option(.move, "Move on drag", "arrow.right.circle")
    }
    .padding(3)
    .background(
      scheme == .dark ? Color.white.opacity(0.065) : Color.black.opacity(0.05),
      in: Capsule()
    )
    .overlay(
      Capsule().strokeBorder(
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
        lineWidth: 0.5
      )
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel("When dropped in a folder")
  }

  private func option(_ value: TransferMode, _ title: LocalizedStringKey, _ symbol: String)
    -> some View
  {
    let on = mode == value
    return Button {
      withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
        mode = value
      }
    } label: {
      Label(title, systemImage: symbol)
        .font(.caption.weight(.semibold))
        .foregroundStyle(on ? Color.white : Color.secondary)
        .frame(maxWidth: .infinity, minHeight: 25)
        .background {
          if on {
            Capsule()
              .fill(Color.accentColor)
              .matchedGeometryEffect(id: "shelfMode", in: ns)
          }
        }
        .capsuleHoverHighlight(tint: on ? nil : Color.primary)
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
        Image(nsImage: model.icon(for: item.id, size: 70))
          .resizable()
          .frame(width: 70, height: 70)
          .rotationEffect(.degrees(depth == 0 ? 0 : side * Double(depth) * 7))
          .offset(x: depth == 0 ? 0 : side * Double(depth) * 9, y: Double(depth) * -4)
          .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 104)
    .overlay(alignment: .topTrailing) {
      Text("\(model.items.count)")
        .font(.caption.bold().monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, 7.5)
        .padding(.vertical, 2.5)
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
    let gone = operation.contains(.move) || operation.contains(.delete)
    if gone || (model?.clearAfterDrop == true && !operation.isEmpty) {
      for id in ids { model?.remove(id) }
    }
    ids = []
  }
}

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
  private var targeted: Bool { model.targetedSender == sender.id }

  var body: some View {
    HStack(spacing: 9) {
      sender.icon().frame(width: 22, height: 22)
      VStack(alignment: .leading, spacing: 1) {
        Text(sender.title).font(.callout.weight(.medium))
        HStack(spacing: 4) {
          StatusDot(
            color: power.isBusy ? KitbagUI.warning : (power.isOn ? KitbagUI.success : .secondary),
            active: power.isOn && !power.isBusy,
            size: 5.5
          )
          Text(power.isBusy ? "Working…" : (power.isOn ? "Ready" : "Off"))
            .font(.caption2)
            .foregroundStyle(power.isOn ? KitbagUI.success : .secondary)
        }
      }
      Spacer(minLength: 6)
      if canSend {
        Button {
          model.send(with: sender)
        } label: {
          Label("Send", systemImage: "paperplane.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Color.accentColor, in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .help("Send the shelf with \(sender.title)")
      }
      if power.isBusy { ProgressView().controlSize(.small) }
      Toggle("\(sender.title) service", isOn: Binding(get: { power.isOn }, set: { power.set($0) }))
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(power.isBusy)
    }
    .card(
      padding: 10,
      borderColor: targeted ? Color.accentColor : nil,
      borderWidth: 1.75
    )
    .dropDestination(for: URL.self) { urls, _ in
      model.send(with: sender, urls: urls)
      NotificationCenter.default.post(name: .kitbagFileDropFinished, object: nil)
      return !urls.isEmpty
    } isTargeted: {
      model.targetedSender = $0 ? sender.id : nil
    }
    .animation(.easeOut(duration: 0.16), value: canSend)
  }
}

private struct PlainSenderButton: View {
  let sender: FileSender
  @ObservedObject var model: ShelfModel

  private var targeted: Bool { model.targetedSender == sender.id }

  var body: some View {
    Button {
      model.send(with: sender)
    } label: {
      HStack(spacing: 9) {
        sender.icon().frame(width: 22, height: 22)
        Text("Send with \(sender.title)").font(.callout.weight(.medium))
        Spacer()
        Image(systemName: "paperplane.fill")
          .font(.caption)
          .foregroundStyle(Color.accentColor)
      }
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
    }
    .buttonStyle(PressableStyle())
    .card(
      padding: 10,
      borderColor: targeted ? Color.accentColor : nil,
      borderWidth: 1.75
    )
    .hoverHighlight(cornerRadius: KitbagUI.cardRadius)
    .dropDestination(for: URL.self) { urls, _ in
      model.send(with: sender, urls: urls)
      NotificationCenter.default.post(name: .kitbagFileDropFinished, object: nil)
      return !urls.isEmpty
    } isTargeted: {
      model.targetedSender = $0 ? sender.id : nil
    }
  }
}

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
    .frame(maxWidth: .infinity, alignment: .leading)
    .card(padding: 11)
    .animation(.easeOut(duration: 0.16), value: model.pendingConvert)
  }

  // MARK: Step 1: pick a format

  private var picker: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 5) {
        Image(systemName: "arrow.triangle.2.circlepath")
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundStyle(.secondary)
        SectionEyebrow("Convert & Optimize")
      }
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 6)], spacing: 6) {
        ForEach(model.convertFormats) { f in
          Button {
            model.requestConvert(.format(f))
          } label: {
            Text(f.label)
              .font(.caption.weight(.semibold))
              .foregroundStyle(Color.accentColor)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 6.5)
              .background(
                Color.accentColor.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
              )
              .hoverHighlight(cornerRadius: 8, tint: Color.accentColor)
              .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          .buttonStyle(PressableStyle())
          .help("Convert to \(f.label)")
        }
      }
      if model.canOptimize {
        HStack(spacing: 6) {
          action("Compress", "arrow.down.right.and.arrow.up.left") {
            model.requestConvert(.compress)
          }
          action("Clean Metadata", "eye.slash") { model.requestConvert(.cleanOnly) }
        }
      }
      if model.canMerge {
        action("Combine into One PDF", "doc.on.doc.fill") { model.requestConvert(.mergePDF) }
      }
    }
  }

  private func action(_ title: LocalizedStringKey, _ symbol: String, run: @escaping () -> Void)
    -> some View
  {
    Button(action: run) {
      Label(title, systemImage: symbol)
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6.5)
        .background(
          Color.primary.opacity(0.07),
          in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .hoverHighlight(cornerRadius: 8)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(PressableStyle())
  }

  // MARK: Step 2: what will happen, then where to save

  private func confirm(_ request: ConvertRequest) -> some View {
    let plan = model.plan(for: request)
    let sameFormat = request == .compress || request == .cleanOnly
    let compressing = model.compressEnabled && showsCompress(request)
    let nothingToDo = sameFormat && !model.compressEnabled && !model.cleanEnabled
    return VStack(alignment: .leading, spacing: 9) {
      HStack {
        Text(heading(request)).font(.callout.weight(.semibold)).lineLimit(1)
        Spacer()
        Button("Cancel") { model.cancelRequest() }
          .controlSize(.small)
          .buttonStyle(.borderless)
      }
      SizeComparison(rows: model.estimateRows, estimating: model.estimating)
      if showsCompress(request) {
        Toggle("Compress", isOn: $model.compressEnabled)
          .toggleStyle(.checkbox)
          .font(.callout)
        if compressing {
          Picker("Strength", selection: $model.compressLevel) {
            ForEach(CompressLevel.allCases) { Text($0.label).tag($0) }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
        }
      }
      if sameFormat {
        Toggle("Remove hidden metadata", isOn: $model.cleanEnabled)
          .toggleStyle(.checkbox)
          .font(.callout)
          .help("Camera info, GPS location, and AI details such as prompts and content credentials")
      } else if plan.hasMetadata {
        Toggle("Remove hidden metadata", isOn: $model.stripMetadata)
          .toggleStyle(.checkbox)
          .font(.callout)
          .help("Camera info, GPS location, and AI details such as prompts and content credentials")
      }
      VStack(spacing: 6) {
        HStack(spacing: 6) {
          choice("Save Next to Original", "folder", prominent: true) {
            model.runPending(saveTo: .original)
          }
          choice("Choose Folder…", "folder.badge.plus") { model.chooseFolderAndRun() }
        }
        if sameFormat {
          choice("Replace Originals", "arrow.triangle.2.circlepath") {
            model.runPending(saveTo: .replace)
          }
        }
      }
      .disabled(nothingToDo)
      .opacity(nothingToDo ? 0.45 : 1)
    }
  }

  private func showsCompress(_ r: ConvertRequest) -> Bool {
    if case .format(let f) = r { return f.supportsCompress }
    return r != .mergePDF
  }

  private func progress(_ p: ConvertProgress) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text("Converting to \(p.title)…").font(.callout.weight(.medium))
        Spacer()
        Text("\(p.done) / \(p.total)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
        Button("Cancel") { model.cancelConvert() }
          .controlSize(.mini)
      }
      ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
    }
  }

  private func heading(_ r: ConvertRequest) -> String {
    switch r {
    case .format(let f): return String(localized: "Convert to \(f.label)")
    case .mergePDF: return String(localized: "Combine into one PDF")
    case .compress, .cleanOnly:
      switch (model.compressEnabled, model.cleanEnabled) {
      case (true, true): return String(localized: "Compress & clean metadata")
      case (false, true): return String(localized: "Remove hidden metadata")
      case (true, false): return String(localized: "Compress")
      default: return String(localized: "Choose an action")
      }
    }
  }

  private func choice(
    _ title: LocalizedStringKey, _ symbol: String, prominent: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(title, systemImage: symbol)
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .foregroundStyle(prominent ? Color.white : Color.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
          prominent ? Color.accentColor : Color.primary.opacity(0.08),
          in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .hoverHighlight(cornerRadius: 8, tint: prominent ? .white : nil)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(PressableStyle())
  }
}

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
        if estimating { ProgressView().controlSize(.mini) }
        Text(estimating ? "Estimating output size…" : "Size estimate unavailable")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        Text("\(bytes(before)) → \(bytes(after))")
          .font(.caption.weight(.semibold).monospacedDigit())
        let c = ShelfFormat.change(before, after)
        if !c.text.isEmpty {
          Text(c.text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(c.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(c.color.opacity(0.14), in: Capsule())
        }
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
      ? (String(localized: "\(-pct)% smaller"), KitbagUI.success)
      : (String(localized: "\(pct)% larger"), KitbagUI.warning)
  }
}

private struct ItemList: View {
  @ObservedObject var model: ShelfModel

  var body: some View {
    ScrollView {
      VStack(spacing: 2) {
        ForEach(model.items) { item in
          let missing = model.missing.contains(item.id)
          let est = model.estimateRows.first { $0.id == item.id }
          HStack(spacing: 8) {
            Image(nsImage: model.icon(for: item.id, size: 18))
              .resizable()
              .frame(width: 18, height: 18)
            Text(item.name)
              .font(.caption)
              .lineLimit(1)
              .truncationMode(.middle)
            Spacer(minLength: 6)
            if missing {
              Text("missing").font(.caption2.weight(.medium)).foregroundStyle(KitbagUI.danger)
            } else if let est, let after = est.after {
              Text("\(ShelfFormat.bytes(est.before)) → \(ShelfFormat.bytes(after))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            } else if let size = model.fileSize(for: item.id) {
              Text(ShelfFormat.bytes(size))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            Button {
              model.remove(item.id)
            } label: {
              Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Remove from the shelf")
            .accessibilityLabel("Remove \(item.name)")
          }
          .padding(.horizontal, 6)
          .padding(.vertical, 4)
          .hoverHighlight(cornerRadius: 6)
        }
      }
    }
    .frame(maxHeight: 150)
  }
}
