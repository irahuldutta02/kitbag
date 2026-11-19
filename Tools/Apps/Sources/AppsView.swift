import KitbagCore
import SwiftUI

struct AppsView: View {
  @ObservedObject var model: AppsModel

  var body: some View {
    VStack(spacing: 10) {
      if model.visible.isEmpty && model.toolSwitches.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "square.grid.2x2")
            .font(.system(size: 24, weight: .light))
            .foregroundStyle(.tertiary)
          Text("No apps selected")
            .font(.callout.weight(.semibold))
          Text("Choose which companion apps to manage in Settings ▸ Apps.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .card()
      } else {
        if !model.toolSwitches.isEmpty {
          VStack(alignment: .leading, spacing: 0) {
            SectionEyebrow("Kitbag Tools")
              .padding(.horizontal, 4)
              .padding(.bottom, 6)
            ForEach(Array(model.toolSwitches.enumerated()), id: \.element.id) { i, sw in
              if i > 0 { Divider().opacity(0.45).padding(.vertical, 5) }
              switchRow(sw)
            }
          }
          .card(padding: 11)
        }

        if !model.visible.isEmpty {
          VStack(alignment: .leading, spacing: 0) {
            if !model.toolSwitches.isEmpty {
              SectionEyebrow("Apps")
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
            }
            ForEach(Array(model.visible.enumerated()), id: \.element.id) { i, app in
              if i > 0 { Divider().opacity(0.45).padding(.vertical, 5) }
              row(app)
            }
          }
          .card(padding: 11)
        }
      }
      if let n = model.notice {
        Label(n, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(KitbagUI.danger)
      }
    }
  }

  /// One of Kitbag's own tools, switched like the apps below it.
  private func switchRow(_ sw: ToolSwitch) -> some View {
    HStack(spacing: 10) {
      Image(systemName: sw.symbol)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 28, height: 28)
        .background(Color.red.gradient, in: RoundedRectangle(cornerRadius: 7.5, style: .continuous))
      VStack(alignment: .leading, spacing: 1.5) {
        HStack(spacing: 4) {
          Text("Kitbag")
          Text(sw.name)
        }.font(.callout.weight(.medium))
        if let e = sw.error {
          Text(e).font(.caption).foregroundStyle(KitbagUI.danger).lineLimit(2)
        } else {
          HStack(spacing: 4) {
            StatusDot(color: sw.isOn ? KitbagUI.success : .secondary, active: sw.isOn, size: 5.5)
            Text(sw.isOn ? "Active" : "Off")
              .font(.caption)
              .foregroundStyle(sw.isOn ? KitbagUI.success : .secondary)
          }
        }
      }
      Spacer()
      Toggle(sw.name, isOn: Binding(get: { sw.isOn }, set: { sw.set($0) }))
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 3)
    .hoverHighlight(cornerRadius: 8)
  }

  private func row(_ app: ManagedApp) -> some View {
    let installed = model.installed.contains(app.id)
    let on = model.running.contains(app.id)
    return HStack(spacing: 10) {
      Image(nsImage: model.icon(app, size: 28))
        .resizable()
        .frame(width: 28, height: 28)
        .opacity(installed ? 1 : 0.4)
      VStack(alignment: .leading, spacing: 1.5) {
        Text(app.name).font(.callout.weight(.medium))
        HStack(spacing: 4) {
          StatusDot(
            color: on ? KitbagUI.success : .secondary,
            active: on,
            size: 5.5
          )
          Text(installed ? (on ? "Running" : "Stopped") : "Not installed")
            .font(.caption)
            .foregroundStyle(on ? KitbagUI.success : .secondary)
        }
      }
      Spacer()
      if model.busy.contains(app.id) { ProgressView().controlSize(.small) }
      Toggle(app.name, isOn: Binding(get: { on }, set: { model.set(app, on: $0) }))
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(!installed || model.busy.contains(app.id))
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 3)
    .hoverHighlight(cornerRadius: 8)
  }
}

/// Pick which apps the Apps tab lists, and open macOS's own menu bar list.
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
            Image(nsImage: model.icon(app, size: 22))
              .resizable()
              .frame(width: 22, height: 22)
              .opacity(installed ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 1) {
              Text("Show \(app.name)")
              if !installed {
                Text("Not installed, so it's hidden from the menu")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
        if installed && app.background {
          Toggle(
            "Keep window hidden",
            isOn: Binding(
              get: { !model.windowAllowed.contains(app.id) },
              set: { model.setWindowAllowed(app, !$0) })
          )
          .toggleStyle(.checkbox)
          .controlSize(.small)
          .help(
            "When on, \(app.name) runs in the background and its window is hidden whenever it pops up. Needs Accessibility access for Kitbag."
          )
        }
        if installed {
          Button("Menu bar icon…") { AppMenuIcon.openSystemSettings() }
            .controlSize(.small)
            .help("Manage \(app.name)'s menu bar icon in System Settings")
        }
      }
    }
  }
}
