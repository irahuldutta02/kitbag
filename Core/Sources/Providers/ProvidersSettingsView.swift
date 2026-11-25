import AppKit
import SwiftUI

/// Settings panel for the AI CLIs: a provider list on the left, details and actions on the right.
public struct ProvidersSettingsView: View {
  @ObservedObject var manager: ProviderManager
  @ObservedObject private var terminal = TerminalModel.shared
  @StateObject private var sel = UIBox<AIProviderID>(.codex)
  private var selected: AIProviderID { sel.value }

  public init(manager: ProviderManager) { self.manager = manager }

  public var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      HStack(spacing: 0) {
        list.frame(width: 250)
        Divider()
        ProviderDetail(manager: manager, id: selected)
          .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .frame(minHeight: 420)
      .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .onAppear { manager.refreshAll() }
  }

  private var header: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text("AI Agent Providers").font(.title3.weight(.semibold))
        Text("AI command line tools Kitbag can use, for example to clean up dictation.")
          .font(.callout).foregroundStyle(.secondary)
      }
      Spacer()
      if let d = manager.lastChecked {
        Text("Checked \(d, format: .relative(presentation: .named))")
          .font(.caption).foregroundStyle(.secondary)
      }
      Button {
        manager.refreshAll()
      } label: {
        if manager.refreshing {
          ProgressView().controlSize(.small)
        } else {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
      }
      .controlSize(.small)
      .disabled(manager.refreshing)
      Button {
        terminal.isOpen = true
      } label: {
        Label("Show Logs", systemImage: "terminal")
      }
      .controlSize(.small)
    }
  }

  private var list: some View {
    VStack(spacing: 2) {
      ForEach(AIProviderID.allCases) { id in
        let s = manager.state(id)
        Button {
          sel.value = id
        } label: {
          HStack(spacing: 10) {
            ProviderGlyph(id: id, size: 30)
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: 6) {
                Text(id.displayName).font(.callout.weight(.semibold))
                if let v = s.version {
                  Text(v).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
                }
              }
              Text(s.authSummary)
                .font(.caption)
                .foregroundStyle(s.authenticated ? KitbagUI.success : .secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            Toggle(
              "Enabled",
              isOn: Binding(
                get: { manager.isEnabled(id) }, set: { manager.setEnabled(id, $0) })
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
          }
          .padding(.horizontal, 8).padding(.vertical, 7)
          .background(
            selected == id ? Color.accentColor.opacity(0.16) : .clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
          )
          .hoverHighlight(cornerRadius: 10)
          .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
      }
      Spacer(minLength: 0)
    }
    .padding(8)
  }
}

/// Tile with the provider's real logo.
struct ProviderGlyph: View {
  let id: AIProviderID
  var size: CGFloat = 30
  var body: some View { ProviderLogo(id: id, size: size) }
}

private struct ProviderDetail: View {
  @ObservedObject var manager: ProviderManager
  let id: AIProviderID
  @ObservedObject private var terminal = TerminalModel.shared
  @StateObject private var draftBox = UIBox("")
  private var draft: String {
    get { draftBox.value }
    nonmutating set { draftBox.value = newValue }
  }

  private var state: ProviderState { manager.state(id) }
  private var busy: Bool { state.busyAction != nil }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        title
        if let e = state.error { errorBanner(e) }
        section("Status") { status }
        section("Setup") { setup }
        if state.installed { section("Account") { account } }
      }
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .onAppear { draft = manager.customPath(for: id) }
    .onChange(of: id) { _, new in draft = manager.customPath(for: new) }
  }

  private var title: some View {
    HStack(spacing: 12) {
      ProviderGlyph(id: id, size: 40)
      VStack(alignment: .leading, spacing: 2) {
        Text(id.displayName).font(.title3.weight(.semibold))
        if let v = state.version {
          Text(v).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
        }
      }
      Spacer()
      Button { manager.refresh(id) } label: { Image(systemName: "arrow.clockwise") }
        .buttonStyle(.borderless)
        .help("Refresh \(id.displayName)")
        .disabled(busy)
    }
  }

  private func section<C: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> C)
    -> some View
  {
    VStack(alignment: .leading, spacing: 8) {
      SectionEyebrow(title)
      VStack(alignment: .leading, spacing: 10) { content() }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
  }

  private var status: some View {
    HStack(alignment: .top, spacing: 8) {
      StatusDot(
        color: !state.installed ? KitbagUI.danger : (state.authenticated ? KitbagUI.success : KitbagUI.warning),
        active: busy, size: 8
      )
      .padding(.top, 5)
      VStack(alignment: .leading, spacing: 2) {
        Text(state.authSummary).font(.callout.weight(.medium))
        if let d = state.accountDetail { Text(d).font(.caption).foregroundStyle(.secondary) }
      }
    }
  }

  @ViewBuilder private var setup: some View {
    HStack {
      Label(
        state.installed ? "Installed" : "Not installed",
        systemImage: state.installed ? "checkmark.circle.fill" : "xmark.circle"
      )
      .foregroundStyle(state.installed ? KitbagUI.success : .secondary)
      .font(.callout)
      Spacer()
      if let b = state.busyAction {
        HStack(spacing: 6) {
          ProgressView().controlSize(.small)
          Text(b).font(.callout).foregroundStyle(.secondary)
        }
      } else if state.installed {
        Button("Update") { manager.update(id) }.controlSize(.small)
        Button("Reinstall") { manager.reinstall(id) }.controlSize(.small)
      } else {
        Button("Install") { manager.install(id) }.controlSize(.small).buttonStyle(.borderedProminent)
      }
    }
    HStack(spacing: 6) {
      Text("Binary path").font(.callout)
      TextField(state.binaryPath ?? id.binaryName, text: $draftBox.value)
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 12, design: .monospaced))
        .onSubmit { manager.setCustomPath(draft, for: id) }
      Button("Browse…") { browse() }.controlSize(.small)
      if !manager.customPath(for: id).isEmpty {
        Button("Reset") {
          draft = ""
          manager.setCustomPath("", for: id)
        }
        .controlSize(.small)
      }
    }
  }

  @ViewBuilder private var account: some View {
    HStack {
      Label(
        state.authenticated ? "Signed in" : "Not signed in",
        systemImage: state.authenticated ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.xmark"
      )
      .foregroundStyle(state.authenticated ? KitbagUI.success : .secondary)
      .font(.callout)
      Spacer()
      if state.authenticated {
        Button("Change account") { manager.changeAccount(id) }.controlSize(.small).disabled(busy)
        Button("Sign out", role: .destructive) { manager.signOut(id) }.controlSize(.small).disabled(busy)
      } else {
        Button("Sign in") { manager.signIn(id) }
          .controlSize(.small).buttonStyle(.borderedProminent).disabled(busy)
      }
    }
    if id == .antigravity {
      Text("Antigravity signs in inside Terminal. Type /logout there to switch accounts.")
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  private func errorBanner(_ message: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(KitbagUI.danger)
      Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 8)
      Button("View Terminal") { terminal.isOpen = true }.controlSize(.small)
      Button("Dismiss") { manager.dismissError(id) }.controlSize(.small)
    }
    .padding(10)
    .background(KitbagUI.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  private func browse() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.showsHiddenFiles = true
    if panel.runModal() == .OK, let url = panel.url {
      draft = url.path
      manager.setCustomPath(url.path, for: id)
    }
  }
}
