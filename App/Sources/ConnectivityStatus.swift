import AppKit
import CoreWLAN
import IOKit
import KitbagCore
import notify

enum WiFiState { case off, idle, connected }
enum BluetoothState { case off, on, connected }

/// State for the two corner buttons, and what a click does. Read only while the menu is open.
@MainActor
final class ConnectivityStatus: ObservableObject {
  enum Kind {
    case wifi, bluetooth

    var title: String { self == .wifi ? "Wi-Fi" : "Bluetooth" }
    var menuID: String {
      self == .wifi ? "com.apple.menuextra.wifi" : "com.apple.menuextra.bluetooth"
    }
    var tile: String { self == .wifi ? "controlcenter-wifi" : "controlcenter-bluetooth" }
    var settingsURLs: [String] {
      self == .wifi
        ? [
          "x-apple.systempreferences:com.apple.wifi-settings-extension",
          "x-apple.systempreferences:com.apple.preference.network",
        ]
        : [
          "x-apple.systempreferences:com.apple.BluetoothSettings",
          "x-apple.systempreferences:com.apple.preference.bluetooth",
        ]
    }
  }

  @Published private(set) var wifi: WiFiState = .idle
  @Published private(set) var bluetooth: BluetoothState = .on
  private let guide = AccessibilityGuide()
  private var timer: Timer?

  func start() {
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
    timer?.tolerance = 1
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  func refresh() {
    if let i = CWWiFiClient.shared().interface() {
      wifi = !i.powerOn() ? .off : (i.rssiValue() != 0 ? .connected : .idle)
    }
    bluetooth =
      !Self.bluetoothPoweredOn() ? .off : (Self.connectedBluetoothDevices() > 0 ? .connected : .on)
  }

  /// Bluetooth power, from the state macOS publishes under "com.apple.bluetooth.power" (1 = on).
  /// Readable from the sandbox with no permission prompt; if it can't be read, Bluetooth is
  /// assumed on.
  private static func bluetoothPoweredOn() -> Bool {
    var token: Int32 = 0
    guard notify_register_check("com.apple.bluetooth.power", &token) == 0 else { return true }
    defer { notify_cancel(token) }
    var state: UInt64 = 0
    guard notify_get_state(token, &state) == 0 else { return true }
    return state != 0
  }

  /// Devices stay in the I/O registry while Bluetooth is off, so this only counts when it's on.
  static func connectedBluetoothDevices() -> Int {
    var iterator: io_iterator_t = 0
    guard
      IOServiceGetMatchingServices(
        kIOMainPortDefault, IOServiceMatching("IOBluetoothDevice"), &iterator) == KERN_SUCCESS
    else { return 0 }
    defer { IOObjectRelease(iterator) }
    var count = 0
    while case let service = IOIteratorNext(iterator), service != 0 {
      count += 1
      IOObjectRelease(service)
    }
    return count
  }

  /// Opens the real macOS dropdown. First click asks for Accessibility access with the guided
  /// walkthrough and continues by itself; if the dropdown can't be opened, opens the Settings pane.
  func open(_ kind: Kind) {
    Task {
      switch await MenuExtra.open(
        identifier: kind.menuID, title: kind.title, controlCenterTile: kind.tile)
      {
      case .opened: break
      case .needsPermission: guide.begin { [weak self] in self?.open(kind) }
      case .notFound:
        for link in kind.settingsURLs {
          if let url = URL(string: link), NSWorkspace.shared.open(url) { break }
        }
      }
    }
  }
}
