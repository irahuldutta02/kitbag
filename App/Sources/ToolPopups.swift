import AppKit
import Combine
import KitbagCore
import SwiftUI

/// Opens a tool's view as its own small window. It starts pinned (above every other window, on all
/// Spaces); the pin button in its header unpins it, after which it closes when you click elsewhere.
@MainActor
final class ToolPopups: NSObject, NSWindowDelegate {
  private let manager: ToolManager
  private var panels: [String: PopupPanel] = [:]

  init(manager: ToolManager) { self.manager = manager }

  func open(_ id: String) {
    if let existing = panels[id] {
      existing.makeKeyAndOrderFront(nil)
      return
    }
    guard let d = manager.descriptors.first(where: { $0.id == id }), d.popsOut else { return }
    if manager.active[id] == nil { manager.setEnabled(id, true) }  // opening an app switches it on
    guard let tool = manager.active[id] else { return }

    tool.menuVisibilityChanged(true)
    let pin = PinState()
    // Measure the content on its own (no window, so no title bar inset), then freeze the size.
    let hostView = NSHostingView(
      rootView: PopupChrome(descriptor: d, content: tool.makeMenuView(), pin: pin, width: Self.width(id)))
    let size = hostView.fittingSize
    hostView.sizingOptions = []
    let panel = PopupPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered, defer: false)
    panel.toolID = id
    panel.pin = pin
    let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
    glass.material = .hudWindow
    glass.blendingMode = .behindWindow
    glass.state = .active
    hostView.frame = glass.bounds
    hostView.autoresizingMask = [.width, .height]
    glass.addSubview(hostView)
    panel.contentView = glass
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    panel.standardWindowButton(.zoomButton)?.isHidden = true
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.isMovableByWindowBackground = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isFloatingPanel = true
    panel.delegate = self
    panel.observePin()

    panel.setContentSize(size)
    if let v = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
      let n = CGFloat(panels.count)
      panel.setFrameTopLeftPoint(
        NSPoint(x: v.maxX - panel.frame.width - 24 - 30 * n, y: v.maxY - 16 - 30 * n))
    }
    panels[id] = panel
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
  }

  private static func width(_ id: String) -> CGFloat {
    ["dictation": 380, "calculator": 280, "speedtest": 340, "mirror": 328, "portmanager": 400][id] ?? 320
  }

  func windowDidResignKey(_ notification: Notification) {
    guard let panel = notification.object as? PopupPanel, panel.pin?.pinned == false else { return }
    panel.close()
  }

  func windowWillClose(_ notification: Notification) {
    guard let panel = notification.object as? PopupPanel, let id = panel.toolID else { return }
    panels[id] = nil
    panel.contentView = nil  // lets the tool see its view go away (Mirror switches the camera off)
    manager.active[id]?.menuVisibilityChanged(false)
  }
}

@MainActor final class PinState: ObservableObject {
  @Published var pinned = true
}

/// Header (icon, name, pin) above the tool's own view, under the window's close button.
private struct PopupChrome: View {
  let descriptor: ToolDescriptor
  let content: AnyView
  @ObservedObject var pin: PinState
  let width: CGFloat

  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        Text(descriptor.name)  // centered title, like a native window; no icon
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.primary.opacity(0.9))
        HStack(spacing: 8) {
          Spacer()
        Button {
          withAnimation(.easeOut(duration: 0.15)) { pin.pinned.toggle() }
        } label: {
          HStack(spacing: 4) {
            Image(systemName: pin.pinned ? "pin.fill" : "pin")
              .font(.system(size: 10, weight: .semibold))
              .rotationEffect(.degrees(pin.pinned ? 0 : 45))
            Text(pin.pinned ? "Pinned" : "Pin")
              .font(.system(size: 11, weight: .medium))
          }
          .foregroundStyle(pin.pinned ? Color.accentColor : Color.secondary)
          .padding(.horizontal, 9)
          .frame(height: 22)
          .background(
            pin.pinned ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.07), in: Capsule()
          )
          .overlay(
            Capsule().strokeBorder(
              pin.pinned ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08),
              lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(pin.pinned ? "Pinned on top. Click to unpin" : "Pin on top")
        }
      }
      .padding(.horizontal, 12)
      .frame(height: 30)  // same row as the close button

      content
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .padding(.top, 8)
    }
    .frame(width: width, alignment: .top)
    .overlay(alignment: .top) {  // hairline under the header
      Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5).offset(y: 30)
    }
    .ignoresSafeArea(.container, edges: .top)  // header sits in the title bar row
  }
}

final class PopupPanel: NSPanel {
  var toolID: String?
  var pin: PinState?
  private var sub: AnyCancellable?

  override var canBecomeKey: Bool { true }

  @MainActor func observePin() {
    guard let pin else { return }
    sub = pin.$pinned.sink { [weak self] on in self?.level = on ? .floating : .normal }
  }
}
