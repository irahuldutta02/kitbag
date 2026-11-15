import AppKit

/// Reports presses and releases of the Globe / fn key. Needs Accessibility access to hear it
/// in other apps. In System Settings > Keyboard, set "Press globe key to" to "Do Nothing".
@MainActor
final class FnKeyWatcher {
  var onDown: (() -> Void)?
  var onUp: (() -> Void)?
  private var global: Any?
  private var local: Any?
  private var isDown = false

  func start() {
    stop()
    global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
      let code = e.keyCode, down = e.modifierFlags.contains(.function)
      Task { @MainActor in self?.handle(code, down) }
    }
    local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
      self?.handle(e.keyCode, e.modifierFlags.contains(.function))
      return e
    }
  }

  func stop() {
    if let global { NSEvent.removeMonitor(global) }
    if let local { NSEvent.removeMonitor(local) }
    global = nil
    local = nil
    isDown = false
  }

  private func handle(_ keyCode: UInt16, _ down: Bool) {
    guard keyCode == 63 || keyCode == 179, down != isDown else { return }
    isDown = down
    if down { onDown?() } else { onUp?() }
  }
}
