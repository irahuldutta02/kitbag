import AppKit
import KitbagCore
import SwiftUI

/// The tab in the menu pop-up (if shown).
struct DictationView: View {
  @ObservedObject var model: DictationModel
  @StateObject private var copied = UIBox(false)

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        StatusDot(
          color: model.phase == .listening
            ? KitbagUI.danger : (model.phase == .processing ? KitbagUI.warning : KitbagUI.success),
          active: model.phase != .idle,
          size: 7
        )
        VStack(alignment: .leading, spacing: 1) {
          Text(statusTitle).font(.callout.weight(.semibold))
          Text(statusText).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Button(model.phase == .listening ? "Stop" : "Start") { model.toggle() }
          .disabled(model.phase == .processing)
          .buttonStyle(.borderedProminent)
          .tint(model.phase == .listening ? KitbagUI.danger : Color.accentColor)
          .controlSize(.small)
      }

      HStack(spacing: 6) {
        Text("Shortcut").font(.caption).foregroundStyle(.secondary)
        KeycapBadge(model.settings.shortcut.display)
        Spacer()
        Button("Dashboard") { DictationDashboard.show() }
          .controlSize(.mini)
          .buttonStyle(.bordered)
      }

      TodaySummary()

      if !model.lastText.isEmpty {
        Divider().opacity(0.45)
        HStack {
          SectionEyebrow("Last Dictation")
          Spacer()
          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(model.lastText, forType: .string)
            withAnimation { copied.value = true }
            Task {
              try? await Task.sleep(nanoseconds: 1_200_000_000)
              withAnimation { copied.value = false }
            }
          } label: {
            Label(
              copied.value ? "Copied" : "Copy",
              systemImage: copied.value ? "checkmark" : "doc.on.doc"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(copied.value ? KitbagUI.success : .secondary)
          }
          .buttonStyle(.plain)
        }
        Text(model.lastText)
          .font(.callout)
          .lineLimit(5)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card(padding: 11)
  }

  private struct TodaySummary: View {
    @ObservedObject var stats = DictationStats.shared
    var body: some View {
      let t = DictationSummary(stats.sessions(since: Calendar.current.startOfDay(for: Date())))
      Text(
        "Today: \(DashboardView.duration(t.speakSeconds)) · \(t.words) words · \(DashboardView.money(t.cost))"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private var statusTitle: LocalizedStringKey {
    switch model.phase {
    case .idle: return "Ready to dictate"
    case .listening: return "Listening…"
    case .processing: return "Polishing…"
    }
  }

  private var statusText: LocalizedStringKey {
    switch model.phase {
    case .idle:
      return model.settings.shortcut.isFn
        ? "Hold Globe key anywhere to speak" : "Press shortcut anywhere to speak"
    case .listening: return "Press Esc to cancel"
    case .processing: return "Transcribing & cleaning up"
    }
  }
}

/// Which "setup" groups the person opened.
@MainActor private final class SetupDisclosure: ObservableObject {
  @Published var whisper = false
  @Published var gemma = false
  @Published var prompt = false
  @Published var test = false
  @Published var initialized = false
}

/// Today's totals in one line.
private struct TodayLine: View {
  @ObservedObject var stats = DictationStats.shared
  var body: some View {
    let t = DictationSummary(stats.sessions(since: Calendar.current.startOfDay(for: Date())))
    if t.sessions == 0 {
      Text("Nothing dictated today").foregroundStyle(.secondary)
    } else {
      Text(
        "Today: \(DashboardView.duration(t.speakSeconds)) · \(t.words) words · \(DashboardView.money(t.cost))"
      )
    }
  }
}

/// A key drawn like a keycap.
private struct Keycap: View {
  let text: String
  var highlighted = false
  var body: some View {
    Text(text)
      .font(.system(size: 15, weight: .semibold, design: .rounded))
      .foregroundStyle(highlighted ? Color.accentColor : .primary)
      .padding(.horizontal, 13)
      .padding(.vertical, 6)
      .background(
        .quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(
            highlighted ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.14),
            lineWidth: highlighted ? 1 : 0.75
          )
      )
  }
}

/// Options on the Dictation page of the Kitbag window. Each group is its own section.
struct DictationSettingsView: View {
  @ObservedObject var model: DictationModel
  @ObservedObject var settings: DictationSettings
  @ObservedObject var local: LocalSetup
  @StateObject private var picker = ShortcutPicker()
  @StateObject private var ui = SetupDisclosure()
  @ObservedObject private var providers = ProviderManager.shared
  @StateObject private var testBox = UIBox("")

  var body: some View {
    if let e = local.error {
      Section {
        HStack(spacing: 8) {
          Label(e, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(KitbagUI.danger)
            .font(.callout)
          Spacer()
          Button("Dismiss") { local.error = nil }.controlSize(.small)
        }
      }
    }
    shortcutSection
    speechSection
    cleanupSection
    promptSection
    testSection
    permissionsSection
    statisticsSection
  }

  // MARK: Shortcut

  @ViewBuilder private var shortcutSection: some View {
    Section {
      HStack(spacing: 10) {
        Keycap(
          text: picker.recording ? "Press new keys…" : settings.shortcut.display,
          highlighted: picker.recording)
        Spacer()
        if !settings.shortcut.isFn && !picker.recording {
          Button("Use Globe key") { settings.shortcut = .fn }.controlSize(.small)
        }
        Button(picker.recording ? "Cancel" : "Change") {
          picker.recording ? stopRecording() : startRecording()
        }
        .controlSize(.small)
      }
      if settings.shortcut.isFn {
        hint("Hold to talk, release to paste", "hand.tap.fill")
        hint("Double-tap to start hands-free, double-tap again to stop", "repeat")
        HStack {
          hint("Set “Press 🌐 key to” to Do Nothing", "info.circle")
          Spacer()
          Button("Open Keyboard Settings…") { model.openKeyboardSettings() }.controlSize(.small)
        }
      } else {
        hint("Press to start, press again to finish", "hand.tap.fill")
      }
      hint("Esc cancels while listening", "escape")
    } header: {
      Text("Shortcut")
    }
    .onDisappear { if picker.recording { stopRecording() } }
  }

  private func hint(_ text: LocalizedStringKey, _ symbol: String) -> some View {
    Label(text, systemImage: symbol).font(.callout).foregroundStyle(.secondary)
  }

  // MARK: Speech to text

  private var whisperReady: Bool { local.whisperBinary != nil && local.whisperModelReady }

  @ViewBuilder private var speechSection: some View {
    Section {
      Picker("Speech to text", selection: $settings.engine) {
        Text("Apple").tag("apple")
        Text("Whisper").tag("whisper")
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .onAppear {
        local.refresh()
        if providers.lastChecked == nil { providers.refreshAll() }
        if !ui.initialized {
          ui.whisper = !whisperReady
          ui.gemma = !gemmaReady
          ui.initialized = true
        }
      }

      if settings.engine == "whisper" {
        status(ready: whisperReady, ok: "Ready · runs on this Mac", todo: "Finish setup below")
        Picker("Language", selection: $settings.whisperLanguage) {
          ForEach(LocalSetup.whisperLanguages) { Text($0.name).tag($0.id) }
        }
        if settings.whisperLanguage == "auto" {
          LabeledContent("Languages I speak") {
            Menu {
              ForEach(LocalSetup.whisperLanguages.filter { $0.id != "auto" }) { l in
                Toggle(
                  l.name,
                  isOn: Binding(
                    get: { settings.allowedLanguages.contains(l.id) },
                    set: { settings.setAllowed(l.id, $0) }))
              }
            } label: {
              Text(allowedSummary)
                .lineLimit(1)
                .truncationMode(.tail)
            }
            .frame(maxWidth: 220, alignment: .trailing)
          }
          hint(
            "Auto-detect finds the language of each recording. Pick languages you speak to narrow it down, or leave it on any language.",
            "info.circle")
        }
        DisclosureGroup("Whisper setup", isExpanded: $ui.whisper) { whisperRows }
      } else {
        Picker("Language", selection: $settings.language) {
          Text("System language").tag("")
          ForEach(DictationSettings.languages) { Text($0.name).tag($0.id) }
        }
        hint(
          "Built into macOS. No download needed, though it supports fewer languages.", "info.circle"
        )
      }
    } header: {
      Text("Speech to text")
    }
  }

  private var allowedSummary: String {
    let names = settings.allowedLanguages.compactMap { code in
      LocalSetup.whisperLanguages.first { $0.id == code }?.name
    }
    return names.isEmpty ? String(localized: "Any language") : names.joined(separator: ", ")
  }

  private func status(ready: Bool, ok: LocalizedStringKey, todo: LocalizedStringKey) -> some View {
    HStack(spacing: 8) {
      Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
        .foregroundStyle(ready ? KitbagUI.success : KitbagUI.warning)
      Text(ready ? ok : todo).font(.callout.weight(.medium))
      Spacer()
    }
  }

  @ViewBuilder private var whisperRows: some View {
    LabeledContent("Engine") {
      if let busy = local.whisperBusy, local.whisperProgress == nil {
        HStack(spacing: 6) {
          ProgressView().controlSize(.small)
          Text(busy)
        }
      } else if local.whisperBinary != nil {
        HStack(spacing: 10) {
          installed
          Button("Uninstall", role: .destructive) { local.uninstallWhisper() }.controlSize(.small)
        }
      } else {
        Button("Install") { local.installWhisper() }.controlSize(.small)
      }
    }
    Picker("Model", selection: $settings.whisperModel) {
      ForEach(LocalSetup.whisperModels) { Text($0.name).tag($0.id) }
    }
    .onChange(of: settings.whisperModel) { _, _ in local.refresh() }
    LabeledContent("Model file") {
      if local.whisperModelReady {
        HStack(spacing: 10) {
          Label("Downloaded", systemImage: "checkmark.circle.fill").foregroundStyle(
            KitbagUI.success)
          Button("Delete", role: .destructive) { local.deleteWhisperModel() }.controlSize(.small)
        }
      } else if let p = local.whisperProgress {
        HStack(spacing: 6) {
          ProgressView(value: p).frame(width: 90)
          Text("\(Int(p * 100))%").monospacedDigit()
        }
      } else {
        Button("Download") { local.downloadWhisperModel() }.controlSize(.small)
      }
    }
  }

  // MARK: Cleanup

  private var gemmaReady: Bool { local.ollamaPath != nil && local.gemmaReady }

  @ViewBuilder private var cleanupSection: some View {
    Section {
      Picker("Cleanup", selection: $settings.provider) {
        Text("Claude").tag("claude")
        Text("Antigravity").tag("antigravity")
        Text("Codex").tag("codex")
        Text("Gemma").tag("gemma")
        Text("Off").tag("off")
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      switch settings.provider {
      case "claude":
        providerStatus(.claude)
        Picker("Model", selection: $settings.model) {
          ForEach(DictationSettings.models) { Text($0.name).tag($0.id) }
        }
        Picker("Effort", selection: $settings.effort) {
          ForEach(DictationSettings.efforts) { Text($0.name).tag($0.id) }
        }
        providerActions(.claude)
      case "antigravity":
        providerStatus(.antigravity)
        Picker("Model", selection: $settings.agyModel) {
          ForEach(DictationSettings.agyModels) { Text($0.name).tag($0.id) }
        }
        Picker("Effort", selection: $settings.agyEffort) {
          ForEach(DictationSettings.simpleEfforts) { Text($0.name).tag($0.id) }
        }
        providerActions(.antigravity)
      case "codex":
        providerStatus(.codex)
        Picker("Model", selection: $settings.codexModel) {
          ForEach(DictationSettings.codexModels) { Text($0.name).tag($0.id) }
        }
        Picker("Effort", selection: $settings.codexEffort) {
          ForEach(DictationSettings.simpleEfforts) { Text($0.name).tag($0.id) }
        }
        providerActions(.codex)
      case "gemma":
        status(ready: gemmaReady, ok: "Ready · runs on this Mac", todo: "Finish setup below")
        DisclosureGroup("Gemma setup", isExpanded: $ui.gemma) { gemmaRows }
      default:
        hint("Your words are pasted exactly as recognized.", "info.circle")
      }
    } header: {
      Text("Clean-up")
    } footer: {
      if settings.provider != "off" {
        Text(
          "Removes filler words and fixes punctuation while keeping the language and terms you spoke."
        )
      }
    }
  }

  // MARK: Provider status and actions (Claude, Antigravity, Codex)

  private func providerStatus(_ id: AIProviderID) -> some View {
    let st = providers.state(id)
    let ready = st.installed && st.authenticated
    return HStack(spacing: 8) {
      Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
        .foregroundStyle(ready ? KitbagUI.success : KitbagUI.warning)
      VStack(alignment: .leading, spacing: 1) {
        Text(st.installed ? st.authSummary : "\(id.displayName) isn't installed")
          .font(.callout.weight(.medium))
        if st.installed, let v = st.version {
          Text("\(id.binaryName) \(v)").font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer()
    }
  }

  @ViewBuilder private func providerActions(_ id: AIProviderID) -> some View {
    let st = providers.state(id)
    LabeledContent(id.displayName) {
      HStack(spacing: 8) {
        if let busy = st.busyAction {
          ProgressView().controlSize(.small)
          Text(busy).font(.caption).foregroundStyle(.secondary)
        } else if !st.installed {
          Button("Install") { providers.install(id) }.controlSize(.small)
        } else {
          if !st.authenticated { Button("Sign in") { providers.signIn(id) }.controlSize(.small) }
          Button("Update") { providers.update(id) }.controlSize(.small)
        }
        Button("Manage Providers…") {
          NotificationCenter.default.post(name: .kitbagOpenSettings, object: "providers")
        }
        .controlSize(.small)
      }
    }
    if let e = st.error {
      HStack {
        Text(e).font(.caption).foregroundStyle(KitbagUI.danger)
        Spacer()
        Button("Dismiss") { providers.dismissError(id) }.controlSize(.mini)
      }
    }
  }

  // MARK: Editable clean-up prompt

  @ViewBuilder private var promptSection: some View {
    if settings.provider != "off" {
      Section {
        DisclosureGroup(isExpanded: $ui.prompt) {
          TextEditor(text: $settings.cleanupPrompt)
            .font(.system(size: 12, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(height: 160)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.75)
            )
          HStack {
            Text("Sent to the model with every dictation. Keep the <transcript> convention.")
              .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Reset to Default") { settings.resetPrompt() }
              .controlSize(.small)
              .disabled(!settings.isCustomPrompt)
          }
        } label: {
          HStack(spacing: 8) {
            Text("Edit prompt")
            if settings.isCustomPrompt {
              Text("Customized")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 6.5).padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.14), in: Capsule())
            }
          }
        }
      } header: {
        Text("Clean-up Prompt")
      }
    }
  }

  // MARK: Test box

  @ViewBuilder private var testSection: some View {
    Section {
      DisclosureGroup("Test dictation", isExpanded: $ui.test) {
        TextEditor(text: $testBox.value)
          .font(.system(size: 13))
          .scrollContentBackground(.hidden)
          .padding(6)
          .frame(height: 110)
          .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.75)
          )
        HStack {
          Text(testHint).font(.caption).foregroundStyle(.secondary)
          Spacer()
          Button("Clear") { testBox.value = "" }
            .controlSize(.small)
            .disabled(testBox.value.isEmpty)
          Button(model.phase == .listening ? "Stop" : "Start") {
            let box = testBox
            model.toggleTest { result in
              let sep = box.value.isEmpty || box.value.hasSuffix("\n") ? "" : " "
              box.value += sep + result
            }
          }
          .disabled(model.phase == .processing)
          .buttonStyle(.borderedProminent)
          .tint(model.phase == .listening ? KitbagUI.danger : Color.accentColor)
          .controlSize(.small)
        }
      }
    } header: {
      Text("Test")
    }
  }

  private var testHint: LocalizedStringKey {
    switch model.phase {
    case .idle: return "Press Start, speak, then press Stop. Uses your current settings."
    case .listening: return "Listening… press Stop when you're done."
    case .processing: return "Transcribing & cleaning up…"
    }
  }

  @ViewBuilder private var gemmaRows: some View {
    LabeledContent("Ollama") {
      if let busy = local.ollamaBusy, busy == "Removing…" || busy == "Installing…" {
        HStack(spacing: 6) {
          ProgressView().controlSize(.small)
          Text(busy)
        }
      } else if local.ollamaPath != nil {
        HStack(spacing: 10) {
          installed
          Button("Uninstall", role: .destructive) { local.uninstallOllama() }.controlSize(.small)
        }
      } else {
        Button("Install") { local.installOllama() }.controlSize(.small)
      }
    }
    Picker("Model", selection: $settings.gemmaModel) {
      ForEach(gemmaChoices) { Text($0.name).tag($0.id) }
    }
    .onChange(of: settings.gemmaModel) { _, _ in local.refresh() }
    LabeledContent("Other Ollama model") {
      TextField("Model", text: $settings.gemmaModel)
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .frame(width: 160)
        .multilineTextAlignment(.trailing)
    }
    LabeledContent("Model file") {
      if local.ollamaBusy != nil && local.gemmaReady {
        HStack(spacing: 6) {
          ProgressView().controlSize(.small)
          Text(local.ollamaBusy ?? "")
        }
      } else if local.gemmaReady {
        HStack(spacing: 10) {
          Label("Downloaded", systemImage: "checkmark.circle.fill").foregroundStyle(
            KitbagUI.success)
          Button("Delete", role: .destructive) { local.deleteGemma() }.controlSize(.small)
        }
      } else if local.ollamaPath == nil {
        Text("Install Ollama first").foregroundStyle(.secondary)
      } else if let busy = local.ollamaBusy {
        HStack(spacing: 6) {
          ProgressView().controlSize(.small)
          Text(busy).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
      } else {
        Button("Download") { local.downloadGemma() }.controlSize(.small)
      }
    }
  }

  private var gemmaChoices: [LocalSetup.Option] {
    let known = LocalSetup.gemmaModels
    if known.contains(where: { $0.id == settings.gemmaModel }) { return known }
    return known + [LocalSetup.Option(id: settings.gemmaModel, name: settings.gemmaModel)]
  }

  private var installed: some View {
    Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(KitbagUI.success)
  }

  // MARK: Permissions and statistics

  @ViewBuilder private var permissionsSection: some View {
    Section {
      LabeledContent {
        if model.accessibilityGranted {
          Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(KitbagUI.success)
        } else {
          Button("Allow…") { model.allowAutoPaste() }.controlSize(.small)
        }
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          Text("Accessibility")
          Text("Lets Kitbag paste your text and listen for the Globe key")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    } header: {
      Text("Permissions")
    }
  }

  @ViewBuilder private var statisticsSection: some View {
    Section {
      HStack {
        TodayLine().font(.callout)
        Spacer()
        Button("Open Dashboard") { DictationDashboard.show() }.controlSize(.small)
      }
    } header: {
      Text("Statistics")
    }
  }

  // MARK: Choosing a shortcut

  private func startRecording() {
    picker.recording = true
    model.pauseHotKey(true)
    picker.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
      if e.keyCode == 53 {  // esc
        stopRecording()
        return nil
      }
      let mods = Shortcut.carbonModifiers(e.modifierFlags)
      guard mods != 0 else {
        NSSound.beep()
        return nil
      }  // needs at least one modifier key
      settings.shortcut = Shortcut(
        keyCode: UInt32(e.keyCode), modifiers: mods, label: Shortcut.label(for: e))
      stopRecording()
      return nil
    }
  }

  private func stopRecording() {
    if let m = picker.monitor { NSEvent.removeMonitor(m) }
    picker.monitor = nil
    picker.recording = false
    model.pauseHotKey(false)
  }
}

@MainActor private final class ShortcutPicker: ObservableObject {
  @Published var recording = false
  var monitor: Any?
}
