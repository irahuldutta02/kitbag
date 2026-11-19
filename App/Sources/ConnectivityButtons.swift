import KitbagCore
import SwiftUI

/// Wi-Fi and Bluetooth quick status buttons in the menu bar popover header.
struct ConnectivityButtons: View {
  @ObservedObject var status: ConnectivityStatus
  @ObservedObject private var layout = MenuLayout.shared
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    HStack(spacing: 5) {
      if layout.isShown(MenuLayout.wifi) {
        button(.wifi, label: wifiLabel, active: status.wifi == .connected) {
          Image(systemName: status.wifi == .off ? "wifi.slash" : "wifi")
            .font(.system(size: 12.5, weight: .semibold))
        }
      }
      if layout.isShown(MenuLayout.bluetooth) {
        button(.bluetooth, label: bluetoothLabel, active: status.bluetooth == .connected) {
          BluetoothGlyph()
            .frame(width: 8.5, height: 13.5)
            .opacity(status.bluetooth == .off ? 0.4 : 1)
        }
      }
    }
  }

  private var bluetoothLabel: String {
    switch status.bluetooth {
    case .off: return "Bluetooth: Off"
    case .on: return "Bluetooth: On"
    case .connected: return "Bluetooth: Connected"
    }
  }

  private var wifiLabel: String {
    switch status.wifi {
    case .off: return "Wi-Fi: Off"
    case .idle: return "Wi-Fi: Not connected"
    case .connected: return "Wi-Fi: Connected"
    }
  }

  private func button<Icon: View>(
    _ kind: ConnectivityStatus.Kind,
    label: String,
    active: Bool,
    @ViewBuilder icon: () -> Icon
  ) -> some View {
    let inactiveFill = scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.055)
    let stroke = scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07)

    return Button {
      status.open(kind)
    } label: {
      icon()
        .foregroundStyle(active ? Color.white : Color.secondary)
        .frame(width: 30, height: 30)
        .background(Circle().fill(active ? Color.accentColor : inactiveFill))
        .overlay(
          Circle().strokeBorder(active ? Color.white.opacity(0.18) : stroke, lineWidth: 0.5)
        )
        .capsuleHoverHighlight(tint: active ? .white : nil)
        .contentShape(Circle())
    }
    .buttonStyle(PressableStyle())
    .help(label)
    .accessibilityLabel(label)
  }
}
