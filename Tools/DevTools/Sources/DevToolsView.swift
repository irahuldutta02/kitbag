import AppKit
import KitbagCore
import SwiftUI

/// The Dev Tools tab: two quick tools on top, then Docker and the databases as switchable services.
struct DevToolsView: View {
  @ObservedObject var model: DevToolsModel
  @ObservedObject var services: ServicesModel

  var body: some View {
    VStack(spacing: 12) {
      HStack(spacing: 10) {
        toolTile("Pick Color", symbol: "eyedropper", tint: .pink, action: model.pickColor)
        toolTile("Measure", symbol: "ruler", tint: .orange, action: model.measure)
      }
      if services.dockerReady { ServicesCard(model: services, copy: model.copy) }
    }
  }

  private func toolTile(_ title: LocalizedStringKey, symbol: String, tint: Color, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      VStack(spacing: 8) {
        Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
          .frame(width: 38, height: 38)
          .background(tint.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        Text(title).font(.callout.weight(.medium))
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 14)
      .card()
      .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(PressableStyle())
  }
}

/// A label, a value and a copy button.
struct CopyRow: View {
  let title: LocalizedStringKey
  let value: String
  let copy: (String) -> Void

  var body: some View {
    HStack {
      Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
      Text(value).font(.callout.monospacedDigit()).textSelection(.enabled)
      Spacer(minLength: 4)
      Button {
        copy(value)
      } label: {
        Image(systemName: "doc.on.doc")
      }
      .buttonStyle(.borderless).help("Copy")
      .accessibilityLabel("Copy \(value)")
    }
  }
}

/// Docker and the databases: a switch each, live status, and one-tap helpers. A row appears only
/// once that piece is fully installed and set up.
struct ServicesCard: View {
  @ObservedObject var model: ServicesModel
  let copy: (String) -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("SERVICES").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).tracking(0.6)
        Spacer()
      }
      .padding(.horizontal, 4).padding(.bottom, 8)
      dockerRow
      ForEach(ServicesModel.services.filter(model.serviceReady)) { s in
        Divider().padding(.vertical, 8)
        serviceRow(s)
      }
      if let n = model.notice {
        Text(n).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 8)
      }
    }
    .card()
  }

  // MARK: Rows

  private var dockerRow: some View {
    row(
      title: "Docker", symbol: "shippingbox.fill", tint: .blue, id: "docker",
      subtitle: status("docker", running: model.daemonReady, detail: "Engine running")
    ) {
      Button { model.openDocker() } label: { Image(systemName: "arrow.up.forward.app") }
        .buttonStyle(.borderless).help("Open Docker Desktop")
    }
  }

  private func serviceRow(_ s: ServicesModel.Service) -> some View {
    let running = model.isOn(s.id)
    return row(
      title: s.title, symbol: s.symbol, tint: s.tint, id: s.id,
      subtitle: status(s.id, running: model.containers[s.container] == true, detail: "Running · \(s.endpoint)")
    ) {
      if running {
        Button { copy(s.connection) } label: { Image(systemName: "doc.on.doc") }
          .buttonStyle(.borderless).help("Copy connection string")
      }
    }
  }

  private func status(_ id: String, running: Bool, detail: String) -> (String, Color) {
    switch model.phase(id) {
    case .starting: return ("Starting…", .orange)
    case .stopping: return ("Stopping…", .orange)
    default: return running ? (detail, .green) : ("Stopped", .secondary)
    }
  }

  private func row<Extra: View>(
    title: String, symbol: String, tint: Color, id: String, subtitle: (String, Color),
    @ViewBuilder extra: () -> Extra
  ) -> some View {
    HStack(spacing: 10) {
      ServiceIcon(id: id, symbol: symbol, tint: tint, size: 30)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.callout.weight(.medium))
        HStack(spacing: 5) {
          Circle().fill(subtitle.1).frame(width: 6, height: 6)
          Text(subtitle.0).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
      }
      Spacer(minLength: 6)
      extra()
      if model.phase(id) != nil { ProgressView().controlSize(.small) }
      Toggle(
        title,
        isOn: Binding(
          get: { model.isOn(id) },
          set: { on in
            if id == "docker" { model.toggleDocker(on) }
            else if let s = ServicesModel.services.first(where: { $0.id == id }) { model.toggle(s, on) }
          })
      )
      .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(model.isBusy)
    }
  }
}

struct DevToolsSettingsView: View {
  @ObservedObject var model: ServicesModel

  var body: some View {
    row("Docker", "Container engine", symbol: "shippingbox.fill", tint: .blue, id: "docker",
      installed: model.dockerInstalled, install: { model.installDocker() },
      uninstall: { model.uninstallDocker() })
    .onAppear { Task { await model.refresh() } }
    // Docker's icon is drawn by an Electron tray that has no saved identity, so no setting from
    // outside can hide it; macOS's own per-app switch in System Settings is the way.
    HStack(spacing: 8) {
      Text("Docker's own menu bar icon")
      Spacer()
      Button("Manage in System Settings") { AppMenuIcon.openSystemSettings() }
        .controlSize(.small)
    }
    ForEach(ServicesModel.services) { s in
      row(s.title, s.subtitle, symbol: s.symbol, tint: s.tint, id: s.id,
        installed: model.isInstalled(s), install: { model.install(s) },
        uninstall: { model.uninstall(s) })
    }
    if let n = model.notice { Text(n).font(.caption).foregroundStyle(.red) }
  }

  private func row(
    _ title: String, _ subtitle: String, symbol: String, tint: Color, id: String, installed: Bool,
    install: @escaping () -> Void, uninstall: @escaping () -> Void
  ) -> some View {
    HStack(spacing: 12) {
      ServiceIcon(id: id, symbol: symbol, tint: tint, size: 28)
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
        Text(subtitle).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      switch model.phase(id) {
      case .installing: status("Installing…")
      case .uninstalling: status("Uninstalling…")
      default:
        if installed {
          Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            .font(.callout)
          Button("Uninstall", role: .destructive, action: uninstall).controlSize(.small).disabled(model.isBusy)
        } else {
          Button(id == "docker" || model.daemonReady ? "Install" : "Set up", action: install)
            .controlSize(.small).disabled(model.isBusy)
        }
      }
    }
  }

  @ViewBuilder private func status(_ text: LocalizedStringKey) -> some View {
    Text(text).font(.caption).foregroundStyle(.secondary)
    ProgressView().controlSize(.small)
  }
}
