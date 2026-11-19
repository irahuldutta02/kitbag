import AppKit
import KitbagCore
import SwiftUI

/// What the floating pill shows.
@MainActor
final class OverlayState: ObservableObject {
  enum Mode: Equatable {
    case listening, processing
    case message(String, error: Bool)
  }
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

/// A sleek floating HUD pill at the bottom center of the active screen that never steals focus.
@MainActor
final class DictationOverlay {
  let state = OverlayState()
  private var panel: NSPanel?

  /// Extra transparent margin around the pill so its drop shadow is never clipped.
  private static let shadowInset: CGFloat = 14

  func show() {
    if panel == nil {
      let host = NSHostingView(rootView: OverlayView(state: state))
      host.frame = NSRect(origin: .zero, size: panelSize(for: .listening))
      let p = NSPanel(
        contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
        defer: false)
      p.contentView = host
      p.isFloatingPanel = true
      p.level = .statusBar
      p.hidesOnDeactivate = false
      p.isOpaque = false
      p.backgroundColor = .clear
      p.hasShadow = false  // SwiftUI draws the pill's shadow inside the padded bounds
      p.ignoresMouseEvents = true
      p.isReleasedWhenClosed = false
      p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
      panel = p
    }
    guard let p = panel else { return }
    let size = panelSize(for: state.mode)
    let mouse = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
      ?? NSScreen.main
      ?? NSScreen.screens.first
    guard let v = screen?.visibleFrame else { return }
    let targetFrame = NSRect(
      x: v.midX - size.width / 2,
      y: v.minY + 24 - Self.shadowInset,
      width: size.width,
      height: size.height
    )

    if p.isVisible && p.alphaValue > 0.5 {
      // Already visible: morph frame smoothly without flashing alpha back to 0.
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.18
        ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
        p.animator().setFrame(targetFrame, display: true)
      }
    } else {
      p.setFrame(targetFrame, display: true)
      p.alphaValue = 0
      p.orderFrontRegardless()
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.16
        ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
        p.animator().alphaValue = 1
      }
    }
  }

  func hide() {
    guard let p = panel else { return }
    NSAnimationContext.runAnimationGroup(
      { ctx in
        ctx.duration = 0.2
        p.animator().alphaValue = 0
      },
      completionHandler: { MainActor.assumeIsolated { p.orderOut(nil) } })
  }

  private func panelSize(for mode: OverlayState.Mode) -> NSSize {
    let pill: NSSize =
      switch mode {
      case .listening: NSSize(width: 138, height: 42)
      case .processing: NSSize(width: 146, height: 42)
      case .message: NSSize(width: 388, height: 48)
      }
    return NSSize(
      width: pill.width + Self.shadowInset * 2,
      height: pill.height + Self.shadowInset * 2
    )
  }
}

private struct OverlayView: View {
  @ObservedObject var state: OverlayState

  var body: some View {
    HStack(spacing: 10) {
      switch state.mode {
      case .listening:
        RecordingDot()
        Waveform(levels: state.levels)
      case .processing:
        ProgressView().controlSize(.small).tint(.white)
        Text("Working…")
          .font(.callout.weight(.medium))
          .foregroundStyle(.white.opacity(0.92))
      case .message(let text, let error):
        Image(systemName: error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
          .foregroundStyle(error ? KitbagUI.warning : KitbagUI.success)
          .font(.system(size: 15, weight: .semibold))
        Text(text)
          .font(.callout.weight(.medium))
          .foregroundStyle(.white)
          .lineLimit(2)
          .minimumScaleFactor(0.84)
      }
    }
    .padding(.horizontal, 16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(white: 0.08).opacity(0.90), in: Capsule())
    .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75))
    .shadow(color: .black.opacity(0.32), radius: 10, y: 4)
    .padding(14)
    .environment(\.colorScheme, .dark)
  }
}

/// Subtle pulsing red recording indicator.
private struct RecordingDot: View {
  @StateObject private var pulse = UIBox(false)

  var body: some View {
    ZStack {
      Circle()
        .fill(KitbagUI.danger.opacity(pulse.value ? 0.15 : 0.4))
        .frame(width: pulse.value ? 15 : 10, height: pulse.value ? 15 : 10)
      Circle()
        .fill(KitbagUI.danger)
        .frame(width: 7, height: 7)
    }
    .frame(width: 15, height: 15)
    .onAppear {
      withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
        pulse.value = true
      }
    }
  }
}

/// Symmetric live audio bars that respond smoothly to voice amplitude.
private struct Waveform: View {
  let levels: [Float]
  private let bars = 11
  private let envelope: [CGFloat] = [
    0.42, 0.62, 0.78, 0.90, 0.97, 1.0, 0.97, 0.90, 0.78, 0.62, 0.42,
  ]

  var body: some View {
    HStack(spacing: 3) {
      ForEach(0..<bars, id: \.self) { i in
        let idx = max(0, levels.count - 1 - abs(i - bars / 2) * 2)
        let level = CGFloat(levels[idx]) * envelope[i]
        Capsule()
          .fill(Color.white.opacity(0.92))
          .frame(width: 3, height: 4 + level * 19)
      }
    }
    .animation(.linear(duration: 0.06), value: levels)
  }
}
