import AppKit
import KitbagCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Menu Bar Popover View

struct VideoPlayerMenuView: View {
  @ObservedObject var model: VideoPlayerModel
  @StateObject private var copied = UIBox(false)

  var body: some View {
    VStack(spacing: 10) {
      // Hero launch & status card
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 10) {
          StatusDot(
            color: model.stats.isRunning ? KitbagUI.success : .secondary,
            active: model.stats.isRunning,
            size: 7
          )
          VStack(alignment: .leading, spacing: 1.5) {
            Text(model.stats.isRunning ? "Server Running" : "Ready to Stream")
              .font(.callout.weight(.semibold))
            Text(statusSubtitle)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          Spacer(minLength: 6)
          if model.stats.isRunning {
            Button {
              copyServerURL()
            } label: {
              Image(systemName: copied.value ? "checkmark" : "link")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(copied.value ? KitbagUI.success : .secondary)
                .frame(width: 24, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .hoverHighlight(cornerRadius: 6)
            .help("Copy local URL")

            Button {
              model.stopServer()
            } label: {
              Image(systemName: "stop.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(KitbagUI.danger)
                .frame(width: 24, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .hoverHighlight(cornerRadius: 6, tint: KitbagUI.danger)
            .help("Stop local server and active streams")
          }
        }

        // Destination browser pill
        HStack(spacing: 8) {
          if let browser = model.effectiveBrowser {
            Image(nsImage: BrowserDiscovery.icon(for: browser.appURL, size: 16))
              .resizable()
              .frame(width: 16, height: 16)
          } else {
            Image(systemName: "globe")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(.secondary)
          }
          Text("Opens in \(model.destinationBrowserName)")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
          Spacer(minLength: 4)
          Button("Change") {
            NotificationCenter.default.post(name: .kitbagOpenSettings, object: "videoplayer")
          }
          .buttonStyle(.plain)
          .font(.caption.weight(.medium))
          .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
          Color.primary.opacity(0.045),
          in: RoundedRectangle(cornerRadius: KitbagUI.innerRadius, style: .continuous)
        )

        // Primary actions
        HStack(spacing: 8) {
          Button {
            model.openPlayer()
          } label: {
            HStack(spacing: 6) {
              if model.isStarting {
                ProgressView().controlSize(.mini)
              } else {
                Image(systemName: "play.fill")
                  .font(.system(size: 11.5, weight: .semibold))
              }
              Text("Open Player")
                .font(.callout.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .disabled(model.isStarting)

          Button {
            model.chooseVideoAndOpen()
          } label: {
            Label("Choose…", systemImage: "film")
              .font(.callout.weight(.medium))
          }
          .buttonStyle(.bordered)
          .controlSize(.large)
          .disabled(model.isStarting)
          .help("Pick a local video file and open it in the browser")
        }
      }
      .card(padding: 11)

      // FFmpeg warning if missing
      if !model.ffmpegStatus.isReady {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(KitbagUI.warning)
          VStack(alignment: .leading, spacing: 1) {
            Text("FFmpeg required for playback")
              .font(.caption.weight(.semibold))
            Text("Install via Homebrew in Video Player settings.")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Spacer(minLength: 4)
          Button("Setup") {
            NotificationCenter.default.post(name: .kitbagOpenSettings, object: "videoplayer")
          }
          .buttonStyle(.bordered)
          .controlSize(.mini)
        }
        .card(padding: 10, borderColor: KitbagUI.warning.opacity(0.5), borderWidth: 1)
      }

      // Recently played videos
      if !model.settings.recents.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            SectionEyebrow("Continue Watching")
            Spacer()
            Button("Clear") {
              model.clearRecents()
            }
            .buttonStyle(.plain)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .hoverHighlight(cornerRadius: 5)
          }
          .padding(.horizontal, 4)

          VStack(spacing: 3) {
            ForEach(model.settings.recents.prefix(4)) { item in
              RecentRow(
                item: item,
                onPlay: { model.openPlayer(filePath: item.path, autoPlay: true) },
                onRemove: { model.removeRecent(item) }
              )
            }
          }
        }
        .card(padding: 10)
      }

      if let err = model.errorMessage {
        HStack(spacing: 6) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(KitbagUI.danger)
          Text(err)
            .font(.caption)
            .foregroundStyle(KitbagUI.danger)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
          KitbagUI.danger.opacity(0.1),
          in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
      }
    }
  }

  private var statusSubtitle: String {
    if model.stats.isRunning {
      var parts = ["127.0.0.1:\(model.stats.port)"]
      if model.stats.clientCount > 0 {
        parts.append(
          "\(model.stats.clientCount) \(model.stats.clientCount == 1 ? "tab" : "tabs")")
      }
      if model.stats.activeStreams > 0 {
        parts.append(
          "\(model.stats.activeStreams) \(model.stats.activeStreams == 1 ? "stream" : "streams")")
      }
      return parts.joined(separator: " · ")
    }
    return "Starts on port \(model.settings.port) when opened"
  }

  private func copyServerURL() {
    guard let url = model.serverBaseURL else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.absoluteString, forType: .string)
    withAnimation { copied.value = true }
    Task {
      try? await Task.sleep(nanoseconds: 1_400_000_000)
      withAnimation { copied.value = false }
    }
  }

  private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
    guard !providers.isEmpty else { return false }
    Task {
      var urls: [URL] = []
      for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        if let url = await loadFileURL(from: p) {
          urls.append(url)
        }
      }
      if !urls.isEmpty {
        _ = model.handleDroppedURLs(urls)
      }
    }
    return true
  }

  private func loadFileURL(from provider: NSItemProvider) async -> URL? {
    await withCheckedContinuation { cont in
      provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
        if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
          cont.resume(returning: url)
        } else if let url = item as? URL {
          cont.resume(returning: url)
        } else {
          cont.resume(returning: nil)
        }
      }
    }
  }
}

private struct RecentRow: View {
  let item: RecentVideo
  let onPlay: () -> Void
  let onRemove: () -> Void
  @StateObject private var hover = UIBox(false)

  var body: some View {
    HStack(spacing: 8) {
      Button(action: onPlay) {
        HStack(spacing: 8) {
          ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
              .fill(Color.accentColor.opacity(0.13))
              .frame(width: 26, height: 26)
            Image(systemName: "play.fill")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(Color.accentColor)
          }

          VStack(alignment: .leading, spacing: 3) {
            Text(item.name)
              .font(.caption.weight(.medium))
              .lineLimit(1)
              .truncationMode(.middle)

            if item.duration > 0 {
              HStack(spacing: 6) {
                GeometryReader { geo in
                  ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule()
                      .fill(Color.accentColor)
                      .frame(width: max(4, geo.size.width * item.progress))
                  }
                }
                .frame(height: 3)

                Text(item.canResume ? Self.fmt(item.position) : Self.fmt(item.duration))
                  .font(.system(size: 10, design: .rounded).monospacedDigit())
                  .foregroundStyle(.secondary)
              }
            }
          }
          Spacer(minLength: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .buttonStyle(PressableStyle())

      if hover.value {
        Button(action: onRemove) {
          Image(systemName: "xmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: 18, height: 18)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .capsuleHoverHighlight()
        .help("Remove from recent list")
      }
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 5)
    .hoverHighlight(cornerRadius: 8)
    .onHover { hover.value = $0 }
  }

  private static func fmt(_ seconds: Double) -> String {
    let s = max(0, Int(seconds))
    let h = s / 3600
    let m = (s % 3600) / 60
    let rem = s % 60
    if h > 0 {
      return String(format: "%d:%02d:%02d", h, m, rem)
    }
    return String(format: "%d:%02d", m, rem)
  }
}

// MARK: - Settings View (Multi-Section Native macOS Form)

struct VideoPlayerSettingsView: View {
  @ObservedObject var model: VideoPlayerModel
  @ObservedObject var settings: VideoPlayerSettings
  @StateObject private var portText = UIBox("")

  var body: some View {
    browserAndLaunchSection
    playbackSection
    appearanceSection
    subtitlesSection
    serverAndEngineSection
  }

  // MARK: 1. Browser & Launch

  private var browserAndLaunchSection: some View {
    Section {
      Picker("Destination browser", selection: $settings.browserBundleID) {
        HStack(spacing: 6) {
          if let def = model.systemDefaultBrowser {
            Image(nsImage: BrowserDiscovery.icon(for: def.appURL, size: 15))
            Text("System Default (\(def.name))")
          } else {
            Image(systemName: "globe")
            Text("System Default")
          }
        }
        .tag("")

        if !model.installedBrowsers.isEmpty {
          Divider()
          ForEach(model.installedBrowsers) { browser in
            HStack(spacing: 6) {
              Image(nsImage: BrowserDiscovery.icon(for: browser.appURL, size: 15))
              Text(browser.name)
            }
            .tag(browser.id)
          }
        }
      }

      if model.selectedBrowserMissing {
        Label(
          "The previously selected browser isn't installed. Falling back to your System Default browser.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(KitbagUI.warning)
      }

      LabeledContent("Default library folder") {
        HStack(spacing: 8) {
          Text(settings.defaultFolder)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 220, alignment: .trailing)
          Button("Choose…") { model.chooseDefaultFolder() }
            .controlSize(.small)
          if settings.defaultFolder != "~/Movies" {
            Button("Reset") { settings.defaultFolder = "~/Movies" }
              .controlSize(.small)
          }
        }
      }

      ShortcutRecorderRow(
        "Open Video Player tab",
        current: model.shortcut,
        defaultShortcut: VideoPlayerModel.defaultShortcut,
        onPause: { model.pauseHotKey($0) },
        onSet: { model.setShortcut($0) }
      )

      LabeledContent("Quick launch") {
        HStack(spacing: 8) {
          Button("Choose Video…") { model.chooseVideoAndOpen() }
            .controlSize(.small)
          Button("Open Player") { model.openPlayer() }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
      }
    } header: {
      Text("Browser & Launch")
    } footer: {
      Text(
        "Choose which browser opens the local player. Picking a Chromium browser such as Google Chrome or Arc makes sharing a tab with audio in Google Meet effortless."
      )
    }
    .onAppear {
      model.refresh()
      portText.value = String(settings.port)
    }
  }

  // MARK: 2. Playback & Streaming

  private var playbackSection: some View {
    Section {
      Picker("Default video quality", selection: $settings.defaultQuality) {
        ForEach(VideoQuality.allCases) { q in
          Text(q.title).tag(q)
        }
      }

      Picker("Default playback speed", selection: $settings.defaultSpeed) {
        ForEach(VideoPlayerSettings.speedOptions, id: \.self) { speed in
          Text(Self.formatSpeed(speed)).tag(speed)
        }
      }

      Picker("Skip forward / back", selection: $settings.skipSeconds) {
        ForEach(VideoPlayerSettings.skipOptions, id: \.self) { sec in
          Text("\(sec) seconds").tag(sec)
        }
      }

      Picker("Preferred audio language", selection: $settings.preferredAudioLanguage) {
        ForEach(VideoPlayerSettings.supportedLanguages) { lang in
          Text(lang.title).tag(lang.id)
        }
      }

      Toggle("Hardware acceleration (Apple VideoToolbox)", isOn: $settings.hardwareAcceleration)

      Toggle("Remember playback position & recent videos", isOn: $settings.rememberPosition)

      if !settings.recents.isEmpty {
        LabeledContent("Saved history") {
          HStack(spacing: 8) {
            Text("\(settings.recents.count) \(settings.recents.count == 1 ? "video" : "videos")")
              .font(.callout)
              .foregroundStyle(.secondary)
            Button("Clear History", role: .destructive) {
              model.clearRecents()
            }
            .controlSize(.small)
          }
        }
      }
    } header: {
      Text("Playback & Streaming")
    } footer: {
      Text(
        "Original quality copies H.264 video with zero re-encoding from the start. Seeking, non-H.264 codecs (HEVC/MKV), and upscaling transcode on the fly with VideoToolbox."
      )
    }
  }

  // MARK: 3. Web Player Appearance

  private var appearanceSection: some View {
    Section {
      Picker("Theme", selection: $settings.theme) {
        ForEach(PlayerTheme.allCases) { t in
          Text(t.title).tag(t)
        }
      }
      .pickerStyle(.segmented)

      Picker("Glass material", selection: $settings.glassStyle) {
        ForEach(PlayerGlassStyle.allCases) { g in
          Text(g.title).tag(g)
        }
      }
      .pickerStyle(.segmented)

      LabeledContent("Glass translucency") {
        HStack(spacing: 10) {
          Slider(value: $settings.glassTransparency, in: 0...100).frame(width: 200)
          Text("\(Int(settings.glassTransparency.rounded()))%")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 42, alignment: .trailing)
        }
      }

      LabeledContent("Backdrop blur") {
        HStack(spacing: 10) {
          Slider(value: $settings.glassBlur, in: 0...60).frame(width: 200)
          Text("\(Int(settings.glassBlur.rounded())) px")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 42, alignment: .trailing)
        }
      }

      LabeledContent("Background dimming") {
        HStack(spacing: 10) {
          Slider(value: $settings.backgroundDimming, in: 0...85).frame(width: 200)
          Text("\(Int(settings.backgroundDimming.rounded()))%")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 42, alignment: .trailing)
        }
      }

      Picker("Library background", selection: $settings.backgroundPreset) {
        ForEach(BackgroundPreset.allCases) { bg in
          Text(bg.title).tag(bg)
        }
      }

      if settings.backgroundPreset == .custom {
        LabeledContent("Custom image") {
          HStack(spacing: 8) {
            Text(
              settings.customBackgroundPath.isEmpty
                ? "None selected"
                : URL(fileURLWithPath: settings.customBackgroundPath).lastPathComponent
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: 180, alignment: .trailing)
            Button("Choose Image…") { model.chooseCustomBackground() }
              .controlSize(.small)
          }
        }
      }

      HStack {
        Text("Changes sync live to open player tabs.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Reset Appearance") {
          settings.resetAppearanceDefaults()
          Toast.shared.show("Appearance reset to defaults.")
        }
        .controlSize(.small)
      }
    } header: {
      Text("Player Appearance")
    }
  }

  // MARK: 4. Subtitles

  private var subtitlesSection: some View {
    Section {
      Picker("Default subtitle selection", selection: $settings.subtitleBehavior) {
        ForEach(SubtitleBehavior.allCases) { b in
          Text(b.title).tag(b)
        }
      }

      Picker("Subtitle size", selection: $settings.subtitleSize) {
        ForEach(SubtitleSize.allCases) { s in
          Text(s.title).tag(s)
        }
      }
      .pickerStyle(.segmented)

      Picker("Subtitle style", selection: $settings.subtitleStyle) {
        ForEach(SubtitleStyle.allCases) { s in
          Text(s.title).tag(s)
        }
      }
    } header: {
      Text("Subtitles")
    } footer: {
      Text(
        "Supports embedded text tracks (SRT, ASS, WebVTT) and matching external subtitle files. Use G and H during playback to nudge subtitle timing."
      )
    }
  }

  // MARK: 5. Server & FFmpeg Engine

  private var serverAndEngineSection: some View {
    Section {
      LabeledContent("Local server") {
        HStack(spacing: 8) {
          StatusDot(
            color: model.stats.isRunning ? KitbagUI.success : .secondary,
            active: model.stats.isRunning,
            size: 6.5
          )
          Text(
            model.stats.isRunning
              ? "Running on 127.0.0.1:\(model.stats.port)"
              : "Stopped"
          )
          .font(.callout.monospacedDigit())
          .foregroundStyle(model.stats.isRunning ? .primary : .secondary)

          if model.stats.isRunning {
            Button("Stop") { model.stopServer() }
              .controlSize(.small)
          } else {
            Button("Start") { model.startServerManually() }
              .controlSize(.small)
          }
        }
      }

      Picker("Server lifecycle", selection: $settings.serverMode) {
        ForEach(ServerMode.allCases) { mode in
          Text(mode.title).tag(mode)
        }
      }

      LabeledContent("Local port") {
        HStack(spacing: 8) {
          TextField("7077", text: $portText.value)
            .textFieldStyle(.roundedBorder)
            .font(.callout.monospacedDigit())
            .frame(width: 84)
            .onSubmit { commitPort() }
          if Int(portText.value) != settings.port {
            Button("Apply") { commitPort() }
              .controlSize(.small)
              .buttonStyle(.borderedProminent)
          }
          if settings.port != 7077 {
            Button("Default") {
              settings.port = 7077
              portText.value = "7077"
            }
            .controlSize(.small)
          }
        }
      }

      LabeledContent("FFmpeg engine") {
        HStack(spacing: 8) {
          if model.ffmpegStatus.isReady {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(KitbagUI.success)
            Text(model.ffmpegStatus.version.map { "v\($0)" } ?? "Installed")
              .font(.callout.monospacedDigit())
              .foregroundStyle(.secondary)
          } else {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(KitbagUI.warning)
            Text("Not found")
              .font(.callout)
              .foregroundStyle(KitbagUI.warning)
            if model.isInstallingFFmpeg {
              ProgressView().controlSize(.small)
            } else {
              Button("Install via Homebrew") {
                model.installFFmpegViaHomebrew()
              }
              .buttonStyle(.borderedProminent)
              .controlSize(.small)
            }
          }
          Button("Re-check") { model.refreshFFmpeg() }
            .controlSize(.small)
        }
      }

      LabeledContent("FFmpeg path") {
        HStack(spacing: 8) {
          Text(
            settings.customFFmpegPath.isEmpty
              ? (model.ffmpegStatus.ffmpegPath ?? "Auto-detect")
              : settings.customFFmpegPath
          )
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(maxWidth: 210, alignment: .trailing)
          Button("Locate…") { model.chooseCustomFFmpeg() }
            .controlSize(.small)
          if !settings.customFFmpegPath.isEmpty {
            Button("Auto") {
              settings.customFFmpegPath = ""
              model.refreshFFmpeg()
            }
            .controlSize(.small)
          }
        }
      }
    } header: {
      Text("Server & Engine")
    } footer: {
      Text(
        "The server binds exclusively to 127.0.0.1 and is never exposed to your network."
      )
    }
  }

  private func commitPort() {
    let trimmed = portText.value.trimmingCharacters(in: .whitespacesAndNewlines)
    if let parsed = Int(trimmed), parsed >= 1024, parsed <= 65535 {
      settings.port = parsed
      portText.value = String(parsed)
      Toast.shared.show("Server port updated to \(parsed).")
    } else {
      portText.value = String(settings.port)
      Toast.shared.show("Enter a valid port between 1024 and 65535.", error: true)
    }
  }

  private static func formatSpeed(_ speed: Double) -> String {
    if speed == floor(speed) {
      return "\(Int(speed))×"
    }
    return "\(speed)×"
  }
}
