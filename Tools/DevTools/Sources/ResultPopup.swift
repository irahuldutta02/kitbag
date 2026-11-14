import AppKit
import SwiftUI

enum PopupContent {
  case color(ColorValue)
  case size(Measurement)
}

/// Small floating cards shown next to the cursor when a pick or measurement finishes.
/// Each stays until its close button is pressed and can be dragged anywhere.
@MainActor
final class ResultPopup {
  private var panels: [NSPanel] = []

  func show(_ content: PopupContent, copy: @escaping (String) -> Void) {
    var panel: NSPanel?
    let host = NSHostingView(
      rootView: ResultPopupView(
        content: content, copy: copy,
        close: { [weak self] in
          if let p = panel { self?.close(p) }
        }))
    let size = host.fittingSize
    host.frame = NSRect(origin: .zero, size: size)

    let p = NSPanel(
      contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    p.isFloatingPanel = true
    p.level = .floating
    p.hidesOnDeactivate = false
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hasShadow = true
    p.isMovableByWindowBackground = true  // drag it by any non-button area
    p.isReleasedWhenClosed = false
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    p.contentView = host
    panel = p

    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    var origin = NSPoint(x: mouse.x + 16, y: mouse.y - size.height - 16)
    if let v = screen?.visibleFrame {
      origin.x = min(max(origin.x, v.minX + 8), v.maxX - size.width - 8)
      origin.y = min(max(origin.y, v.minY + 8), v.maxY - size.height - 8)
    }
    p.setFrameOrigin(origin)
    p.orderFrontRegardless()
    panels.append(p)
  }

  private func close(_ p: NSPanel) {
    p.orderOut(nil)
    p.contentView = nil
    panels.removeAll { $0 === p }
  }

  /// Closes every popup (used when the tool is turned off).
  func close() {
    for p in panels {
      p.orderOut(nil)
      p.contentView = nil
    }
    panels = []
  }
}

private struct ResultPopupView: View {
  let content: PopupContent
  let copy: (String) -> Void
  let close: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        switch content {
        case .color: Label("Color", systemImage: "eyedropper").font(.subheadline.bold())
        case .size: Label("Size", systemImage: "ruler").font(.subheadline.bold())
        }
        Spacer()
        Button(action: close) { Image(systemName: "xmark.circle.fill") }
          .buttonStyle(.borderless).foregroundStyle(.secondary)
          .accessibilityLabel("Close")
      }
      switch content {
      case .color(let c):
        HStack(alignment: .top, spacing: 12) {
          RoundedRectangle(cornerRadius: 10).fill(c.color).frame(width: 56, height: 56)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.2)))
          VStack(spacing: 4) {
            CopyRow(title: "HEX", value: c.hex, copy: copy)
            CopyRow(title: "RGB", value: c.rgb, copy: copy)
            CopyRow(title: "HSL", value: c.hsl, copy: copy)
          }
        }
      case .size(let m):
        VStack(spacing: 4) {
          CopyRow(title: "Points", value: m.pointsText, copy: copy)
          CopyRow(title: "Pixels", value: m.pixelsText, copy: copy)
        }
      }
    }
    .padding(12)
    .frame(width: 280)
    .background(WindowDragArea())  // behind the content, in front of the material
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.15)))
  }
}

/// Lets the user drag the window by pressing anywhere on the card that isn't a control.
private struct WindowDragArea: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView { DragView() }
  func updateNSView(_ nsView: NSView, context: Context) {}

  private final class DragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
  }
}
