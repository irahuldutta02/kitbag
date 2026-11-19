import AppKit
import KitbagCore
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
    p.isMovableByWindowBackground = true
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
        case .color:
          Label("Color", systemImage: "eyedropper")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.pink, .primary)
        case .size:
          Label("Measurement", systemImage: "ruler")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.orange, .primary)
        }
        Spacer()
        Button(action: close) {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .capsuleHoverHighlight()
        .accessibilityLabel("Close")
      }
      switch content {
      case .color(let c):
        HStack(alignment: .center, spacing: 12) {
          RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(c.color)
            .frame(width: 58, height: 58)
            .overlay(
              RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.primary.opacity(0.18), lineWidth: 0.75)
            )
            .shadow(color: c.color.opacity(0.28), radius: 4, y: 1)
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
    .padding(13)
    .frame(width: 292)
    .background(WindowDragArea())
    .glass(RoundedRectangle(cornerRadius: 15, style: .continuous))
  }
}

private struct WindowDragArea: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView { DragView() }
  func updateNSView(_ nsView: NSView, context: Context) {}

  private final class DragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
  }
}
