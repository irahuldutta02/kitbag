import KitbagCore
import SwiftUI

struct AppsView: View {
  @ObservedObject var model: AppsModel

  var body: some View {
    let groups = model.groupedVisible
    VStack(spacing: 10) {
      if model.shortcut != nil, !model.shortcutWorks {
        Label("Shortcut is taken by another app.", systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(KitbagUI.warning)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      if groups.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "square.grid.2x2")
            .font(.system(size: 24, weight: .light))
            .foregroundStyle(.tertiary)
          Text("No apps selected")
            .font(.callout.weight(.semibold))
          Text("Choose which companion apps to manage in Settings ▸ Quick Toggle.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .card()
      } else {
        ForEach(groups) { group in
          VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
              Image(systemName: group.symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
              SectionEyebrow(group.title)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)

            ForEach(Array(group.switches.enumerated()), id: \.element.id) { i, sw in
              if i > 0 { Divider().opacity(0.45).padding(.vertical, 5) }
              switchRow(sw)
            }
            ForEach(Array(group.apps.enumerated()), id: \.element.id) { i, app in
              if i > 0 || !group.switches.isEmpty { Divider().opacity(0.45).padding(.vertical, 5) }
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

      if let s = model.shortcut {
        HStack(spacing: 6) {
          Text("Open Quick Toggle")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          KeycapBadge(s.display)
        }
        .padding(.horizontal, 4)
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
      Toggle(sw.name, isOn: Binding(get: { sw.isOn }, set: { model.setSwitch(sw, on: $0) }))
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

/// Pick which apps the Apps tab lists, configure its global shortcut, and open macOS's menu bar list.
struct AppsSettingsView: View {
  @ObservedObject var model: AppsModel

  var body: some View {
    Section {
      ShortcutRecorderRow(
        "Open Quick Toggle",
        current: model.shortcut,
        defaultShortcut: AppsModel.defaultShortcut,
        onPause: { model.pauseHotKey($0) },
        onSet: { model.setShortcut($0) }
      )
    } header: {
      Text("Shortcut")
    } footer: {
      Text("Press it anywhere to open Quick Toggle from the menu bar.")
    }

    ForEach(AppCategory.allCases) { category in
      let apps = AppsModel.catalog.filter { $0.category == category }
      if !apps.isEmpty {
        Section {
          ForEach(apps) { app in
            appRow(app)
          }
        } header: {
          Label(category.name, systemImage: category.symbol)
        }
      }
    }
  }

  /// The app and its switch on top, its options underneath, so every row lines up the same way.
  /// Apps that aren't installed are only listed, with no switch or options.
  private func appRow(_ app: ManagedApp) -> some View {
    let installed = model.installed.contains(app.id)
    let on = model.running.contains(app.id)
    let iconSize: CGFloat = 28
    let spacing: CGFloat = 10
    return VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: spacing) {
        Image(nsImage: model.icon(app, size: iconSize))
          .resizable()
          .frame(width: iconSize, height: iconSize)
          .opacity(installed ? 1 : 0.4)
        VStack(alignment: .leading, spacing: 1) {
          Text(app.name)
          Text(installed ? (on ? "Running" : "Stopped") : "Not installed")
            .font(.caption)
            .foregroundStyle(on ? KitbagUI.success : .secondary)
        }
        Spacer()
        if model.busy.contains(app.id) { ProgressView().controlSize(.small) }
        if installed {
          Toggle(app.name, isOn: Binding(get: { on }, set: { model.set(app, on: $0) }))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(model.busy.contains(app.id))
        }
      }
      if installed {
        appOptions(app).padding(.leading, iconSize + spacing)
      }
    }
    .padding(.vertical, 2)
  }

  private func appOptions(_ app: ManagedApp) -> some View {
    HStack(spacing: 16) {
      Toggle(
        "Show in Quick Toggle",
        isOn: Binding(get: { !model.hidden.contains(app.id) }, set: { model.setShown(app, $0) })
      )
      if app.background {
        Toggle(
          "Keep window hidden",
          isOn: Binding(
            get: { !model.windowAllowed.contains(app.id) },
            set: { model.setWindowAllowed(app, !$0) })
        )
        .help(
          "When on, \(app.name) runs in the background and its window is hidden whenever it pops up. Needs Accessibility access for Kitbag."
        )
      }
      Spacer(minLength: 0)
      if app.category != .utilities {
        Button("Menu bar icon…") { AppMenuIcon.openSystemSettings() }
          .help("Manage \(app.name)'s menu bar icon in System Settings")
      }
    }
    .toggleStyle(.checkbox)
    .controlSize(.small)
  }
}
