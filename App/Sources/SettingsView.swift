import AppKit
import KitbagCore
import SwiftUI

@MainActor private final class SettingsNav: ObservableObject {
  @Published var page = "fileshelf"
}

/// The Kitbag window: a sidebar of tools plus Settings, and one page per tool with a header,
/// its on/off switch and its options. The terminal is a drawer opened from the toolbar.
struct SettingsView: View {
  @ObservedObject var manager: ToolManager
  @StateObject private var nav = SettingsNav()
  @ObservedObject private var terminal = TerminalModel.shared

  /// Tools that can be shown: standalone ones, plus integrations that are installed or installable.
  private var tools: [ToolDescriptor] {
    manager.descriptors.filter { $0.showsTab && ($0.requiresApp == nil || manager.isAvailable($0) || $0.brewCask != nil) }
  }

  private var pageTitle: LocalizedStringKey {
    nav.page == "general" ? "Settings" : (tools.first { $0.id == nav.page }?.name ?? "Kitbag")
  }

  var body: some View {
    HStack(spacing: 0) {
      sidebar.frame(width: 236).padding(10)
      detail
    }
    .background { WindowBackdrop() }
    .background {  // ⌘J shows or hides the terminal (the toolbar button does the same)
      Button("") { terminal.isOpen.toggle() }.keyboardShortcut("j", modifiers: .command).opacity(0)
    }
    .overlay(alignment: .bottomTrailing) { terminalButton }
    .ignoresSafeArea()
    .frame(minWidth: 800, minHeight: 540)
    .onAppear { manager.setVisibleTool(Self.toolPage(nav.page)) }
    .onChange(of: nav.page) { _, new in manager.setVisibleTool(Self.toolPage(new)) }
    .onDisappear { manager.setVisibleTool(nil) }
  }

  private static func toolPage(_ page: String) -> String? {
    ["general", "connectivity"].contains(page) ? nil : page
  }

  /// Matches the window's own corner radius, so the sidebar and the button follow its outline.
  static let cornerRadius: CGFloat = 18

  // MARK: Terminal button, bottom right (sits above the drawer while it is open)

  private var terminalButton: some View {
    Button { terminal.isOpen.toggle() } label: {
      Image(systemName: "terminal").font(.system(size: 17, weight: .medium))
        .frame(width: 46, height: 46)
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }
    .buttonStyle(.plain)
    .glass(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous), interactive: true)
    .help("Show or hide the terminal (⌘J)")
    .padding(.trailing, 16)
    .padding(.bottom, terminal.isOpen ? 252 + 16 : 16)
    .animation(.default, value: terminal.isOpen)
  }

  // MARK: Floating glass sidebar, like System Settings on macOS 26

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 2) {
      Spacer().frame(height: 40)  // room for the window buttons
      Text("Tools").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 6)
      ForEach(tools) { d in
        row(id: d.id, title: Text(d.name), tint: Look.tint(d.id)) { ToolIcon(d) }
      }
      row(id: "connectivity", title: Text("Connectivity"), tint: .blue) {
        Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 12, weight: .semibold))
      }
      Spacer(minLength: 12)
      row(id: "general", title: Text("Settings"), tint: .gray) {
        Image(systemName: "gearshape.fill").resizable().scaledToFit().frame(width: 14, height: 14)
      }
    }
    .padding(10)
    .frame(maxHeight: .infinity, alignment: .top)
    .glass(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
  }

  private func row<I: View>(id: String, title: Text, tint: Color, @ViewBuilder icon: () -> I) -> some View {
    let selected = nav.page == id
    return Button { nav.page = id } label: {
      HStack(spacing: 10) {
        Look.tile(icon(), tint, size: 24)
        title
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 8).padding(.vertical, 6)
      .foregroundStyle(selected ? Color.white : Color.primary)
      .background(selected ? Color.accentColor : .clear, in: Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  // MARK: Detail

  private var detail: some View {
    VStack(spacing: 0) {
      Spacer().frame(height: 44)  // title bar area; each page has its own header card
      Form {
        if nav.page == "connectivity" {
          ConnectivityPage()
        } else if nav.page == "general" {
          AppearanceSection()
          LoginItemSection()
        } else if let d = tools.first(where: { $0.id == nav.page }) {
          ToolPage(descriptor: d, manager: manager)
          // Add-ons without a tab of their own (Blip) live on the File Shelf page.
          if d.id == "fileshelf" {
            ForEach(manager.descriptors.filter { !$0.showsTab }) {
              ToolPage(descriptor: $0, manager: manager, addOn: true)
            }
          }
        }
      }
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
      .overlay(alignment: .bottom) { ToastOverlay() }
      .animation(.easeInOut(duration: 0.2), value: Toast.shared.message)
      if terminal.isOpen {
        Divider()
        TerminalView(model: terminal).padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 20).frame(height: 252)
      }
    }
  }
}

/// Shared look: colored icon tiles, per-tool colors and descriptions.
enum Look {
  static func tint(_ id: String) -> Color {
    ["fileshelf": .blue, "systemmonitor": .green, "speedtest": .orange, "devtools": .purple,
      "audio": .pink, "blip": .indigo, "apps": .teal, "dictation": .red][id] ?? .gray
  }

  static let blurb: [String: LocalizedStringKey] = [
    "fileshelf": "A temporary shelf for files while you move them between apps.",
    "systemmonitor": "CPU, memory, storage, network and battery at a glance.",
    "speedtest": "Measure your internet download and upload speed.",
    "devtools": "Pick colors, measure the screen, and run Docker, MongoDB and PostgreSQL.",
    "audio": "Switch your audio input and output devices.",
    "apps": "Turn Google Drive, Proton Drive, Wispr Flow, OpenWhispr and FineTune on or off without opening them.",
    "dictation": "Hold a key, speak, and your words are transcribed, cleaned up and typed into the app in front of you.",
  ]

  /// Tools whose settings view builds its own sections instead of one options section.
  static let ownSections: Set<String> = ["dictation"]

  static let optionsTitle: [String: LocalizedStringKey] = [
    "fileshelf": "Behavior", "systemmonitor": "Monitoring", "devtools": "Runtimes & Services", "apps": "Apps to show", "dictation": "Dictation",
  ]

  static func tile<V: View>(_ icon: V, _ color: Color, size: CGFloat) -> some View {
    icon.foregroundStyle(.white).frame(width: size, height: size)
      .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
  }
}

private struct ToolPage: View {
  let descriptor: ToolDescriptor
  @ObservedObject var manager: ToolManager
  var addOn = false
  @StateObject private var job = Installer()

  private var available: Bool { manager.isAvailable(descriptor) }

  var body: some View {
    if addOn { addOnSection } else { header }
    if !addOn, available, manager.isEnabled(descriptor.id),
      let tool = manager.active[descriptor.id], let settings = tool.makeSettingsView()
    {
      if Look.ownSections.contains(descriptor.id) {
        settings  // lays out its own sections
      } else {
        Section { settings } header: { Text(Look.optionsTitle[descriptor.id] ?? "Options") }
      }
    }
  }

  // MARK: Page header: big icon, name, description, on/off

  private var header: some View {
    Section {
      HStack(spacing: 14) {
        Look.tile(bigIcon, Look.tint(descriptor.id), size: 52)
        VStack(alignment: .leading, spacing: 2) {
          Text(descriptor.name).font(.title3.weight(.semibold))
          if let b = Look.blurb[descriptor.id] {
            Text(b).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          }
        }
        Spacer(minLength: 12)
        if available {
          Toggle("Enabled", isOn: enabled).labelsHidden().toggleStyle(.switch)
        } else {
          installControl
        }
      }
      .padding(.vertical, 4)
      if let err = manager.errors[descriptor.id] { Text(err).font(.caption).foregroundStyle(.red) }
    }
  }

  @ViewBuilder private var bigIcon: some View {
    if descriptor.customIcon != nil {
      ToolIcon(descriptor).scaleEffect(1.6)
    } else {
      Image(systemName: descriptor.symbol).font(.system(size: 24, weight: .medium))
    }
  }

  private var enabled: Binding<Bool> {
    Binding(
      get: { manager.isEnabled(descriptor.id) },
      set: { manager.setEnabled(descriptor.id, $0) })
  }

  // MARK: Add-on (Blip): its own section on another tool's page

  private var addOnSection: some View {
    Section {
      HStack(spacing: 12) {
        Look.tile(ToolIcon(descriptor), Look.tint(descriptor.id), size: 28)
        VStack(alignment: .leading, spacing: 1) {
          Text(descriptor.name)
          Text(available ? "Adds “Send with Blip” to the shelf" : "Not installed")
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        if available {
          Toggle("Enabled", isOn: enabled).labelsHidden().toggleStyle(.switch).disabled(job.installing)
        } else {
          installControl
        }
      }
      if available, manager.isEnabled(descriptor.id), let tool = manager.active[descriptor.id],
        let settings = tool.makeSettingsView()
      {
        settings
      }
      if available, descriptor.brewCask != nil {
        HStack {
          Text("Installed with Homebrew").foregroundStyle(.secondary)
          Spacer()
          if job.installing {
            ProgressView().controlSize(.small)
          } else {
            Button("Uninstall", role: .destructive) { uninstall() }.controlSize(.small)
          }
        }
      }
      if let e = job.error { Text(e).font(.caption).foregroundStyle(.red) }
    } header: {
      Text("Integrations")
    }
  }

  @ViewBuilder private var installControl: some View {
    if job.installing {
      ProgressView().controlSize(.small)
    } else {
      Button("Install") { install() }.controlSize(.small)
    }
  }

  // MARK: Actions

  private func uninstall() {
    guard let cask = descriptor.brewCask,
      Shell.confirm(
        String(localized: "Uninstall this app?"),
        String(localized: "The app is quit and removed."), action: String(localized: "Uninstall"))
    else { return }
    job.installing = true
    job.error = nil
    Task {
      if let id = descriptor.requiresApp {
        NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.terminate() }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
      }
      job.error = await Shell.brewUninstallCask(cask)
      job.installing = false
      manager.refreshAvailability()
      try? await Task.sleep(nanoseconds: 1_500_000_000)
      manager.refreshAvailability()
    }
  }

  private func install() {
    guard let cask = descriptor.brewCask else { return }
    job.installing = true
    job.error = nil
    Task {
      job.error = await Shell.brewInstallCask(cask)
      job.installing = false
      manager.refreshAvailability()
      try? await Task.sleep(nanoseconds: 1_500_000_000)  // LaunchServices can lag a moment
      manager.refreshAvailability()
    }
  }
}

@MainActor private final class Installer: ObservableObject {
  @Published var installing = false
  @Published var error: String?
}

/// Frosted backdrop behind the window's content; the slider fades its tint so the desktop shows through.
private struct WindowBackdrop: View {
  @ObservedObject private var glass = GlassStyle.shared
  var body: some View {
    ZStack {
      BehindWindowBlur()
      Color(nsColor: .windowBackgroundColor).opacity(1 - glass.transparency * 0.85)
    }
    .ignoresSafeArea()
  }
}

private struct BehindWindowBlur: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let v = NSVisualEffectView()
    v.blendingMode = .behindWindow
    v.material = .underWindowBackground
    v.state = .active
    return v
  }
  func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

private struct AppearanceSection: View {
  @ObservedObject private var glass = GlassStyle.shared

  var body: some View {
    Section {
      LabeledContent("Liquid Glass") {
        HStack(spacing: 10) {
          Slider(value: $glass.transparency, in: 0...1).frame(width: 240)
          Text("\(Int((glass.transparency * 100).rounded()))%")
            .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            .frame(width: 40, alignment: .trailing)
        }
      }
    } header: {
      Text("Appearance")
    }
  }
}

/// The Wi-Fi and Bluetooth buttons in the menu pop-up: one switch each.
private struct ConnectivityPage: View {
  @ObservedObject private var layout = MenuLayout.shared

  var body: some View {
    Section {
      row(MenuLayout.wifi, "Wi-Fi") { Image(systemName: "wifi").font(.system(size: 12, weight: .semibold)) }
      row(MenuLayout.bluetooth, "Bluetooth") { BluetoothGlyph().frame(width: 8, height: 13) }
    } header: {
      Text("Connectivity")
    }
  }

  private func row<I: View>(_ id: String, _ name: LocalizedStringKey, @ViewBuilder icon: () -> I) -> some View {
    Toggle(isOn: Binding(get: { layout.isShown(id) }, set: { layout.setShown(id, $0) })) {
      HStack(spacing: 10) { Look.tile(icon(), .blue, size: 24); Text(name) }
    }
  }
}
