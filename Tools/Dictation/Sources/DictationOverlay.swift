import AppKit
import SwiftUI

/// What the floating pill shows.
@MainActor
final class OverlayState: ObservableObject {
  enum Mode: Equatable { case listening, processing, message(String, error: Bool) }
  @Published var mode: Mode = .listening
  @Published var levels: [Float] = Array(repeating: 0, count: 28)

  func push(_ level: Float) {
    levels.removeFirst()
    levels.append(level)
  }

  func reset() {
    mode = .listening
    levels = Array(repeating: 0, count: levels.count)
  }
}

/// A small pill at the bottom center of the screen that never takes focus.
@MainActor
final class DictationOverlay {
  let state = OverlayState()
  private var panel: NSPanel?

  func show() {
    if panel == nil {
      let host = NSHostingView(rootView: OverlayView(state: state))
      host.frame = NSRect(origin: .zero, size: NSSize(width: 120, height: 40))
      let p = NSPanel(
        contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
        defer: false)
      p.contentView = host
      p.isFloatingPanel = true
      p.level = .statusBar
      p.hidesOnDeactivate = false
      p.isOpaque = false
      p.backgroundColor = .clear
      p.hasShadow = false
      p.ignoresMouseEvents = true
      p.isReleasedWhenClosed = false
      p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
      panel = p
    }
    guard let p = panel else { return }
    var size = NSSize(width: 120, height: 40)  // a small pill; only messages need more room
    if case .message = state.mode { size = NSSize(width: 340, height: 44) }
    p.setContentSize(size)
    let screen = NSScreen.main ?? NSScreen.screens[0]
    let v = screen.visibleFrame
    p.setFrameOrigin(NSPoint(x: v.midX - size.width / 2, y: v.minY + 28))
    p.alphaValue = 0
    p.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { $0.duration = 0.15; p.animator().alphaValue = 1 }
  }

  func hide() {
    guard let p = panel else { return }
    NSAnimationContext.runAnimationGroup(
      { $0.duration = 0.2; p.animator().alphaValue = 0 },
      completionHandler: { MainActor.assumeIsolated { p.orderOut(nil) } })
  }
}

private struct OverlayView: View {
  @ObservedObject var state: OverlayState

  var body: some View {
    HStack(spacing: 10) {
      switch state.mode {
      case .listening:
        Waveform(levels: state.levels)
      case .processing:
        ProgressView().controlSize(.small).tint(.white)
      case .message(let text, let error):
        Image(systemName: error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
          .foregroundStyle(error ? .orange : .green).font(.system(size: 14, weight: .semibold))
        Text(text).font(.callout).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
      }
    }
    .padding(.horizontal, 16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black.opacity(0.9), in: Capsule())
    .overlay(Capsule().strokeBorder(Color.white.opacity(0.14)))
    .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
    .environment(\.colorScheme, .dark)
  }
}

/// A short row of bars that dance with your voice.
private struct Waveform: View {
  let levels: [Float]
  private let bars = 9

  var body: some View {
    HStack(spacing: 3) {
      ForEach(0..<bars, id: \.self) { i in
        let level = levels[levels.count - 1 - i]  // newest on the left, fading to the right
        Capsule().fill(Color.white)
          .frame(width: 3, height: 4 + CGFloat(level) * 18)
      }
    }
    .animation(.linear(duration: 0.06), value: levels)
  }
}
