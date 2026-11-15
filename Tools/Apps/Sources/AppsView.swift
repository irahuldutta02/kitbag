import KitbagCore
import SwiftUI

struct AppsView: View {
  @ObservedObject var model: AppsModel

  var body: some View {
    VStack(spacing: 10) {
      VStack(spacing: 0) {
        ForEach(Array(AppsModel.catalog.enumerated()), id: \.element.id) { i, app in
          if i > 0 { Divider().padding(.vertical, 6) }
          row(app)
        }
      }
      .card()
      if let n = model.notice { Text(n).font(.caption).foregroundStyle(.red) }
    }
  }

  private func row(_ app: ManagedApp) -> some View {
    let installed = model.installed.contains(app.id)
    let on = model.running.contains(app.id)
    return HStack(spacing: 10) {
      Image(nsImage: model.icon(app, size: 28)).resizable().frame(width: 28, height: 28)
        .opacity(installed ? 1 : 0.4)
      VStack(alignment: .leading, spacing: 1) {
        Text(app.name).font(.callout.weight(.medium))
        Text(installed ? (on ? "Running" : "Off") : "Not installed")
          .font(.caption).foregroundStyle(on ? .green : .secondary)
      }
      Spacer()
      if model.busy.contains(app.id) { ProgressView().controlSize(.small) }
      Toggle(app.name, isOn: Binding(get: { on }, set: { model.set(app, on: $0) }))
        .labelsHidden().toggleStyle(.switch).controlSize(.small)
        .disabled(!installed || model.busy.contains(app.id))
    }
  }
}

/// One row per app with a shortcut to macOS's own menu bar list, the only switch that works for them.
struct AppsSettingsView: View {
  @ObservedObject var model: AppsModel

  var body: some View {
    ForEach(AppsModel.catalog.filter { model.installed.contains($0.id) }) { app in
      HStack(spacing: 10) {
        Image(nsImage: model.icon(app, size: 22)).resizable().frame(width: 22, height: 22)
        Text("\(app.name)'s menu bar icon")
        Spacer()
        Button("Manage in System Settings") { AppMenuIcon.openSystemSettings() }.controlSize(.small)
      }
    }
  }
}
