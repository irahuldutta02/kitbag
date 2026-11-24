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
  private var floatingPanel: MenuPanel?
  private var panelHost: NSHostingController<PopoverView>?
  private var panelResignObserver: NSObjectProtocol?
  private var panelOpenedAt = Date.distantPast
  private var panelTopEdge: CGFloat = 0
  private var panelCenterX: CGFloat = 0
  private var panelScreenFrame: NSRect = .zero
  private let state = PopoverState()
  private let settingsNav = SettingsNav()
  private var settingsWindow: NSWindow?
  private var sizeObservation: NSKeyValueObservation?
  private var appearanceObservation: NSKeyValueObservation?
  private var outsideClickMonitor: Any?
  private lazy var popups = ToolPopups(manager: manager)

  private var isMenuShown: Bool { popover.isShown || (floatingPanel?.isVisible ?? false) }

  func applicationDidFinishLaunching(_ notification: Notification) {
    Diagnostics.shared.contextProvider = { [weak self] in
      guard let self else { return [] }
      let on = self.manager.enabledTools.map(\.descriptor.id).sorted().joined(separator: ", ")
      return ["tools enabled: \(on.isEmpty ? "none" : on)"]
    }
    manager.bootstrap()
    EditShortcuts.install()
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
      MainActor.assumeIsolated { self?.closeMenu() }
    }
    NotificationCenter.default.addObserver(forName: .kitbagOpenTab, object: nil, queue: .main) {
      [weak self] note in
      let tabID = note.object as? String
      MainActor.assumeIsolated {
        guard let self, let tabID else { return }
        if self.isMenuShown && self.state.selected == tabID {
          self.closeMenu()
        } else {
          self.state.selected = tabID
          if self.popover.isShown {
            self.popover.contentViewController?.view.window?.makeKey()
          } else if let panel = self.floatingPanel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
          } else {
            // Global shortcuts use a floating panel instead of NSPopover so auto-hiding
            // menu bars and full-screen Spaces never immediately dismiss the menu.
            self.showFloatingPanel()
          }
        }
      }
    }
    NotificationCenter.default.addObserver(forName: .kitbagOpenPopup, object: nil, queue: .main) {
      [weak self] note in
      let id = note.object as? String
      MainActor.assumeIsolated {
        guard let self, let id else { return }
        self.closeMenu()
        self.popups.open(id)
      }
    }
    NotificationCenter.default.addObserver(
      forName: .kitbagOpenSettings, object: nil, queue: .main
    ) { [weak self] note in
      let page = note.object as? String
      MainActor.assumeIsolated {
        self?.closeMenu()
        self?.openSettings(page: page)
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
    isMenuShown ? closeMenu() : show()
  }

  private func closeMenu() {
    if popover.isShown { popover.performClose(nil) }
    closeFloatingPanel()
  }

  private func makePopoverHost() -> NSHostingController<PopoverView> {
    let host = NSHostingController(
      rootView: PopoverView(manager: manager, state: state) {
        [weak self] targetPage in
        self?.closeMenu()
        self?.openSettings(page: targetPage)
      })
    host.sizingOptions = .preferredContentSize
    return host
  }

  private func show() {
    closeFloatingPanel()
    guard !popover.isShown, let button = statusItem.button else { return }
    // Content is built only now and released on close.
    let host = makePopoverHost()
    popover.contentViewController = host
    // Keep the popover exactly as tall as the current tab, growing and shrinking with it.
    sizeObservation = host.observe(\.preferredContentSize) { [weak self] host, _ in
      MainActor.assumeIsolated {
        // Resize at once: an animated popover resize makes the tab bar slide when switching tabs.
        NSAnimationContext.runAnimationGroup { ctx in
          ctx.duration = 0
          ctx.allowsImplicitAnimation = false
          self?.popover.contentSize = host.preferredContentSize
        }
      }
    }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
    // A transient popover doesn't dismiss on clicks in other apps (e.g. full-screen ones),
    // so also watch for mouse-downs delivered to other processes.
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.popover.performClose(nil) }
    }
  }

  /// Presents the menu inside a borderless floating panel so global shortcuts work reliably
  /// even when macOS's menu bar is auto-hidden or the user is in a full-screen Space.
  private func showFloatingPanel() {
    if popover.isShown { popover.performClose(nil) }
    closeFloatingPanel()

    let host = makePopoverHost()
    panelHost = host
    host.view.layoutSubtreeIfNeeded()
    let measured =
      host.preferredContentSize.height > 10 ? host.preferredContentSize : host.view.fittingSize
    let initialSize = normalizedPanelSize(measured)

    let screen =
      NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
      ?? NSScreen.main ?? NSScreen.screens.first
    let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    let full = screen?.frame ?? visible
    panelScreenFrame = visible

    // Anchor horizontally under the status icon if it lives on this screen; otherwise top-right.
    let margin: CGFloat = 10
    if let statusFrame = statusItem.button?.window?.frame,
      statusFrame.width > 0,
      statusFrame.midX >= full.minX && statusFrame.midX <= full.maxX
    {
      panelCenterX = statusFrame.midX
    } else {
      panelCenterX = visible.maxX - margin - initialSize.width / 2
    }
    let menuBarVisible = visible.maxY < full.maxY - 4
    panelTopEdge = menuBarVisible ? visible.maxY - 6 : full.maxY - 10

    let frame = panelFrame(for: initialSize)
    let panel = MenuPanel(
      contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.isFloatingPanel = true
    panel.level = .popUpMenu
    panel.hidesOnDeactivate = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isReleasedWhenClosed = false
    panel.animationBehavior = .utilityWindow
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.onEscape = { [weak self] in self?.closeFloatingPanel() }

    let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
    blur.material = .popover
    blur.blendingMode = .behindWindow
    blur.state = .active
    blur.wantsLayer = true
    blur.layer?.cornerRadius = 14
    blur.layer?.cornerCurve = .continuous
    blur.layer?.masksToBounds = true
    blur.layer?.borderWidth = 0.75
    blur.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
    blur.autoresizingMask = [.width, .height]

    host.view.frame = blur.bounds
    host.view.autoresizingMask = [.width, .height]
    blur.addSubview(host.view)
    panel.contentView = blur
    floatingPanel = panel

    sizeObservation = host.observe(\.preferredContentSize) { [weak self] host, _ in
      MainActor.assumeIsolated { self?.resizeFloatingPanel(to: host.preferredContentSize) }
    }

    panelOpenedAt = Date()
    panel.setFrame(frame, display: true)
    panel.makeKeyAndOrderFront(nil)

    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.closeFloatingPanel() }
    }
    panelResignObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, Date().timeIntervalSince(self.panelOpenedAt) > 0.15 else { return }
        self.closeFloatingPanel()
      }
    }
  }

  private func normalizedPanelSize(_ size: NSSize) -> NSSize {
    NSSize(
      width: max(360, size.width.isFinite && size.width > 0 ? size.width : 380),
      height: max(120, min(size.height.isFinite && size.height > 0 ? size.height : 320, 680))
    )
  }

  private func panelFrame(for rawSize: NSSize) -> NSRect {
    let size = normalizedPanelSize(rawSize)
    let margin: CGFloat = 10
    let maxHeight = max(160, panelTopEdge - panelScreenFrame.minY - margin)
    let clampedHeight = min(size.height, maxHeight)
    let x = max(
      panelScreenFrame.minX + margin,
      min(panelCenterX - size.width / 2, panelScreenFrame.maxX - size.width - margin))
    let y = max(panelScreenFrame.minY + margin, panelTopEdge - clampedHeight)
    return NSRect(x: x.rounded(), y: y.rounded(), width: size.width.rounded(), height: clampedHeight.rounded())
  }

  private func resizeFloatingPanel(to newSize: NSSize) {
    guard let panel = floatingPanel, panel.isVisible else { return }
    let next = panelFrame(for: newSize)
    if abs(next.width - panel.frame.width) > 0.5 || abs(next.height - panel.frame.height) > 0.5
      || abs(next.origin.x - panel.frame.origin.x) > 0.5
      || abs(next.origin.y - panel.frame.origin.y) > 0.5
    {
      panel.setFrame(next, display: true)
    }
  }

  private func closeFloatingPanel() {
    guard let panel = floatingPanel else { return }
    if let monitor = outsideClickMonitor {
      NSEvent.removeMonitor(monitor)
      outsideClickMonitor = nil
    }
    if let observer = panelResignObserver {
      NotificationCenter.default.removeObserver(observer)
      panelResignObserver = nil
    }
    sizeObservation = nil
    panel.orderOut(nil)
    panel.contentView = nil
    floatingPanel = nil
    panelHost = nil
    if !popover.isShown {
      manager.setVisibleTool(nil)
      state.dropMode = false
    }
  }

  func popoverDidClose(_ notification: Notification) {
    if let monitor = outsideClickMonitor, floatingPanel == nil {
      NSEvent.removeMonitor(monitor)
      outsideClickMonitor = nil
    }
    if floatingPanel == nil {
      manager.setVisibleTool(nil)
      state.dropMode = false
      sizeObservation = nil
    }
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
    NSApp.dockTile.contentView = nil  // use the app's own icon, same as in Applications
    NSApp.dockTile.display()
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow?.makeKeyAndOrderFront(nil)
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

/// Floating borderless panel that can accept keyboard input (e.g. search) without activating
/// Kitbag or depending on an auto-hidden menu bar window.
private final class MenuPanel: NSPanel {
  var onEscape: (() -> Void)?
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
  override func cancelOperation(_ sender: Any?) { onEscape?() }
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

      // Top navigation strip: full-width segmented icon bar, tabs share the space evenly
      if !tabs.isEmpty {
        HStack(spacing: 2) {
          ForEach(Array(tabs.enumerated()), id: \.element.descriptor.id) { index, tab in
            tabButton(tab.descriptor, index: index)
          }
        }
        .padding(3)
        .frame(maxWidth: .infinity)
        .background(tabTrackFill, in: Capsule())
        .overlay(Capsule().strokeBorder(tabTrackBorder, lineWidth: 0.5))
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
    .frame(width: 380)
    .frame(maxHeight: .infinity, alignment: .top)
    .onAppear { manager.setVisibleTool(currentID) }
    .onChange(of: currentID) { _, new in manager.setVisibleTool(new) }
  }

  @ViewBuilder
  private func tabButton(_ descriptor: ToolDescriptor, index: Int) -> some View {
    let on = descriptor.id == currentID

    let btn = Button {
      state.selected = descriptor.id
    } label: {
      ToolIcon(descriptor)
        .font(.system(size: 13.5, weight: .medium))
        .foregroundStyle(on ? Color.white : Color.secondary)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background {
          if on { Capsule().fill(Color.accentColor) }
        }
        .capsuleHoverHighlight(tint: on ? nil : Color.primary)
        .contentShape(Capsule())
        .transaction { $0.animation = nil }  // no slide or fade of the icon when the tab changes
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
