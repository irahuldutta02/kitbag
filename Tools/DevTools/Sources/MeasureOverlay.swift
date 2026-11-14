import AppKit

/// Full-screen, see-through overlay (one window per display) for dragging out a rectangle.
@MainActor
final class MeasureOverlay {
  private var windows: [NSWindow] = []
  private var completion: ((CGSize?, CGFloat) -> Void)?

  func begin(completion: @escaping (CGSize?, CGFloat) -> Void) {
    self.completion = completion
    for screen in NSScreen.screens {
      let w = OverlayWindow(
        contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
      w.level = .screenSaver
      w.isOpaque = false
      w.backgroundColor = .clear
      w.hasShadow = false
      w.isReleasedWhenClosed = false
      w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      let v = MeasureView(frame: NSRect(origin: .zero, size: screen.frame.size))
      v.onFinish = { [weak self] size, scale in self?.finish(size, scale) }
      w.contentView = v
      w.makeKeyAndOrderFront(nil)
      w.makeFirstResponder(v)
      windows.append(w)
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  func cancel() { finish(nil, 1) }

  private func finish(_ size: CGSize?, _ scale: CGFloat) {
    for w in windows {
      w.orderOut(nil)
      w.contentView = nil
    }
    windows = []
    let c = completion
    completion = nil
    c?(size, scale)
  }
}

private final class OverlayWindow: NSWindow {
  override var canBecomeKey: Bool { true }
}

private final class MeasureView: NSView {
  var onFinish: ((CGSize?, CGFloat) -> Void)?
  private var start: NSPoint?
  private var current: NSPoint?

  override var acceptsFirstResponder: Bool { true }
  override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

  private var selection: NSRect? {
    guard let a = start, let b = current else { return nil }
    return NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
  }

  override func mouseDown(with event: NSEvent) {
    start = convert(event.locationInWindow, from: nil)
    current = start
    needsDisplay = true
  }

  override func mouseDragged(with event: NSEvent) {
    current = convert(event.locationInWindow, from: nil)
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    let scale = window?.backingScaleFactor ?? 1
    if let r = selection, r.width >= 1, r.height >= 1 {
      onFinish?(r.size, scale)
    } else {
      onFinish?(nil, scale)
    }
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 { onFinish?(nil, 1) }  // Esc
  }

  override func draw(_ dirtyRect: NSRect) {
    // A faint dim also makes the window catch mouse events.
    NSColor.black.withAlphaComponent(0.15).setFill()
    bounds.fill()
    guard let r = selection else { return }
    NSColor.clear.setFill()
    r.fill(using: .copy)
    NSColor.controlAccentColor.setStroke()
    let path = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5))
    path.lineWidth = 1.5
    path.stroke()

    let scale = window?.backingScaleFactor ?? 1
    let m = Measurement(points: r.size, scale: scale)
    let text = NSAttributedString(
      string: "\(m.pointsText)  ·  \(m.pixelsText)",
      attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white,
      ])
    let size = text.size()
    var box = NSRect(
      x: r.maxX - size.width - 16, y: r.minY - size.height - 14, width: size.width + 12,
      height: size.height + 6)
    if box.minY < 4 { box.origin.y = r.maxY + 8 }  // no room below: put it above
    box.origin.x = min(max(box.origin.x, 4), bounds.width - box.width - 4)
    NSColor.black.withAlphaComponent(0.8).setFill()
    NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
    text.draw(at: NSPoint(x: box.minX + 6, y: box.minY + 3))
  }
}
