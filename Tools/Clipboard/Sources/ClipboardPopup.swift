import AppKit
import Carbon.HIToolbox
import KitbagCore
import SwiftUI

/// What the pop-up shows right now: the search text and which row is selected.
@MainActor
final class PopupState: ObservableObject {
  @Published var query = "" { didSet { if query != oldValue { selection = 0 } } }
  @Published var selection = 0
  /// Bumped every time the pop-up opens, so the list jumps back to the top.
  @Published var opened = 0
}

/// A panel that takes the keyboard without making Kitbag the active app, so the app you were
/// typing in stays in front and receives the paste.
private final class KeyPanel: NSPanel {
  var onKey: ((NSEvent) -> Void)?
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
  override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown { onKey?(event) } else { super.sendEvent(event) }
  }
}

/// The history pop-up that opens at the cursor. It is built once and reused, so it shows instantly.
@MainActor
final class ClipboardPopup {
  static let width: CGFloat = 400
  static let maxHeight: CGFloat = 440

  private unowned let model: ClipboardModel
  private let state = PopupState()
  private var panel: KeyPanel?
  private var clickMonitor: Any?
  private var resignObserver: NSObjectProtocol?
  /// What the pop-up hangs from while it is open: the text cursor, or the mouse pointer.
  private var anchor = NSRect.zero

  init(model: ClipboardModel) { self.model = model }

  var isShown: Bool { panel?.isVisible ?? false }

  func toggle() { isShown ? close() : show() }

  func show() {
    let p = panel ?? makePanel()
    panel = p
    state.query = ""
    state.selection = 0
    state.opened += 1
    anchor = CaretLocator.caretRect() ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
    place()
    p.makeKeyAndOrderFront(nil)
    guard clickMonitor == nil else { return }
    clickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) {
      [weak self] _ in MainActor.assumeIsolated { self?.close() }
    }
    resignObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didResignKeyNotification, object: p, queue: .main
    ) { [weak self] _ in MainActor.assumeIsolated { self?.close() } }
  }

  func close() {
    if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    clickMonitor = nil
    if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    resignObserver = nil
    panel?.orderOut(nil)
  }

  private func place() {
    guard let p = panel else { return }
    let size = NSSize(width: Self.width, height: Self.height(for: model.filtered(state.query)))
    let frame = Self.frame(
      anchor: anchor, size: size, screens: NSScreen.screens.map(\.visibleFrame))
    if frame != p.frame { p.setFrame(frame, display: true) }
  }

  static func height(for items: [ClipItem]) -> CGFloat {
    let chrome: CGFloat = 42 + 1 + 1 + 32  // search row, two dividers, footer
    guard !items.isEmpty else { return chrome + 114 }
    let rows = items.prefix(20).reduce(CGFloat(14)) { $0 + ($1.kind == .image ? 48 : 32) }
    return min(maxHeight, chrome + rows)
  }

  static func frame(anchor: NSRect, size: NSSize, screens: [NSRect]) -> NSRect {
    let probe = NSPoint(x: anchor.minX, y: anchor.midY)
    guard
      let v = screens.first(where: { $0.insetBy(dx: -1, dy: -40).contains(probe) }) ?? screens.first
    else {
      return NSRect(origin: anchor.origin, size: size)
    }
    let gap: CGFloat = 6
    let margin: CGFloat = 8
    var o = NSPoint(x: anchor.minX, y: anchor.minY - gap - size.height)
    if o.y < v.minY + margin, anchor.maxY + gap + size.height <= v.maxY - margin {
      o.y = anchor.maxY + gap
    }
    o.x = max(v.minX + margin, min(o.x, v.maxX - size.width - margin))
    o.y = max(v.minY + margin, min(o.y, v.maxY - size.height - margin))
    return NSRect(origin: o, size: size)
  }

  private func makePanel() -> KeyPanel {
    let frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.maxHeight)
    let p = KeyPanel(
      contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    let blur = NSVisualEffectView(frame: frame)
    blur.material = .popover
    blur.blendingMode = .behindWindow
    blur.state = .active
    blur.wantsLayer = true
    blur.layer?.cornerRadius = 14
    blur.layer?.cornerCurve = .continuous
    blur.layer?.masksToBounds = true
    let host = NSHostingView(
      rootView: PopupView(
        model: model, state: state,
        choose: { [weak self] item, plain in self?.choose(item, plain: plain) }))
    host.frame = frame
    host.autoresizingMask = [.width, .height]
    blur.addSubview(host)
    p.contentView = blur
    p.isFloatingPanel = true
    p.level = .popUpMenu
    p.hidesOnDeactivate = false
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hasShadow = true
    p.isReleasedWhenClosed = false
    p.animationBehavior = .none
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    p.onKey = { [weak self] in self?.key($0) }
    return p
  }

  private func choose(_ item: ClipItem, plain: Bool) {
    close()
    model.paste(item, plainText: plain)
  }

  // MARK: Keyboard

  private func key(_ e: NSEvent) {
    handle(e)
    if isShown { place() }
  }

  private func handle(_ e: NSEvent) {
    let items = model.filtered(state.query)
    let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
    let current = items.indices.contains(state.selection) ? items[state.selection] : nil
    func move(_ by: Int) {
      guard !items.isEmpty else { return }
      state.selection = max(0, min(items.count - 1, state.selection + by))
    }

    switch Int(e.keyCode) {
    case kVK_Escape:
      if state.query.isEmpty { close() } else { state.query = "" }
    case kVK_DownArrow: mods.contains(.command) ? move(items.count) : move(1)
    case kVK_UpArrow: mods.contains(.command) ? move(-items.count) : move(-1)
    case kVK_PageDown: move(8)
    case kVK_PageUp: move(-8)
    case kVK_Home: move(-items.count)
    case kVK_End: move(items.count)
    case kVK_Tab: move(mods.contains(.shift) ? -1 : 1)
    case kVK_Return, kVK_ANSI_KeypadEnter:
      if let current { choose(current, plain: mods.contains(.option) || mods.contains(.shift)) }
    case kVK_Delete, kVK_ForwardDelete:
      if mods.contains(.command) {
        if let current {
          model.delete(current.id)
          state.selection = max(0, min(state.selection, items.count - 2))
        }
      } else if !state.query.isEmpty {
        state.query.removeLast()
      }
    default:
      let typed = e.charactersIgnoringModifiers ?? ""
      if mods == .command {
        if let n = Int(typed), (1...9).contains(n) {
          if items.indices.contains(n - 1) { choose(items[n - 1], plain: false) }
        } else if typed == "p", let current {
          model.togglePin(current.id)
          state.selection = model.filtered(state.query).firstIndex { $0.id == current.id } ?? 0
        } else if typed == "c", let current {
          model.copy(current)
          close()
        }
      } else if mods == .control, typed == "n" {
        move(1)
      } else if mods == .control, typed == "p" {
        move(-1)
      } else if mods.subtracting(.shift).isEmpty, let chars = e.characters,
        !chars.isEmpty,
        chars.unicodeScalars.allSatisfy({
          $0.value >= 0x20 && !(0xF700...0xF8FF).contains($0.value)
        })
      {
        state.query += chars
      }
    }
  }
}

// MARK: Views

private struct PopupView: View {
  @ObservedObject var model: ClipboardModel
  @ObservedObject var state: PopupState
  let choose: (ClipItem, Bool) -> Void
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let items = model.filtered(state.query)
    VStack(spacing: 0) {
      // Search header
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(state.query.isEmpty ? Color.secondary : Color.accentColor)
        if state.query.isEmpty {
          Text("Type to search clipboard…")
            .font(.callout)
            .foregroundStyle(.tertiary)
        } else {
          Text(state.query)
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .truncationMode(.head)
        }
        Spacer(minLength: 4)
        if model.paused {
          HStack(spacing: 4) {
            StatusDot(color: KitbagUI.warning, size: 5.5)
            Text("Paused").font(.caption2.weight(.semibold)).foregroundStyle(KitbagUI.warning)
          }
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(KitbagUI.warning.opacity(0.14), in: Capsule())
        }
        Text("\(items.count)")
          .font(.caption2.weight(.semibold).monospacedDigit())
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6.5)
          .padding(.vertical, 2)
          .background(Color.primary.opacity(0.07), in: Capsule())
      }
      .padding(.horizontal, 14)
      .frame(height: 42)

      Divider().opacity(0.55)

      if items.isEmpty {
        VStack(spacing: 6) {
          Image(systemName: state.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
            .font(.system(size: 24, weight: .light))
            .foregroundStyle(.tertiary)
          Text(state.query.isEmpty ? "Nothing copied yet" : "No matches")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(spacing: 2) {
              ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                ClipRow(
                  model: model, item: item, selected: index == state.selection,
                  badge: index < 9 ? "⌘\(index + 1)" : nil
                )
                .contentShape(Rectangle())
                .onHover { hovering in
                  if hovering && state.selection != index {
                    state.selection = index
                  }
                }
                .onTapGesture { choose(item, false) }
                .id(item.id)
              }
            }
            .padding(6)
          }
          .onChange(of: state.selection) { _, new in
            if items.indices.contains(new) { proxy.scrollTo(items[new].id) }
          }
          .onChange(of: state.opened) { _, _ in
            if let first = items.first { proxy.scrollTo(first.id, anchor: .top) }
          }
        }
      }

      Divider().opacity(0.55)

      // Footer with source info + crisp keycap hints
      HStack(spacing: 8) {
        if items.indices.contains(state.selection) {
          Text(Self.info(items[state.selection]))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        Spacer(minLength: 4)
        HStack(spacing: 6) {
          hint("↵", "Paste")
          hint("⌥↵", "Plain")
          hint("⌘P", "Pin")
          hint("⌘⌫", "Del")
        }
        .fixedSize()
        .layoutPriority(1)
      }
      .padding(.horizontal, 12)
      .frame(height: 32)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(
          scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.11),
          lineWidth: 0.75
        )
    )
  }

  private func hint(_ key: String, _ label: LocalizedStringKey) -> some View {
    HStack(spacing: 3) {
      KeycapBadge(key)
      Text(label).font(.caption2).foregroundStyle(.secondary)
    }
  }

  /// "Safari · 5m ago" for the selected item.
  static func info(_ item: ClipItem) -> String {
    let ago = RelativeDateTimeFormatter()
    ago.unitsStyle = .abbreviated
    let when =
      -item.date.timeIntervalSinceNow < 5
      ? "now" : ago.localizedString(for: item.date, relativeTo: Date())
    return [item.app, when].compactMap { $0 }.joined(separator: " · ")
  }
}

/// One history row, shared by the pop-up and the menu tab.
struct ClipRow: View {
  let model: ClipboardModel
  let item: ClipItem
  var selected = false
  var badge: String?

  var body: some View {
    HStack(spacing: 9) {
      if item.kind == .image {
        ClipThumb(model: model, item: item)
      } else {
        Image(systemName: item.symbol)
          .font(.system(size: 11.5, weight: .medium))
          .foregroundStyle(selected ? Color.white.opacity(0.9) : Color.secondary)
          .frame(width: 22, height: 22)
          .background(
            selected ? Color.white.opacity(0.16) : Color.primary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
          )
      }
      Text(item.title)
        .font(.callout)
        .lineLimit(1)
        .truncationMode(.tail)
        .foregroundStyle(selected ? Color.white : Color.primary)
      Spacer(minLength: 4)
      if item.pinned {
        Image(systemName: "pin.fill")
          .font(.system(size: 9.5))
          .foregroundStyle(selected ? Color.white.opacity(0.9) : KitbagUI.warning)
      }
      if let badge {
        Text(badge)
          .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
          .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary.opacity(0.75))
      }
    }
    .padding(.horizontal, 8)
    .frame(height: item.kind == .image ? 46 : 30)
    .background {
      if selected {
        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

@MainActor private final class ThumbBox: ObservableObject {
  @Published var image: NSImage?
}

private struct ClipThumb: View {
  let model: ClipboardModel
  let item: ClipItem
  @StateObject private var box = ThumbBox()

  var body: some View {
    Group {
      if let image = box.image {
        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
      } else {
        Image(systemName: "photo").foregroundStyle(.secondary)
      }
    }
    .frame(width: 56, height: 36)
    .background(
      Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous)
    )
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
    )
    .task(id: item.id) { box.image = await model.thumbnail(item) }
  }
}
