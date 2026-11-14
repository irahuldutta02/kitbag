import AppKit
import KitbagCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
  let manager = ToolManager(descriptors: AllTools.descriptors)
  private var statusItem: NSStatusItem!
  private let popover = NSPopover()
  private let state = PopoverState()
  private let connectivity = ConnectivityStatus()
  private var settingsWindow: NSWindow?
  private var sizeObservation: NSKeyValueObservation?
  private var appearanceObservation: NSKeyValueObservation?

  func applicationDidFinishLaunching(_ notification: Notification) {
    manager.bootstrap()
    // After a drop (or a drag that left), show every tab again, staying on the shelf.
    NotificationCenter.default.addObserver(
      forName: .kitbagFileDropFinished, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.state.dropMode else { return }
        self.state.selected =
          self.manager.enabledTools.first { $0.tool.acceptsFileDrops }?
          .descriptor.id
        self.state.dropMode = false
      }
    }
    popover.behavior = .transient
    popover.delegate = self

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    guard let button = statusItem.button else { return }
    if let url = Bundle.main.url(forResource: "MenuIcon", withExtension: "svg"),
      let icon = NSImage(contentsOf: url)
    {
      icon.size = NSSize(width: 18, height: 18)
      icon.isTemplate = true  // adapts to light/dark menu bar
      icon.accessibilityDescription = "Kitbag"
      button.image = icon
    } else {
      button.image = NSImage(
        systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: "Kitbag")
    }
    button.target = self
    button.action = #selector(toggle)

    // Dragging files over the icon opens the popover so they can be dropped on the shelf.
    let drop = StatusDropView(frame: button.bounds)
    drop.autoresizingMask = [.width, .height]
    drop.onDragEnter = { [weak self] in
      self?.state.dropMode = true
      self?.show()
    }
    button.addSubview(drop)
  }

  @objc private func toggle() {
    popover.isShown ? popover.performClose(nil) : show()
  }

  private func show() {
    guard !popover.isShown, let button = statusItem.button else { return }
    // Content is built only now and released on close.
    let host = NSHostingController(
      rootView: PopoverView(manager: manager, state: state, connectivity: connectivity) {
        [weak self] in
        self?.popover.performClose(nil)
        self?.openSettings()
      })
    host.sizingOptions = .preferredContentSize
    popover.contentViewController = host
    // Keep the popover exactly as tall as the current tab, growing and shrinking with it.
    sizeObservation = host.observe(\.preferredContentSize) { [weak self] host, _ in
      MainActor.assumeIsolated { self?.popover.contentSize = host.preferredContentSize }
    }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    connectivity.start()
  }

  func popoverDidClose(_ notification: Notification) {
    manager.setVisibleTool(nil)
    connectivity.stop()
    state.dropMode = false
    sizeObservation = nil
    popover.contentViewController = nil
  }

  // MARK: Settings window (created on demand, released on close)

  private func openSettings() {
    if settingsWindow == nil {
      let w = NSWindow(
        contentViewController: NSHostingController(rootView: SettingsView(manager: manager)))
      w.title = String(localized: "Kitbag Settings")
      w.styleMask = [.titled, .closable]
      w.isReleasedWhenClosed = false
      w.delegate = self
      w.center()
      settingsWindow = w
    }
    NSApp.setActivationPolicy(.regular)  // show in the Dock while the app window is open
    updateDockIcon()
    appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
      MainActor.assumeIsolated { self?.updateDockIcon() }
    }
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow?.makeKeyAndOrderFront(nil)
  }

  /// Draws the light or dark icon artwork on the Dock tile itself, so it follows the system
  /// appearance and isn't framed like a legacy bundle icon.
  private func updateDockIcon() {
    let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    guard
      let url = Bundle.main.url(
        forResource: dark ? "AppIconDark" : "AppIconLight", withExtension: "png"),
      let image = NSImage(contentsOf: url)
    else { return }
    let tile = NSApp.dockTile
    let view = NSImageView(frame: NSRect(origin: .zero, size: tile.size))
    view.image = image
    view.imageScaling = .scaleProportionallyUpOrDown
    tile.contentView = view
    tile.display()
  }

  /// Dock icon click or reopening from Finder opens the app window.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    openSettings()
    return false
  }

  func windowWillClose(_ notification: Notification) {
    settingsWindow?.contentViewController = nil
    settingsWindow = nil
    appearanceObservation = nil
    NSApp.dockTile.contentView = nil
    NSApp.dockTile.display()
    NSApp.setActivationPolicy(.accessory)  // back to menu-bar only
  }
}

/// Transparent overlay on the status button: forwards clicks, reports drag-enter.
private final class StatusDropView: NSView {
  var onDragEnter: (() -> Void)?

  override init(frame: NSRect) {
    super.init(frame: frame)
    registerForDraggedTypes([.fileURL])
  }
  required init?(coder: NSCoder) { fatalError() }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    onDragEnter?()
    return []
  }
  override func mouseDown(with event: NSEvent) { (superview as? NSControl)?.performClick(nil) }
  override func isAccessibilityElement() -> Bool { false }
}

final class PopoverState: ObservableObject {
  @Published var selected: String?
  @Published var dropMode = false  // files are being dragged: only drop-capable tabs
}

struct PopoverView: View {
  @ObservedObject var manager: ToolManager
  @ObservedObject var state: PopoverState
  @ObservedObject var connectivity: ConnectivityStatus
  @Namespace private var tabSpace
  let openSettings: () -> Void

  private var tabs: [(descriptor: ToolDescriptor, tool: any KitbagTool)] {
    manager.enabledTools.filter {
      $0.descriptor.showsTab && (!state.dropMode || $0.tool.acceptsFileDrops)
    }
  }
  private var currentID: String? {
    (tabs.first { $0.descriptor.id == state.selected } ?? tabs.first)?.descriptor.id
  }

  var body: some View {
    VStack(spacing: 12) {
      HStack(alignment: .center) {
        if !tabs.isEmpty {
          HStack(spacing: 4) {
            ForEach(tabs, id: \.descriptor.id) { tab in
              let on = tab.descriptor.id == currentID
              Button {
                withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
                  state.selected = tab.descriptor.id
                }
              } label: {
                ToolIcon(tab.descriptor)
                  .font(.system(size: 14, weight: .medium))
                  .foregroundStyle(on ? Color.white : Color.secondary)
                  .frame(width: 40, height: 28)
                  .background {
                    if on {
                      Capsule().fill(Color.accentColor)
                        .matchedGeometryEffect(id: "tab", in: tabSpace)
                    }
                  }
                  .contentShape(Capsule())
              }
              .buttonStyle(PressableStyle())
              .help(Text(tab.descriptor.name))
              .accessibilityLabel(Text(tab.descriptor.name))
              .accessibilityAddTraits(on ? .isSelected : [])
            }
          }
          .padding(3)
          .glass(Capsule())
        }
        Spacer(minLength: 8)
        ConnectivityButtons(status: connectivity)
      }
      if tabs.isEmpty {
        Text("No tools enabled. Turn some on in Settings.").foregroundStyle(.secondary)
      } else {
        if let tab = tabs.first(where: { $0.descriptor.id == currentID }) {
          tab.tool.makeMenuView()
            .id(currentID)
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        }
      }
      ForEach(manager.descriptors) { d in
        if let err = manager.errors[d.id] {
          Label("\(Text(d.name)) couldn't start: \(err)", systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red).font(.caption)
        }
      }
      HStack {
        Button(action: openSettings) { Label("Settings", systemImage: "gearshape") }
          .keyboardShortcut(",")
        Spacer()
        Button {
          NSApp.terminate(nil)
        } label: {
          Label("Quit", systemImage: "power")
        }
        .keyboardShortcut("q")
      }
      .buttonStyle(.plain)
      .font(.callout)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 4)
    }
    .padding(14)
    .frame(width: 360)
    .frame(maxHeight: .infinity, alignment: .top)  // never re-center while resizing
    .animation(.spring(duration: 0.4, bounce: 0.15), value: currentID)
    .onAppear { manager.setVisibleTool(currentID) }
    .onChange(of: currentID) { _, new in manager.setVisibleTool(new) }
  }
}
