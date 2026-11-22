import AppKit
import CoreGraphics

/// Reports presses and releases of the Globe / fn key. Needs Accessibility / Input Monitoring access
/// to hear it in other apps. In System Settings > Keyboard, set "Press globe key to" to "Do Nothing".
///
/// macOS can silently stop delivering key events to a listener (after sleep, a lock screen, a busy
/// moment, or a lost key-up), which used to leave the key dead until the menu was opened. So the
/// listener is an event tap that is re-enabled whenever macOS turns it off, rebuilt if it dies, and
/// checked every few seconds; and a key that looks stuck down is released when macOS says it is up.
@MainActor
final class FnKeyWatcher {
  var onDown: (() -> Void)?
  var onUp: (() -> Void)?
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  private var global: Any?
  private var local: Any?
  private var watchdog: Timer?
  private var observers: [NSObjectProtocol] = []
  private var isDown = false
  private var running = false
  private var ticks = 0

  func start() {
    stop()
    running = true
    installTap()
    global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
      let code = e.keyCode, down = e.modifierFlags.contains(.function)
      Task { @MainActor in self?.handle(code, down) }
    }
    local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
      self?.handle(e.keyCode, e.modifierFlags.contains(.function))
      return e
    }
    let wd = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.check() }
    }
    wd.tolerance = 0.5  // lets the system coalesce wakeups
    RunLoop.main.add(wd, forMode: .common)
    watchdog = wd
    let center = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.screensDidWakeNotification] {
      observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in self?.rebuild() }
      })
    }
  }

  func stop() {
    running = false
    removeTap()
    if let global { NSEvent.removeMonitor(global) }
    if let local { NSEvent.removeMonitor(local) }
    global = nil
    local = nil
    watchdog?.invalidate()
    watchdog = nil
    observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    observers = []
    isDown = false
  }

  // MARK: Event tap

  private func installTap() {
    guard tap == nil else { return }
    let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
    let callback: CGEventTapCallBack = { _, type, event, refcon in
      guard let refcon else { return Unmanaged.passUnretained(event) }
      let watcher = Unmanaged<FnKeyWatcher>.fromOpaque(refcon).takeUnretainedValue()
      switch type {
      case .tapDisabledByTimeout, .tapDisabledByUserInput:
        Task { @MainActor in watcher.reenable() }
      case .flagsChanged:
        let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let down = event.flags.contains(.maskSecondaryFn)
        Task { @MainActor in watcher.handle(code, down) }
      default: break
      }
      return Unmanaged.passUnretained(event)
    }
    guard
      let port = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
        eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque())
    else { return }  // no permission yet; the watchdog tries again
    tap = port
    source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: port, enable: true)
  }

  private func removeTap() {
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    if let tap {
      CGEvent.tapEnable(tap: tap, enable: false)
      CFMachPortInvalidate(tap)
    }
    source = nil
    tap = nil
  }

  private func reenable() {
    if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
  }

  private func rebuild() {
    guard running else { return }
    removeTap()
    installTap()
  }

  /// Runs every quarter second: revives a dead tap and releases a key that is stuck down.
  private func check() {
    guard running else { return }
    if let tap {
      if !CGEvent.tapIsEnabled(tap: tap) { rebuild() }
    } else {
      // Permission may have been granted since; trying is costly, so only every couple of seconds.
      ticks += 1
      if ticks % 2 == 0 { installTap() }
    }
    // A missed key-up would otherwise swallow the next press.
    if isDown, !CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn) {
      handle(63, false)
    }
  }

  private func handle(_ keyCode: UInt16, _ down: Bool) {
    guard keyCode == 63 || keyCode == 179, down != isDown else { return }
    isDown = down
    if down { onDown?() } else { onUp?() }
  }
}
