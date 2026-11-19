import AppKit
import KitbagCore
import SwiftUI

@MainActor final class SettingsNav: ObservableObject {
  @Published var page = "fileshelf"
}

/// The Kitbag window: a floating glass sidebar of grouped tools plus Settings, and one page per
/// tool with a header, its on/off switch and its options. The terminal is a drawer (⌘J).
struct SettingsView: View {
  @ObservedObject var manager: ToolManager
  @ObservedObject var nav: SettingsNav
  @ObservedObject private var terminal = TerminalModel.shared

  /// Tools that can be shown: standalone ones, plus integrations that are installed or installable.
  private var tools: [ToolDescriptor] {
    manager.descriptors.filter {
      $0.showsTab && ($0.requiresApp == nil || manager.isAvailable($0) || $0.brewCask != nil)
    }
  }

  private static let productivityIDs = ["fileshelf", "clipboard", "authenticator", "dictation"]

  private var productivityTools: [ToolDescriptor] {
    tools.filter { Self.productivityIDs.contains($0.id) }
  }

  private var systemTools: [ToolDescriptor] {
    tools.filter { !Self.productivityIDs.contains($0.id) }
  }

  var body: some View {
    HStack(spacing: 0) {
      sidebar.frame(width: 242).padding(10)
      detail
    }
    .background { WindowBackdrop() }
    .background {  // ⌘J shows or hides the terminal
      Button("") { terminal.isOpen.toggle() }
        .keyboardShortcut("j", modifiers: .command)
        .opacity(0)
    }
    .overlay(alignment: .bottomTrailing) { terminalButton }
    .ignoresSafeArea()
    .frame(minWidth: 820, minHeight: 560)
  }

  /// Matches the window's own corner radius, so the sidebar and floating button follow its outline.
  static let cornerRadius: CGFloat = 18

  // MARK: Terminal button, bottom right (sits above the drawer while it is open)

  private var terminalButton: some View {
    Button {
      withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
        terminal.isOpen.toggle()
      }
    } label: {
      ZStack(alignment: .topTrailing) {
        Image(systemName: "terminal")
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(terminal.isOpen ? Color.accentColor : Color.primary)
          .frame(width: 44, height: 44)
        if terminal.running {
          StatusDot(color: KitbagUI.warning, active: true, size: 6)
            .padding(6)
        }
      }
      .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(PressableStyle())
    .glass(RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
    .help("Show or hide the terminal (⌘J)")
    .padding(.trailing, 16)
    .padding(.bottom, terminal.isOpen ? 256 + 14 : 16)
    .animation(.spring(response: 0.28, dampingFraction: 0.85), value: terminal.isOpen)
  }

  // MARK: Floating glass sidebar, like System Settings on macOS 26

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 2) {
      Spacer().frame(height: 38)  // room for the traffic-light window buttons

      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          sidebarHeader("Productivity")
          ForEach(productivityTools) { d in
            toolRow(d)
          }

          sidebarHeader("System & Dev")
            .padding(.top, 10)
          ForEach(systemTools) { d in
            toolRow(d)
          }
          row(id: "connectivity", title: Text("Connectivity"), tint: .blue, enabledDot: nil) {
            Image(systemName: "antenna.radiowaves.left.and.right")
              .font(.system(size: 11.5, weight: .semibold))
          }
        }
      }
      .scrollIndicators(.hidden)

      Divider().opacity(0.45).padding(.vertical, 6)

      row(id: "general", title: Text("General"), tint: .gray, enabledDot: nil) {
        Image(systemName: "gearshape.fill")
          .font(.system(size: 12.5, weight: .medium))
      }
    }
    .padding(10)
    .frame(maxHeight: .infinity, alignment: .top)
    .glass(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
  }

  private func sidebarHeader(_ title: LocalizedStringKey) -> some View {
    SectionEyebrow(title)
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
  }

  private func toolRow(_ d: ToolDescriptor) -> some View {
    let active = manager.isAvailable(d) && manager.isEnabled(d.id)
    return row(id: d.id, title: Text(d.name), tint: Look.tint(d.id), enabledDot: active) {
      ToolIcon(d).scaleEffect(0.86)
    }
  }

  private func row<I: View>(
    id: String,
    title: Text,
    tint: Color,
    enabledDot: Bool?,
    @ViewBuilder icon: () -> I
  ) -> some View {
    let selected = nav.page == id
    return Button {
      nav.page = id
    } label: {
      HStack(spacing: 10) {
        Look.tile(icon(), tint, size: 24)
        title
          .font(.callout.weight(selected ? .semibold : .regular))
          .lineLimit(1)
        Spacer(minLength: 4)
        if let on = enabledDot {
          Circle()
            .fill(
              selected
                ? (on ? Color.white : Color.white.opacity(0.35))
                : (on ? KitbagUI.success : Color.secondary.opacity(0.28))
            )
            .frame(width: 6, height: 6)
            .padding(.trailing, 3)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .foregroundStyle(selected ? Color.white : Color.primary)
      .background(
        selected ? Color.accentColor : .clear,
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
      .hoverHighlight(cornerRadius: 10, tint: selected ? nil : Color.primary)
      .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  // MARK: Detail

  private var detail: some View {
    VStack(spacing: 0) {
      Spacer().frame(height: 36)  // title bar area; each page has its own header card
      Form {
        if nav.page == "connectivity" {
          ConnectivityPage()
        } else if nav.page == "general" {
          AppearanceSection()
          LoginItemSection()
          UpdatesSection()
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
        TerminalView(model: terminal)
          .padding(.horizontal, 16)
          .padding(.top, 12)
          .padding(.bottom, 16)
          .frame(height: 256)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
  }
}

/// Shared look: colored icon tiles, per-tool colors and descriptions.
enum Look {
  static func tint(_ id: String) -> Color {
    [
      "fileshelf": .blue, "systemmonitor": .green, "speedtest": .orange, "devtools": .purple,
      "audio": .pink, "blip": .indigo, "apps": .teal, "dictation": .red, "clipboard": .cyan,
      "authenticator": .mint,
    ][id] ?? .gray
  }

  static let blurb: [String: LocalizedStringKey] = [
    "fileshelf":
      "A temporary shelf for files while you move, convert, or compress them between apps.",
    "systemmonitor":
      "Live CPU, memory, storage, network throughput, and battery health at a glance.",
    "speedtest": "Measure download, upload, and latency against Cloudflare's servers in one tap.",
    "devtools":
      "Pick screen colors, measure pixels, and manage Docker, databases, Node, and Python.",
    "audio": "Switch audio output and input devices instantly, or combine multiple outputs.",
    "authenticator":
      "Two-factor codes in your menu bar with QR scanning, Keychain storage, and JSON backups.",
    "clipboard": "Searchable clipboard history. Press ⌥⌘V anywhere to pick an item and paste it.",
    "apps":
      "Start or quit Google Drive, Proton Drive, Wispr Flow, OpenWhispr, and FineTune from one place.",
    "dictation":
      "Hold a key, speak, and have your words transcribed, cleaned up, and pasted where you type.",
  ]

  /// Tools whose settings view builds its own sections instead of one options section.
  static let ownSections: Set<String> = ["dictation", "authenticator"]

  static let optionsTitle: [String: LocalizedStringKey] = [
    "fileshelf": "Behavior", "systemmonitor": "Monitoring", "devtools": "Runtimes & Services",
    "apps": "Apps to show", "dictation": "Dictation", "clipboard": "History",
  ]

  static func tile<V: View>(_ icon: V, _ color: Color, size: CGFloat) -> some View {
    icon.foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(
        color.gradient,
        in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
      )
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
        Section {
          settings
        } header: {
          Text(Look.optionsTitle[descriptor.id] ?? "Options")
        }
      }
    }
  }

  // MARK: Page header: big icon, name, description, on/off

  private var header: some View {
    Section {
      HStack(spacing: 14) {
        Look.tile(bigIcon, Look.tint(descriptor.id), size: 50)
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 7) {
            Text(descriptor.name).font(.title3.weight(.semibold))
            if available {
              let on = manager.isEnabled(descriptor.id)
              Text(on ? "Active" : "Off")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(on ? KitbagUI.success : .secondary)
                .padding(.horizontal, 6.5)
                .padding(.vertical, 2)
                .background(
                  (on ? KitbagUI.success : Color.secondary).opacity(0.14),
                  in: Capsule()
                )
            }
          }
          if let b = Look.blurb[descriptor.id] {
            Text(b)
              .font(.callout)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
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
      if let err = manager.errors[descriptor.id] {
        Label(err, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(KitbagUI.danger)
      }
    }
  }

  @ViewBuilder private var bigIcon: some View {
    if descriptor.customIcon != nil {
      ToolIcon(descriptor).scaleEffect(1.55)
    } else {
      Image(systemName: descriptor.symbol).font(.system(size: 23, weight: .medium))
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
          Text(descriptor.name).font(.callout.weight(.medium))
          Text(available ? "Adds “Send with Blip” to the shelf" : "Not installed")
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        if available {
          Toggle("Enabled", isOn: enabled)
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(job.installing)
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
      if let e = job.error { Text(e).font(.caption).foregroundStyle(KitbagUI.danger) }
    } header: {
      Text("Integrations")
    }
  }

  @ViewBuilder private var installControl: some View {
    if job.installing {
      ProgressView().controlSize(.small)
    } else {
      Button("Install") { install() }.controlSize(.small).buttonStyle(.borderedProminent)
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
        NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach {
          $0.terminate()
        }
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
      LabeledContent("Surface translucency") {
        HStack(spacing: 10) {
          Slider(value: $glass.transparency, in: 0...1).frame(width: 220)
          Text("\(Int((glass.transparency * 100).rounded()))%")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 40, alignment: .trailing)
        }
      }
    } header: {
      Text("Appearance")
    } footer: {
      Text("Adjusts how see-through the Settings window backdrop and popover surfaces appear.")
    }
  }
}

/// The Wi-Fi and Bluetooth buttons in the menu pop-up: one switch each.
private struct ConnectivityPage: View {
  @ObservedObject private var layout = MenuLayout.shared

  var body: some View {
    Section {
      HStack(spacing: 14) {
        Look.tile(
          Image(systemName: "antenna.radiowaves.left.and.right")
            .font(.system(size: 21, weight: .semibold)),
          .blue,
          size: 50
        )
        VStack(alignment: .leading, spacing: 3) {
          Text("Connectivity").font(.title3.weight(.semibold))
          Text(
            "Show quick Wi-Fi and Bluetooth status buttons in the corner of the menu bar popover."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.vertical, 4)
    }
    Section {
      row(MenuLayout.wifi, "Wi-Fi") {
        Image(systemName: "wifi").font(.system(size: 12, weight: .semibold))
      }
      row(MenuLayout.bluetooth, "Bluetooth") {
        BluetoothGlyph().frame(width: 8, height: 13)
      }
    } header: {
      Text("Quick Buttons")
    }
  }

  private func row<I: View>(
    _ id: String, _ name: LocalizedStringKey, @ViewBuilder icon: () -> I
  ) -> some View {
    Toggle(isOn: Binding(get: { layout.isShown(id) }, set: { layout.setShown(id, $0) })) {
      HStack(spacing: 10) {
        Look.tile(icon(), .blue, size: 24)
        Text(name)
      }
    }
  }
}
