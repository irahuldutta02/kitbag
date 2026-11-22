import AppKit
import SwiftUI

/// Lightweight ObservableObject box for view-local state (compatible with Command Line Tools
/// without SwiftUI's `@State` macro plugin).
@MainActor
public final class UIBox<Value>: ObservableObject {
  @Published public var value: Value
  public init(_ value: Value) { self.value = value }
}

/// Shared design tokens and semantic colors for Kitbag's native macOS UI.
public enum KitbagUI {
  public static let cardRadius: CGFloat = 14
  public static let innerRadius: CGFloat = 9
  public static let smallRadius: CGFloat = 7

  /// Crisp semantic colors that keep their vibrancy on translucent macOS surfaces.
  public static let success = Color(red: 0.16, green: 0.72, blue: 0.37)
  public static let warning = Color(red: 0.96, green: 0.58, blue: 0.11)
  public static let danger = Color(red: 0.94, green: 0.26, blue: 0.24)
}

/// Liquid Glass for true floating chrome (sidebars, floating panels, floating buttons).
/// Never adds a dark wash over light mode; lets macOS handle lensing and accessibility.
private struct GlassBackground<S: InsettableShape>: ViewModifier {
  let shape: S
  let interactive: Bool
  @ObservedObject private var style = GlassStyle.shared
  @Environment(\.colorScheme) private var scheme

  func body(content: Content) -> some View {
    let t = style.transparency
    if #available(macOS 26.0, *) {
      let base: Glass = t > 0.72 ? .clear : .regular
      let glass: Glass = interactive ? base.interactive() : base
      content
        .glassEffect(glass, in: shape)
    } else {
      content
        .background(.regularMaterial.opacity(max(0.35, 1 - t * 0.55)), in: shape)
        .overlay(
          shape.strokeBorder(
            scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08),
            lineWidth: 0.5
          )
        )
    }
  }
}

/// Clean inner content surface for cards inside popovers and windows (avoids stacking glass on glass).
private struct SurfaceCard: ViewModifier {
  let padding: CGFloat
  let cornerRadius: CGFloat
  let borderColor: Color?
  let borderWidth: CGFloat
  @ObservedObject private var style = GlassStyle.shared
  @Environment(\.colorScheme) private var scheme

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    let t = style.transparency
    // Adapt cleanly to both Light and Dark mode without muddy black tinting.
    let fill: Color =
      scheme == .dark
      ? Color.white.opacity(0.045 + (1 - t) * 0.045)
      : Color.white.opacity(0.45 + (1 - t) * 0.32)
    let defaultStroke: Color =
      scheme == .dark ? Color.white.opacity(0.095) : Color.black.opacity(0.075)

    content
      .padding(padding)
      .background(fill, in: shape)
      .overlay(
        shape.strokeBorder(
          borderColor ?? defaultStroke,
          lineWidth: borderColor != nil ? borderWidth : 0.5
        )
      )
  }
}

/// Subtle pointer hover highlight shared by rows, tiles, and icon buttons.
private struct HoverHighlight: ViewModifier {
  let cornerRadius: CGFloat
  let isCapsule: Bool
  let tint: Color?
  @StateObject private var hover = UIBox(false)
  @Environment(\.colorScheme) private var scheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    let hovering = hover.value
    let fill: Color =
      tint?.opacity(hovering ? 0.14 : 0)
      ?? (scheme == .dark
        ? Color.white.opacity(hovering ? 0.09 : 0)
        : Color.black.opacity(hovering ? 0.055 : 0))

    content
      .background {
        if isCapsule {
          Capsule().fill(fill)
        } else {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(fill)
        }
      }
      .onHover { hover.value = $0 }
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
  }
}

/// Press feedback shared by every tappable control: a quick dim, nothing moves.
public struct PressableStyle: ButtonStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.7 : 1)  // plain press feedback, no bounce
  }
}

/// Consistent inset search bar used across Clipboard, Authenticator, and System Monitor.
public struct SearchFieldBar: View {
  let placeholder: LocalizedStringKey
  let plainPlaceholder: String?
  @Binding var text: String
  let autoFocus: Bool
  let onSubmit: (() -> Void)?
  @Environment(\.colorScheme) private var scheme

  public init(
    _ placeholder: LocalizedStringKey,
    text: Binding<String>,
    autoFocus: Bool = false,
    plainPlaceholder: String? = nil,
    onSubmit: (() -> Void)? = nil
  ) {
    self.placeholder = placeholder
    self.plainPlaceholder = plainPlaceholder
    self._text = text
    self.autoFocus = autoFocus
    self.onSubmit = onSubmit
  }

  public var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
      if autoFocus {
        AutoFocusSearchField(
          placeholder: plainPlaceholder ?? "",
          text: $text,
          onSubmit: onSubmit
        )
      } else {
        TextField(placeholder, text: $text)
          .textFieldStyle(.plain)
          .font(.callout)
          .onSubmit { onSubmit?() }
      }
      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Clear search")
        .accessibilityLabel("Clear search")
      }
    }
    .padding(.horizontal, 9)
    .frame(height: 30)
    .background(
      scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05),
      in: RoundedRectangle(cornerRadius: KitbagUI.innerRadius, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: KitbagUI.innerRadius, style: .continuous)
        .strokeBorder(
          scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
          lineWidth: 0.5
        )
    )
  }
}

/// AppKit-backed text field that reliably takes keyboard focus inside an NSPopover as soon as it
/// appears and selects any existing text so the user can type immediately.
private struct AutoFocusSearchField: NSViewRepresentable {
  let placeholder: String
  @Binding var text: String
  let onSubmit: (() -> Void)?

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> FocusTextField {
    let tf = FocusTextField()
    tf.isBordered = false
    tf.drawsBackground = false
    tf.focusRingType = .none
    tf.font = .systemFont(ofSize: NSFont.systemFontSize(for: .regular) - 1)
    tf.placeholderString = placeholder
    tf.lineBreakMode = .byTruncatingHead
    tf.usesSingleLineMode = true
    tf.cell?.isScrollable = true
    tf.delegate = context.coordinator
    tf.stringValue = text
    return tf
  }

  func updateNSView(_ tf: FocusTextField, context: Context) {
    context.coordinator.parent = self
    if tf.stringValue != text {
      tf.stringValue = text
    }
    if tf.placeholderString != placeholder {
      tf.placeholderString = placeholder
    }
  }

  final class FocusTextField: NSTextField {
    private var didAutoFocus = false
    private var keyObserver: NSObjectProtocol?

    deinit {
      if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let keyObserver {
        NotificationCenter.default.removeObserver(keyObserver)
        self.keyObserver = nil
      }
      guard let window else {
        didAutoFocus = false
        return
      }
      keyObserver = NotificationCenter.default.addObserver(
        forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self, !self.didAutoFocus else { return }
          self.focusNow()
        }
      }
      focusSoon()
    }

    func focusSoon() {
      DispatchQueue.main.async { [weak self] in
        self?.focusNow()
      }
      // Retry shortly after in case the popover/panel finishes ordering front on the next frame.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
        guard let self, !self.didAutoFocus else { return }
        self.focusNow()
      }
    }

    private func focusNow() {
      guard let window else { return }
      if !window.isKeyWindow { window.makeKey() }
      if window.firstResponder !== currentEditor() {
        if window.makeFirstResponder(self) {
          currentEditor()?.selectAll(nil)
          didAutoFocus = true
        }
      } else {
        didAutoFocus = true
      }
    }
  }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: AutoFocusSearchField
    init(_ parent: AutoFocusSearchField) { self.parent = parent }

    func controlTextDidChange(_ obj: Notification) {
      guard let tf = obj.object as? NSTextField else { return }
      if parent.text != tf.stringValue {
        parent.text = tf.stringValue
      }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
      -> Bool
    {
      if commandSelector == #selector(NSResponder.insertNewline(_:)) {
        parent.onSubmit?()
        return true
      }
      if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
        if !parent.text.isEmpty {
          parent.text = ""
          return true
        }
        NotificationCenter.default.post(name: .kitbagCloseMenu, object: nil)
        return true
      }
      return false
    }
  }
}

/// Uppercase tracked micro-heading used inside cards and grouped sections.
public struct SectionEyebrow: View {
  let title: LocalizedStringKey
  public init(_ title: LocalizedStringKey) { self.title = title }

  public var body: some View {
    Text(title)
      .font(.system(size: 10.5, weight: .semibold))
      .foregroundStyle(.secondary)
      .textCase(.uppercase)
      .tracking(0.6)
  }
}

/// Crisp status dot with an optional soft halo when active.
public struct StatusDot: View {
  let color: Color
  var active = false
  var size: CGFloat = 6.5

  public init(color: Color, active: Bool = false, size: CGFloat = 6.5) {
    self.color = color
    self.active = active
    self.size = size
  }

  public var body: some View {
    ZStack {
      if active {
        Circle()
          .fill(color.opacity(0.28))
          .frame(width: size + 5, height: size + 5)
      }
      Circle()
        .fill(color)
        .frame(width: size, height: size)
    }
    .frame(width: size + 5, height: size + 5)
  }
}

/// Compact keycap badge for shortcuts like ⌥⌘V, ↵, ⌘1.
public struct KeycapBadge: View {
  let text: String
  @Environment(\.colorScheme) private var scheme

  public init(_ text: String) { self.text = text }

  public var body: some View {
    Text(text)
      .font(.system(size: 10.5, weight: .medium, design: .rounded))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 5.5)
      .padding(.vertical, 2)
      .background(
        scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06),
        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .strokeBorder(
            scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08),
            lineWidth: 0.5
          )
      )
  }
}

extension View {
  /// Liquid Glass (on macOS 26+) or translucent material for floating chrome.
  public func glass<S: InsettableShape>(_ shape: S, interactive: Bool = false) -> some View {
    modifier(GlassBackground(shape: shape, interactive: interactive))
  }

  /// Clean, adaptive content surface shared by all popover tools.
  public func card(
    padding: CGFloat = 11,
    cornerRadius: CGFloat = KitbagUI.cardRadius,
    borderColor: Color? = nil,
    borderWidth: CGFloat = 1.5
  ) -> some View {
    modifier(
      SurfaceCard(
        padding: padding,
        cornerRadius: cornerRadius,
        borderColor: borderColor,
        borderWidth: borderWidth
      )
    )
  }

  /// Subtle hover background highlight for interactive rows and tiles.
  public func hoverHighlight(
    cornerRadius: CGFloat = KitbagUI.smallRadius,
    tint: Color? = nil
  ) -> some View {
    modifier(HoverHighlight(cornerRadius: cornerRadius, isCapsule: false, tint: tint))
  }

  /// Subtle hover highlight clipped to a capsule.
  public func capsuleHoverHighlight(tint: Color? = nil) -> some View {
    modifier(HoverHighlight(cornerRadius: 0, isCapsule: true, tint: tint))
  }

  public func pressable() -> some View { buttonStyle(PressableStyle()) }
}
