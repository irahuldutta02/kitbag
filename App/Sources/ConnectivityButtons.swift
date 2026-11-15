import KitbagCore
import SwiftUI

/// Wi-Fi and Bluetooth in the corner of the menu: the icon shows the state, a click opens macOS's own control.
struct ConnectivityButtons: View {
  @ObservedObject var status: ConnectivityStatus

  var body: some View {
    HStack(spacing: 6) {
      button(.wifi, label: wifiLabel, active: status.wifi == .connected) {
        Image(systemName: status.wifi == .off ? "wifi.slash" : "wifi")
          .resizable().scaledToFit().frame(width: 16, height: 16)
      }
      button(.bluetooth, label: bluetoothLabel, active: status.bluetooth == .connected) {
        BluetoothGlyph().frame(width: 10, height: 16)
          .opacity(status.bluetooth == .off ? 0.35 : 1)
      }
    }
  }

  private var bluetoothLabel: String {
    switch status.bluetooth {
    case .off: return "Bluetooth: off"
    case .on: return "Bluetooth: on"
    case .connected: return "Bluetooth: connected"
    }
  }

  private var wifiLabel: String {
    switch status.wifi {
    case .off: return "Wi-Fi: off"
    case .idle: return "Wi-Fi: not connected"
    case .connected: return "Wi-Fi: connected"
    }
  }

  private func button<Icon: View>(
    _ kind: ConnectivityStatus.Kind, label: String, active: Bool, @ViewBuilder icon: () -> Icon
  ) -> some View {
    Button {
      status.open(kind)
    } label: {
      icon()
        .foregroundStyle(active ? Color.white : Color.secondary)
        .frame(width: 34, height: 34)
        .background(Circle().fill(active ? Color.accentColor : Color.clear))
        .glass(Circle(), interactive: true)
        .contentShape(Circle())
    }
    .buttonStyle(PressableStyle())
    .help(label)
    .accessibilityLabel(label)
  }
}
