import KitbagCore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var manager: ToolManager

  var body: some View {
    Form {
      Section("Tools") {
        ForEach(manager.descriptors.filter { $0.requiresApp == nil }) { d in row(d) }
      }
      let integrations = manager.descriptors.filter {
        $0.requiresApp != nil && manager.isAvailable($0)
      }
      if !integrations.isEmpty {
        Section("Integrations") {
          ForEach(integrations) { d in row(d) }
        }
      }
      LoginItemSection()
    }
    .formStyle(.grouped)
    .frame(width: 420)
    .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder private func row(_ d: ToolDescriptor) -> some View {
    Toggle(
      isOn: Binding(get: { manager.isEnabled(d.id) }, set: { manager.setEnabled(d.id, $0) })
    ) {
      Label {
        Text(d.name)
      } icon: {
        ToolIcon(d)
      }
    }
    if let err = manager.errors[d.id] {
      Text(err).font(.caption).foregroundStyle(.red)
    }
    if let tool = manager.active[d.id], let settings = tool.makeSettingsView() {
      settings.padding(.leading, 24)
    }
  }
}
