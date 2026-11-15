import AppKit
import KitbagCore
import SwiftUI

/// The Dev Tools tab: two quick tools on top, then Docker and the databases as switchable services.
struct DevToolsView: View {
  @ObservedObject var model: DevToolsModel
  @ObservedObject var services: ServicesModel
  @ObservedObject var versions: VersionsModel

  var body: some View {
    VStack(spacing: 12) {
      HStack(spacing: 10) {
        toolTile("Pick Color", symbol: "eyedropper", tint: .pink, action: model.pickColor)
        toolTile("Measure", symbol: "ruler", tint: .orange, action: model.measure)
      }
      if services.dockerReady { ServicesCard(model: services, copy: model.copy) }
      VersionsCard(model: versions)
    }
    .onAppear { Task { await versions.refresh() } }
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

/// A self-contained card in Settings: icon, title, subtitle and actions on top, details below.
struct SettingsBlock<Icon: View, Trailing: View, Content: View>: View {
  let title: String
  let subtitle: String
  @ViewBuilder var icon: Icon
  @ViewBuilder var trailing: Trailing
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        icon
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.headline)
          Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer(minLength: 8)
        trailing
      }
      .padding(12)
      content
    }
    .frame(maxWidth: .infinity)
    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
  }
}

/// A padded sub-section inside a block, set off by a divider.
struct BlockSection<Content: View>: View {
  var title: LocalizedStringKey?
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Divider()
      if let title {
        Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).tracking(0.5)
      }
      content
    }
    .padding(.horizontal, 12).padding(.bottom, 12)
  }
}

/// Settings for the Dev Tools tab: one block each for Node.js, Python, Docker, MongoDB, PostgreSQL.
struct DevToolsSettingsView: View {
  @ObservedObject var model: ServicesModel
  @ObservedObject var versions: VersionsModel

  var body: some View {
    VStack(spacing: 14) {
      ForEach(VersionsModel.Kind.allCases) { RuntimeBlock(kind: $0, model: versions) }
      dockerBlock
      ForEach(ServicesModel.services) { serviceBlock($0) }
      if let n = model.notice { Text(n).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
    }
    .padding(.vertical, 4)
    .listRowBackground(Color.clear)
    .listRowInsets(EdgeInsets())
    .onAppear {
      Task { await versions.refresh() }
      Task { await model.refresh() }
    }
  }

  // MARK: Docker and databases

  private var dockerBlock: some View {
    SettingsBlock(
      title: "Docker", subtitle: String(localized: "Container engine"),
      icon: { ServiceIcon(id: "docker", symbol: "shippingbox.fill", tint: .blue, size: 36) },
      trailing: { actions(id: "docker", installed: model.dockerInstalled, installLabel: "Install",
        install: { model.installDocker() }, uninstall: { model.uninstallDocker() }) },
      content: {
        // Docker's icon is drawn by an Electron tray with no saved identity, so no setting from
        // outside can hide it; macOS's own per-app switch in System Settings is the way.
        BlockSection {
          HStack(spacing: 8) {
            Text("Docker's own menu bar icon").font(.callout)
            Spacer()
            Button("Manage in System Settings") { AppMenuIcon.openSystemSettings() }.controlSize(.small)
          }
        }
      })
  }

  private func serviceBlock(_ s: ServicesModel.Service) -> some View {
    SettingsBlock(
      title: s.title, subtitle: s.subtitle,
      icon: { ServiceIcon(id: s.id, symbol: s.symbol, tint: s.tint, size: 36) },
      trailing: { actions(id: s.id, installed: model.isInstalled(s),
        installLabel: model.daemonReady ? "Install" : "Set up",
        install: { model.install(s) }, uninstall: { model.uninstall(s) }) },
      content: { EmptyView() })
  }

  @ViewBuilder private func actions(
    id: String, installed: Bool, installLabel: LocalizedStringKey,
    install: @escaping () -> Void, uninstall: @escaping () -> Void
  ) -> some View {
    switch model.phase(id) {
    case .installing: working("Installing…")
    case .uninstalling: working("Uninstalling…")
    default:
      if installed {
        Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout)
        Button("Uninstall", role: .destructive, action: uninstall).controlSize(.small).disabled(model.isBusy)
      } else {
        Button(installLabel, action: install).controlSize(.small).disabled(model.isBusy)
      }
    }
  }

  @ViewBuilder private func working(_ text: LocalizedStringKey) -> some View {
    Text(text).font(.caption).foregroundStyle(.secondary)
    ProgressView().controlSize(.small)
  }
}

/// One runtime (Node.js or Python): the manager's state, a field for any version, and the
/// installed versions with their default switch.
struct RuntimeBlock: View {
  let kind: VersionsModel.Kind
  @ObservedObject var model: VersionsModel

  private var s: VersionsModel.State { model.state(kind) }
  private var working: Bool { model.busy?.hasPrefix(kind.rawValue) == true }

  var body: some View {
    SettingsBlock(
      title: kind.title,
      subtitle: s.installed
        ? "\(kind.manager) · " + String(localized: "Default: \(s.defaultVersion ?? String(localized: "not set"))")
        : String(localized: "\(kind.manager) isn't installed"),
      icon: {
        ServiceIcon(id: kind.rawValue, symbol: kind.symbol, tint: kind.tint, size: 36)
      },
      trailing: {
        if working { ProgressView().controlSize(.small) }
        if s.installed {
          Button("Uninstall \(kind.manager)", role: .destructive) { model.uninstallManager(kind) }
            .controlSize(.small).disabled(model.isBusy)
        } else {
          Button("Install \(kind.manager)") { model.installManager(kind) }
            .controlSize(.small).disabled(model.isBusy)
        }
      },
      content: {
        if s.installed {
          BlockSection(title: "INSTALL A VERSION") {
            InstallField(kind: kind, model: model)
          }
          BlockSection(title: "INSTALLED VERSIONS") {
            if s.versions.isEmpty {
              Text("None yet").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(s.versions.reversed(), id: \.self) { v in versionRow(v) }
          }
        }
      })
  }

  private func versionRow(_ v: String) -> some View {
    let isDefault = v == s.defaultVersion
    return HStack(spacing: 8) {
      Text(v).font(.callout.monospacedDigit())
      if isDefault {
        Text("Default").font(.caption2.weight(.semibold)).foregroundStyle(.green)
          .padding(.horizontal, 6).padding(.vertical, 2).background(.green.opacity(0.15), in: Capsule())
      }
      Spacer()
      if !isDefault {
        Button("Set default") { model.setDefault(kind, v) }.controlSize(.small).disabled(model.isBusy)
      }
      Button { model.remove(kind, v) } label: { Image(systemName: "trash") }
        .buttonStyle(.borderless).foregroundStyle(.red).help("Remove").disabled(model.isBusy)
        .accessibilityLabel("Remove \(v)")
    }
  }
}

/// Quick switch for the global default Node.js / Python version. Everything else (installing
/// managers and versions) lives in Settings.
struct VersionsCard: View {
  @ObservedObject var model: VersionsModel

  private var kinds: [VersionsModel.Kind] {
    VersionsModel.Kind.allCases.filter { !model.state($0).versions.isEmpty }
  }

  var body: some View {
    if !kinds.isEmpty {
      VStack(spacing: 0) {
        HStack {
          Text("DEFAULT VERSIONS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).tracking(0.6)
          Spacer()
        }
        .padding(.horizontal, 4).padding(.bottom, 8)
        ForEach(Array(kinds.enumerated()), id: \.element) { i, k in
          if i > 0 { Divider().padding(.vertical, 8) }
          row(k)
        }
      }
      .card()
    }
  }

  private func row(_ k: VersionsModel.Kind) -> some View {
    let s = model.state(k)
    return HStack(spacing: 10) {
      ServiceIcon(id: k.rawValue, symbol: k.symbol, tint: k.tint, size: 30)
      Text(k.title).font(.callout.weight(.medium))
      Spacer(minLength: 6)
      if model.isBusy { ProgressView().controlSize(.small) }
      Menu {
        ForEach(s.versions.reversed(), id: \.self) { v in
          Button {
            model.setDefault(k, v)
          } label: {
            if v == s.defaultVersion { Label(v, systemImage: "checkmark") } else { Text(v) }
          }
        }
      } label: {
        Text(s.defaultVersion ?? String(localized: "Not set"))
      }
      .menuStyle(.borderlessButton).fixedSize().disabled(model.isBusy)
    }
  }
}

/// Type or pick a version, then press Install. Picking from the menu only fills the field.
struct InstallField: View {
  let kind: VersionsModel.Kind
  @ObservedObject var model: VersionsModel

  private var text: Binding<String> {
    Binding(get: { model.drafts[kind] ?? "" }, set: { model.drafts[kind] = $0 })
  }
  private var isEmpty: Bool { text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty }

  var body: some View {
    HStack(spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: "number").font(.caption).foregroundStyle(.tertiary)
        TextField(
          "", text: text,
          prompt: Text(kind == .node ? "Version, e.g. 20.11.0" : "Version, e.g. 3.12.4")
        )
        .textFieldStyle(.plain).labelsHidden().onSubmit(go)
        if !isEmpty {
          Button { text.wrappedValue = "" } label: { Image(systemName: "xmark.circle.fill") }
            .buttonStyle(.plain).foregroundStyle(.tertiary).help("Clear")
        }
        Divider().frame(height: 16)
        suggestions
      }
      .padding(.horizontal, 10).padding(.vertical, 7)
      .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))

      Button(action: go) {
        Label("Install", systemImage: "arrow.down.circle.fill")
      }
      .buttonStyle(.borderedProminent).controlSize(.regular)
      .disabled(model.isBusy || isEmpty)
    }
  }

  /// Recent releases; choosing one fills the field and does nothing else.
  private var suggestions: some View {
    Menu {
      let list = model.state(kind).available
      if list.isEmpty {
        Text("Loading versions…")
      } else {
        ForEach(list, id: \.self) { v in
          Button(v == "node" ? "Latest release" : v) { text.wrappedValue = v == "node" ? "latest" : v }
        }
      }
    } label: {
      Text("Recent")
    }
    .menuStyle(.borderlessButton).fixedSize()
    .onAppear { model.loadAvailable(kind) }
  }

  private func go() {
    guard !model.isBusy, !isEmpty else { return }
    model.install(kind, version: text.wrappedValue)
    text.wrappedValue = ""
  }
}
