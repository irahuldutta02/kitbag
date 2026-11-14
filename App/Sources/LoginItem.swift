import ServiceManagement
import SwiftUI

/// Reads the real status from the system each time; no stored flag.
@MainActor
final class LoginItem: ObservableObject {
  @Published private(set) var status = SMAppService.mainApp.status
  @Published var error: String?

  func refresh() { status = SMAppService.mainApp.status }

  var isOn: Bool { status == .enabled || status == .requiresApproval }

  func set(_ on: Bool) {
    error = nil
    do {
      if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    } catch {
      self.error = error.localizedDescription
    }
    refresh()
  }
}

struct LoginItemSection: View {
  @StateObject private var login = LoginItem()

  var body: some View {
    Section("General") {
      Toggle(
        "Start at login",
        isOn: Binding(get: { login.isOn }, set: { login.set($0) }))
      if login.status == .requiresApproval {
        HStack {
          Text("Approval needed in System Settings.").font(.caption).foregroundStyle(.secondary)
          Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
        }
      }
      if login.status == .notFound {
        Text("Login item unavailable for this build location. Move Kitbag to Applications.")
          .font(.caption).foregroundStyle(.secondary)
      }
      if let e = login.error { Text(e).font(.caption).foregroundStyle(.red) }
    }
    .onAppear { login.refresh() }
  }
}
