import AppKit
import ApplicationServices
import SwiftUI

/// Walks the user through the Accessibility permission the way other apps do: opens the exact
/// Privacy & Security pane and floats a small helper with Kitbag's icon, which can be dragged
/// into the list if the app isn't listed. It closes itself and carries on once access is granted.
@MainActor
public final class AccessibilityGuide {
  private var panel: NSPanel?
  private var timer: Timer?

  public init() {}

  public func begin(onGranted: @escaping () -> Void) {
    close()
    for link in [
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
      "x-apple.systempreferences:com.apple.preference.security",
    ] {
      if let url = URL(string: link), NSWorkspace.shared.open(url) { break }
    }
    showPanel()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard AXIsProcessTrusted() else { return }
        self?.close()
        onGranted()
      }
    }
  }

  public func close() {
    timer?.invalidate()
    timer = nil
    panel?.orderOut(nil)
    panel?.contentView = nil
    panel = nil
  }

  private func showPanel() {
    let host = NSHostingView(rootView: GuideView(done: { [weak self] in self?.close() }))
    let size = host.fittingSize
    let p = NSPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    p.contentView = host
    p.isFloatingPanel = true
    p.level = .floating
    p.hidesOnDeactivate = false
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hasShadow = true
    p.isReleasedWhenClosed = false
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    if let v = NSScreen.main?.visibleFrame {
      p.setFrameOrigin(NSPoint(x: v.midX - size.width / 2, y: v.minY + 24))
    }
    p.orderFrontRegardless()
    panel = p
  }
}

private struct GuideView: View {
  let done: () -> Void

  var body: some View {
    HStack(spacing: 14) {
      Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundleURL.path))
        .resizable().frame(width: 44, height: 44)
        .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
        .help("Drag into the Accessibility list")
      VStack(alignment: .leading, spacing: 3) {
        Text("Allow Kitbag to control the menu bar").font(.headline)
        Text(
          "Turn Kitbag on in the Accessibility list. If it isn't listed, drag this icon into it."
        )
        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      Button("Done", action: done)
    }
    .padding(14)
    .frame(width: 520)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.15)))
  }
}
