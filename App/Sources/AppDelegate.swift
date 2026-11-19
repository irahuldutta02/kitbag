import AppKit
import KitbagCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate,
  NSToolbarDelegate
{
  let manager = ToolManager(descriptors: AllTools.descriptors)
  private var statusItem: NSStatusItem!
  private let popover = NSPopover()
  private let state = PopoverState()
  private let settingsNav = SettingsNav()
  private let connectivity = ConnectivityStatus()
  private var settingsWindow: NSWindow?
  private var sizeObservation: NSKeyValueObservation?
  private var appearanceObservation: NSKeyValueObservation?
  private var outsideClickMonitor: Any?

  func applicationDidFinishLaunching(_ notification: Notification) {
    manager.bootstrap()
    Updater.shared.start()
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
    NotificationCenter.default.addObserver(forName: .kitbagCloseMenu, object: nil, queue: .main) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.popover.performClose(nil) }
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
        [weak self] targetPage in
        self?.popover.performClose(nil)
        self?.openSettings(page: targetPage)
      })
    host.sizingOptions = .preferredContentSize
    popover.contentViewController = host
    // Keep the popover exactly as tall as the current tab, growing and shrinking with it.
    sizeObservation = host.observe(\.preferredContentSize) { [weak self] host, _ in
      MainActor.assumeIsolated { self?.popover.contentSize = host.preferredContentSize }
    }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    connectivity.start()
    // A transient popover doesn't dismiss on clicks in other apps (e.g. full-screen ones),
    // so also watch for mouse-downs delivered to other processes.
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.popover.performClose(nil) }
    }
  }

  func popoverDidClose(_ notification: Notification) {
    if let monitor = outsideClickMonitor {
      NSEvent.removeMonitor(monitor)
      outsideClickMonitor = nil
    }
    manager.setVisibleTool(nil)
    connectivity.stop()
    state.dropMode = false
    sizeObservation = nil
    popover.contentViewController = nil
  }

  // MARK: Settings window (created on demand, released on close)

  private func openSettings(page: String? = nil) {
    if let page {
      settingsNav.page = page
    }
    if settingsWindow == nil {
      let w = NSWindow(
        contentViewController: NSHostingController(
          rootView: SettingsView(manager: manager, nav: settingsNav)))
      w.title = "Kitbag"
      // Modern macOS look: content runs under a transparent title bar, like System Settings.
      w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
      w.titlebarAppearsTransparent = true
      w.titleVisibility = .hidden
      w.isOpaque = false  // lets the window's frosted backdrop show the desktop
      w.backgroundColor = .clear
      w.isMovableByWindowBackground = true
      // No native full screen: it hides the window buttons. The green button zooms the window instead.
      w.collectionBehavior.insert(.fullScreenNone)
      let toolbar = NSToolbar(identifier: "KitbagToolbar")
      toolbar.delegate = self
      toolbar.displayMode = .iconOnly
      w.toolbar = toolbar
      w.toolbarStyle = .unified
      w.titlebarSeparatorStyle = .none
      w.setContentSize(NSSize(width: 900, height: 620))
      w.setFrameAutosaveName("KitbagWindow2")
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

  // MARK: Toolbar: empty; it only gives the taller title bar so the window buttons sit in the sidebar.

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.flexibleSpace]
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.flexibleSpace]
  }

  func toolbar(
    _ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? { nil }

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
  @ObservedObject private var updater = Updater.shared
  @ObservedObject var state: PopoverState
  @ObservedObject var connectivity: ConnectivityStatus
  let openSettings: (String?) -> Void

  @Environment(\.colorScheme) private var scheme

  private var tabs: [(descriptor: ToolDescriptor, tool: any KitbagTool)] {
    manager.enabledTools.filter {
      $0.descriptor.showsTab && $0.descriptor.showsMenuTab
        && (!state.dropMode || $0.tool.acceptsFileDrops)
    }
  }
  private var currentTab: (descriptor: ToolDescriptor, tool: any KitbagTool)? {
    tabs.first { $0.descriptor.id == state.selected } ?? tabs.first
  }
  private var currentID: String? { currentTab?.descriptor.id }

  private var tabTrackFill: Color {
    scheme == .dark ? Color.white.opacity(0.065) : Color.black.opacity(0.048)
  }
  private var tabTrackBorder: Color {
    scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
  }

  var body: some View {
    VStack(spacing: 10) {
      if updater.bannerVisible { UpdateBanner() }

      // Top navigation strip: segmented icon bar + quick connectivity buttons
      HStack(alignment: .center, spacing: 8) {
        if !tabs.isEmpty {
          HStack(spacing: 2) {
            ForEach(Array(tabs.enumerated()), id: \.element.descriptor.id) { index, tab in
              tabButton(tab.descriptor, index: index)
            }
          }
          .padding(3)
          .background(tabTrackFill, in: Capsule())
          .overlay(Capsule().strokeBorder(tabTrackBorder, lineWidth: 0.5))
        }
        Spacer(minLength: 4)
        ConnectivityButtons(status: connectivity)
      }

      // Active tool title bar
      if let tab = currentTab {
        HStack(spacing: 8) {
          Look.tile(
            ToolIcon(tab.descriptor).scaleEffect(0.78),
            Look.tint(tab.descriptor.id),
            size: 20
          )
          Text(tab.descriptor.name)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
          Spacer(minLength: 6)
          Button {
            openSettings(tab.descriptor.id)
          } label: {
            Image(systemName: "slider.horizontal.3")
              .font(.system(size: 11.5, weight: .medium))
              .foregroundStyle(.secondary)
              .frame(width: 24, height: 22)
              .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
          }
          .buttonStyle(.plain)
          .hoverHighlight(cornerRadius: 6)
          .help("Configure \(Text(tab.descriptor.name))")
          .accessibilityLabel("Configure \(Text(tab.descriptor.name))")
        }
        .padding(.horizontal, 2)
      }

      // Active tool content
      if tabs.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "square.grid.2x2")
            .font(.system(size: 26, weight: .light))
            .foregroundStyle(.tertiary)
          Text("No tools enabled")
            .font(.callout.weight(.medium))
          Text("Turn on the utilities you want in Settings.")
            .font(.caption)
            .foregroundStyle(.secondary)
          Button("Open Settings") { openSettings("general") }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .card()
      } else if let tab = currentTab {
        tab.tool.makeMenuView()
          .id(currentID)
      }

      // Startup errors, if any
      ForEach(manager.descriptors) { d in
        if let err = manager.errors[d.id] {
          HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(KitbagUI.danger)
            Text("\(Text(d.name)) couldn't start: \(err)")
              .font(.caption)
              .foregroundStyle(KitbagUI.danger)
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 7)
          .background(
            KitbagUI.danger.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
          )
        }
      }

      // Grounded footer
      Divider().opacity(0.55)
      HStack {
        Button {
          openSettings(currentID ?? "general")
        } label: {
          HStack(spacing: 5) {
            Image(systemName: "gearshape")
              .font(.system(size: 12, weight: .medium))
            Text("Settings…")
          }
          .padding(.horizontal, 7)
          .padding(.vertical, 4)
          .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 6)
        .keyboardShortcut(",")

        Spacer()

        Button {
          NSApp.terminate(nil)
        } label: {
          HStack(spacing: 5) {
            Image(systemName: "power")
              .font(.system(size: 11.5, weight: .medium))
            Text("Quit")
          }
          .padding(.horizontal, 7)
          .padding(.vertical, 4)
          .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 6, tint: KitbagUI.danger)
        .keyboardShortcut("q")
      }
      .font(.callout)
      .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 13)
    .padding(.top, 12)
    .padding(.bottom, 10)
    .frame(width: tabs.count > 7 ? 404 : 380)
    .frame(maxHeight: .infinity, alignment: .top)
    .onAppear { manager.setVisibleTool(currentID) }
    .onChange(of: currentID) { _, new in manager.setVisibleTool(new) }
  }

  @ViewBuilder
  private func tabButton(_ descriptor: ToolDescriptor, index: Int) -> some View {
    let on = descriptor.id == currentID
    let itemWidth: CGFloat = tabs.count > 7 ? 31 : (tabs.count > 5 ? 35 : 40)

    let btn = Button {
      state.selected = descriptor.id
    } label: {
      ToolIcon(descriptor)
        .font(.system(size: 13.5, weight: .medium))
        .foregroundStyle(on ? Color.white : Color.secondary)
        .frame(width: itemWidth, height: 27)
        .background {
          if on { Capsule().fill(Color.accentColor) }
        }
        .capsuleHoverHighlight(tint: on ? nil : Color.primary)
        .contentShape(Capsule())
    }
    .buttonStyle(PressableStyle())
    .help(index < 9 ? "\(Text(descriptor.name)) (⌘\(index + 1))" : "\(Text(descriptor.name))")
    .accessibilityLabel(Text(descriptor.name))
    .accessibilityAddTraits(on ? .isSelected : [])

    if index < 9 {
      btn.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
    } else {
      btn
    }
  }
}
