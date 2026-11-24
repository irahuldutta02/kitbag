import AppKit
import KitbagCore
import SwiftUI

/// The Dev Tools tab: two quick tools on top, then Docker/databases and runtime defaults.
struct DevToolsView: View {
  @ObservedObject var model: DevToolsModel
  @ObservedObject var services: ServicesModel
  @ObservedObject var versions: VersionsModel

  var body: some View {
    VStack(spacing: 10) {
      HStack(spacing: 8) {
        toolTile(
          "Pick Color", subtitle: "Eyedropper", symbol: "eyedropper", tint: .pink,
          action: model.pickColor)
        toolTile(
          "Measure", subtitle: "Screen ruler", symbol: "ruler", tint: .orange,
          action: model.measure)
        toolTile(
          "Ports", subtitle: "Port manager", symbol: "network", tint: .teal,
          action: { NotificationCenter.default.post(name: .kitbagOpenPopup, object: "portmanager") })
      }
      if services.dockerReady { ServicesCard(model: services, copy: model.copy) }
      VersionsCard(model: versions)
    }
    .onAppear { Task { await versions.refresh() } }
  }

  private func toolTile(
    _ title: LocalizedStringKey,
    subtitle: LocalizedStringKey,
    symbol: String,
    tint: Color,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 6) {
        Image(systemName: symbol)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 34, height: 34)
          .background(tint.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        VStack(spacing: 1) {
          Text(title).font(.callout.weight(.semibold)).lineLimit(1)
          Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity)
      .card(padding: 10)
      .hoverHighlight(cornerRadius: KitbagUI.cardRadius, tint: tint)
      .contentShape(RoundedRectangle(cornerRadius: KitbagUI.cardRadius, style: .continuous))
    }
    .buttonStyle(PressableStyle())
  }
}

/// A label, a value, and a copy button with crisp inline confirmation.
struct CopyRow: View {
  let title: LocalizedStringKey
  let value: String
  let copy: (String) -> Void
  @StateObject private var copied = UIBox(false)

  var body: some View {
    HStack(spacing: 6) {
      Text(title)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .frame(width: 44, alignment: .leading)
      Text(value)
        .font(.callout.monospacedDigit())
        .lineLimit(1)
        .textSelection(.enabled)
      Spacer(minLength: 4)
      Button {
        copy(value)
        withAnimation(.easeOut(duration: 0.14)) { copied.value = true }
        Task {
          try? await Task.sleep(nanoseconds: 1_200_000_000)
          withAnimation(.easeOut(duration: 0.14)) { copied.value = false }
        }
      } label: {
        Image(systemName: copied.value ? "checkmark" : "doc.on.doc")
          .font(.system(size: 11.5, weight: .medium))
          .foregroundStyle(copied.value ? KitbagUI.success : .secondary)
          .frame(width: 22, height: 22)
          .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
      }
      .buttonStyle(.plain)
      .hoverHighlight(cornerRadius: 6)
      .help(copied.value ? "Copied" : "Copy")
      .accessibilityLabel("Copy \(value)")
    }
  }
}

/// Docker and the databases: a switch each, live status, and one-tap helpers.
struct ServicesCard: View {
  @ObservedObject var model: ServicesModel
  let copy: (String) -> Void
  @StateObject private var copiedID = UIBox<String?>(nil)

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        SectionEyebrow("Services")
        Spacer()
      }
      .padding(.horizontal, 4)
      .padding(.bottom, 7)

      dockerRow
      ForEach(ServicesModel.services.filter(model.serviceReady)) { s in
        Divider().opacity(0.45).padding(.vertical, 6)
        serviceRow(s)
      }
      if let n = model.notice {
        Text(n)
          .font(.caption)
          .foregroundStyle(KitbagUI.danger)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 8)
      }
    }
    .card(padding: 11)
  }

  private var dockerRow: some View {
    let st = status("docker", running: model.daemonReady, detail: "Engine running")
    return row(
      title: "Docker", symbol: "shippingbox.fill", tint: .blue, id: "docker",
      subtitle: st, active: model.daemonReady && model.phase("docker") == nil
    ) {
      Button {
        model.openDocker()
      } label: {
        Image(systemName: "arrow.up.forward.app")
          .font(.system(size: 12.5))
          .foregroundStyle(.secondary)
          .frame(width: 24, height: 24)
          .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
      }
      .buttonStyle(.plain)
      .hoverHighlight(cornerRadius: 6)
      .help("Open Docker Desktop")
    }
  }

  private func serviceRow(_ s: ServicesModel.Service) -> some View {
    let running = model.isOn(s.id)
    let st = status(
      s.id, running: model.containers[s.container] == true, detail: "Running · \(s.endpoint)")
    let justCopied = copiedID.value == s.id
    return row(
      title: s.title, symbol: s.symbol, tint: s.tint, id: s.id,
      subtitle: st, active: model.containers[s.container] == true && model.phase(s.id) == nil
    ) {
      if running {
        Button {
          copy(s.connection)
          withAnimation { copiedID.value = s.id }
          Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if copiedID.value == s.id { withAnimation { copiedID.value = nil } }
          }
        } label: {
          Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(justCopied ? KitbagUI.success : .secondary)
            .frame(width: 24, height: 24)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 6)
        .help(justCopied ? "Copied connection string" : "Copy connection string")
      }
    }
  }

  private func status(_ id: String, running: Bool, detail: String) -> (String, Color) {
    switch model.phase(id) {
    case .starting: return ("Starting…", KitbagUI.warning)
    case .stopping: return ("Stopping…", KitbagUI.warning)
    default: return running ? (detail, KitbagUI.success) : ("Stopped", .secondary)
    }
  }

  private func row<Extra: View>(
    title: String, symbol: String, tint: Color, id: String, subtitle: (String, Color),
    active: Bool, @ViewBuilder extra: () -> Extra
  ) -> some View {
    HStack(spacing: 10) {
      ServiceIcon(id: id, symbol: symbol, tint: tint, size: 29)
      VStack(alignment: .leading, spacing: 1.5) {
        Text(title).font(.callout.weight(.medium))
        HStack(spacing: 4) {
          StatusDot(color: subtitle.1, active: active, size: 5.5)
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
            if id == "docker" {
              model.toggleDocker(on)
            } else if let s = ServicesModel.services.first(where: { $0.id == id }) {
              model.toggle(s, on)
            }
          })
      )
      .labelsHidden()
      .toggleStyle(.switch)
      .controlSize(.small)
      .disabled(model.isBusy)
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 2)
    .hoverHighlight(cornerRadius: 8)
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
    .background(
      Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
    )
  }
}

/// A padded sub-section inside a block, set off by a divider.
struct BlockSection<Content: View>: View {
  var title: LocalizedStringKey?
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Divider().opacity(0.6)
      if let title {
        SectionEyebrow(title)
      }
      content
    }
    .padding(.horizontal, 12)
    .padding(.bottom, 12)
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
      if let n = model.notice {
        Text(n).font(.caption).foregroundStyle(KitbagUI.danger).frame(
          maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.vertical, 4)
    .listRowBackground(Color.clear)
    .listRowInsets(EdgeInsets())
    .onAppear {
      Task { await versions.refresh() }
      Task { await model.refresh() }
    }
  }

  private var dockerBlock: some View {
    SettingsBlock(
      title: "Docker", subtitle: String(localized: "Container engine"),
      icon: { ServiceIcon(id: "docker", symbol: "shippingbox.fill", tint: .blue, size: 36) },
      trailing: {
        actions(
          id: "docker", installed: model.dockerInstalled, installLabel: "Install",
          install: { model.installDocker() }, uninstall: { model.uninstallDocker() })
      },
      content: {
        BlockSection {
          HStack(spacing: 8) {
            Text("Docker's own menu bar icon").font(.callout)
            Spacer()
            Button("Manage in System Settings") { AppMenuIcon.openSystemSettings() }
              .controlSize(.small)
          }
        }
      })
  }

  private func serviceBlock(_ s: ServicesModel.Service) -> some View {
    SettingsBlock(
      title: s.title, subtitle: s.subtitle,
      icon: { ServiceIcon(id: s.id, symbol: s.symbol, tint: s.tint, size: 36) },
      trailing: {
        actions(
          id: s.id, installed: model.isInstalled(s),
          installLabel: model.daemonReady ? "Install" : "Set up",
          install: { model.install(s) }, uninstall: { model.uninstall(s) })
      },
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
        Label("Installed", systemImage: "checkmark.circle.fill")
          .foregroundStyle(KitbagUI.success)
          .font(.callout)
        Button("Uninstall", role: .destructive, action: uninstall)
          .controlSize(.small)
          .disabled(model.isBusy)
      } else {
        Button(installLabel, action: install)
          .controlSize(.small)
          .disabled(model.isBusy)
      }
    }
  }

  @ViewBuilder private func working(_ text: LocalizedStringKey) -> some View {
    Text(text).font(.caption).foregroundStyle(.secondary)
    ProgressView().controlSize(.small)
  }
}

struct RuntimeBlock: View {
  let kind: VersionsModel.Kind
  @ObservedObject var model: VersionsModel

  private var s: VersionsModel.State { model.state(kind) }
  private var working: Bool { model.busy?.hasPrefix(kind.rawValue) == true }

  var body: some View {
    SettingsBlock(
      title: kind.title,
      subtitle: s.installed
        ? "\(kind.manager) · "
          + String(localized: "Default: \(s.defaultVersion ?? String(localized: "not set"))")
        : String(localized: "\(kind.manager) isn't installed"),
      icon: {
        ServiceIcon(id: kind.rawValue, symbol: kind.symbol, tint: kind.tint, size: 36)
      },
      trailing: {
        if working { ProgressView().controlSize(.small) }
        if s.installed {
          Button("Uninstall \(kind.manager)", role: .destructive) { model.uninstallManager(kind) }
            .controlSize(.small)
            .disabled(model.isBusy)
        } else {
          Button("Install \(kind.manager)") { model.installManager(kind) }
            .controlSize(.small)
            .disabled(model.isBusy)
        }
      },
      content: {
        if s.installed {
          BlockSection(title: "Install a Version") {
            InstallField(kind: kind, model: model)
          }
          BlockSection(title: "Installed Versions") {
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
        Text("Default")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(KitbagUI.success)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(KitbagUI.success.opacity(0.15), in: Capsule())
      }
      Spacer()
      if !isDefault {
        Button("Set default") { model.setDefault(kind, v) }
          .controlSize(.small)
          .disabled(model.isBusy)
      }
      Button {
        model.remove(kind, v)
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .foregroundStyle(KitbagUI.danger)
      .help("Remove")
      .disabled(model.isBusy)
      .accessibilityLabel("Remove \(v)")
    }
  }
}

/// Quick switch for the global default Node.js / Python version.
struct VersionsCard: View {
  @ObservedObject var model: VersionsModel

  private var kinds: [VersionsModel.Kind] {
    VersionsModel.Kind.allCases.filter { !model.state($0).versions.isEmpty }
  }

  var body: some View {
    if !kinds.isEmpty {
      VStack(spacing: 0) {
        HStack {
          SectionEyebrow("Default Runtimes")
          Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 7)

        ForEach(Array(kinds.enumerated()), id: \.element) { i, k in
          if i > 0 { Divider().opacity(0.45).padding(.vertical, 6) }
          row(k)
        }
      }
      .card(padding: 11)
    }
  }

  private func row(_ k: VersionsModel.Kind) -> some View {
    let s = model.state(k)
    return HStack(spacing: 10) {
      ServiceIcon(id: k.rawValue, symbol: k.symbol, tint: k.tint, size: 29)
      Text(k.title).font(.callout.weight(.medium))
      Spacer(minLength: 6)
      if model.isBusy { ProgressView().controlSize(.small) }
      Menu {
        ForEach(s.versions.reversed(), id: \.self) { v in
          Button {
            model.setDefault(k, v)
          } label: {
            if v == s.defaultVersion {
              Label(v, systemImage: "checkmark")
            } else {
              Text(v)
            }
          }
        }
      } label: {
        HStack(spacing: 4) {
          Text(s.defaultVersion ?? String(localized: "Not set"))
            .font(.caption.weight(.semibold).monospacedDigit())
          Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.07), in: Capsule())
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .disabled(model.isBusy)
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 2)
    .hoverHighlight(cornerRadius: 8)
  }
}

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
        .textFieldStyle(.plain)
        .labelsHidden()
        .onSubmit(go)
        if !isEmpty {
          Button {
            text.wrappedValue = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
          }
          .buttonStyle(.plain)
          .foregroundStyle(.tertiary)
          .help("Clear")
        }
        Divider().frame(height: 16)
        suggestions
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(
        Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
      )

      Button(action: go) {
        Label("Install", systemImage: "arrow.down.circle.fill")
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.regular)
      .disabled(model.isBusy || isEmpty)
    }
  }

  private var suggestions: some View {
    Menu {
      let list = model.state(kind).available
      if list.isEmpty {
        Text("Loading versions…")
      } else {
        ForEach(list, id: \.self) { v in
          Button(v == "node" ? "Latest release" : v) {
            text.wrappedValue = v == "node" ? "latest" : v
          }
        }
      }
    } label: {
      Text("Recent")
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .onAppear { model.loadAvailable(kind) }
  }

  private func go() {
    guard !model.isBusy, !isEmpty else { return }
    model.install(kind, version: text.wrappedValue)
    text.wrappedValue = ""
  }
}
