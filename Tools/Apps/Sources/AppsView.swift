import KitbagCore
import SwiftUI

struct AppsView: View {
  @ObservedObject var model: AppsModel

  var body: some View {
    VStack(spacing: 10) {
      if model.visible.isEmpty && model.toolSwitches.isEmpty {
        Text("No apps to show. Install or choose some in Settings ▸ Apps.")
          .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 16).card()
      } else {
        VStack(spacing: 0) {
          ForEach(Array(model.toolSwitches.enumerated()), id: \.element.id) { i, sw in
            if i > 0 { Divider().padding(.vertical, 6) }
            switchRow(sw)
          }
          ForEach(Array(model.visible.enumerated()), id: \.element.id) { i, app in
            if i > 0 || !model.toolSwitches.isEmpty { Divider().padding(.vertical, 6) }
            row(app)
          }
        }
        .card()
      }
      if let n = model.notice { Text(n).font(.caption).foregroundStyle(.red) }
    }
  }

  /// One of Kitbag's own tools, switched like the apps below it.
  private func switchRow(_ sw: ToolSwitch) -> some View {
    HStack(spacing: 10) {
      Image(systemName: sw.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
        .frame(width: 28, height: 28)
        .background(Color.red.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 5) { Text("Kitbag"); Text(sw.name) }.font(.callout.weight(.medium))
        if let e = sw.error {
          Text(e).font(.caption).foregroundStyle(.red).lineLimit(2)
        } else {
          Text(sw.isOn ? "On" : "Off").font(.caption).foregroundStyle(sw.isOn ? .green : .secondary)
        }
      }
      Spacer()
      Toggle(sw.name, isOn: Binding(get: { sw.isOn }, set: { sw.set($0) }))
        .labelsHidden().toggleStyle(.switch).controlSize(.small)
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

/// Pick which apps the Apps tab lists, and open macOS's own menu bar list (the only switch that
/// works for their icons).
struct AppsSettingsView: View {
  @ObservedObject var model: AppsModel

  var body: some View {
    ForEach(AppsModel.catalog) { app in
      let installed = model.installed.contains(app.id)
      HStack(spacing: 10) {
        Toggle(
          isOn: Binding(get: { !model.hidden.contains(app.id) }, set: { model.setShown(app, $0) })
        ) {
          HStack(spacing: 10) {
            Image(nsImage: model.icon(app, size: 22)).resizable().frame(width: 22, height: 22)
              .opacity(installed ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 1) {
              Text("Show \(app.name)")
              if !installed { Text("Not installed, so it's left out of the menu").font(.caption).foregroundStyle(.secondary) }
            }
          }
        }
        if installed && app.background {
          Toggle(
            "Keep window hidden",
            isOn: Binding(get: { !model.windowAllowed.contains(app.id) }, set: { model.setWindowAllowed(app, !$0) })
          )
          .toggleStyle(.checkbox).controlSize(.small)
          .help("When on, \(app.name) runs in the background and its window is put away whenever it pops up, for example when you press the dictation key. Needs Accessibility access for Kitbag.")
        }
        if installed {
          Button("Menu bar icon…") { AppMenuIcon.openSystemSettings() }.controlSize(.small)
            .help("Manage \(app.name)'s menu bar icon in System Settings")
        }
      }
    }
  }
}
