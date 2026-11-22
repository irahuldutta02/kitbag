import AppKit
import Carbon.HIToolbox
import KitbagCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public final class VideoPlayerModel: ObservableObject {
  public static let defaultShortcut = KeyShortcut(
    keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(controlKey | optionKey), label: "P")
  private static let shortcutPrefix = "kitbag.videoplayer.shortcut"

  public let settings: VideoPlayerSettings
  private let defaults: UserDefaults
  private let engine = VideoMediaEngine()
  private var server: LocalHTTPServer?
  private var serverBridge: ServerBridge?
  private let hotKey = GlobalHotKey()
  private var hotKeyEnabled = false

  @Published public private(set) var stats: ServerStats = .stopped
  @Published public private(set) var ffmpegStatus = FFmpegStatus(
    ffmpegPath: nil, ffprobePath: nil, version: nil)
  @Published public private(set) var installedBrowsers: [BrowserInfo] = []
  @Published public private(set) var systemDefaultBrowser: BrowserInfo?
  @Published public private(set) var shortcut: KeyShortcut?
  @Published public private(set) var shortcutWorks = true
  @Published public private(set) var isStarting = false
  @Published public private(set) var isInstallingFFmpeg = false
  @Published public var errorMessage: String?
  @Published public var dropTargeted = false

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.settings = VideoPlayerSettings(defaults: defaults)
    self.shortcut = KeyShortcut.load(
      from: defaults, prefix: Self.shortcutPrefix, default: nil)

    let bridge = ServerBridge(
      initialConfig: settings.snapshot(),
      initialRecents: settings.recents
    )
    bridge.owner = self
    self.serverBridge = bridge
    self.server = LocalHTTPServer(engine: engine, delegate: bridge)

    settings.onChange = { [weak self, weak bridge] snap in
      bridge?.updateConfig(snap)
      self?.objectWillChange.send()
    }
    settings.onServerConfigChange = { [weak self] in
      self?.handleServerConfigChange()
    }
  }

  public func start(registerHotKey: Bool = true) {
    refreshBrowsers()
    refreshFFmpeg()
    if registerHotKey && !hotKeyEnabled {
      hotKeyEnabled = true
      hotKey.onPress = {
        NotificationCenter.default.post(name: .kitbagOpenTab, object: "videoplayer")
      }
      registerShortcut()
    }
    if settings.serverMode == .alwaysOn {
      Task { await ensureServerRunning() }
    }
  }

  public func stop() {
    hotKey.unregister()
    hotKeyEnabled = false
    server?.stop()
    stats = .stopped
  }

  public func refresh() {
    refreshBrowsers()
    refreshFFmpeg()
    serverBridge?.updateRecents(settings.recents)
  }

  // MARK: - Destination Browser

  public var effectiveBrowser: BrowserInfo? {
    if !settings.browserBundleID.isEmpty,
      let chosen = BrowserDiscovery.browser(for: settings.browserBundleID)
    {
      return chosen
    }
    return systemDefaultBrowser
  }

  public var destinationBrowserName: String {
    if settings.browserBundleID.isEmpty {
      return systemDefaultBrowser?.name ?? "Default Browser"
    }
    if let chosen = BrowserDiscovery.browser(for: settings.browserBundleID) {
      return chosen.name
    }
    return systemDefaultBrowser?.name ?? "Default Browser"
  }

  public var selectedBrowserMissing: Bool {
    !settings.browserBundleID.isEmpty
      && BrowserDiscovery.browser(for: settings.browserBundleID) == nil
  }

  public func refreshBrowsers() {
    systemDefaultBrowser = BrowserDiscovery.systemDefaultBrowser()
    installedBrowsers = BrowserDiscovery.installedBrowsers()
  }

  // MARK: - Server Lifecycle

  public var serverBaseURL: URL? {
    guard stats.isRunning, stats.port > 0 else { return nil }
    return URL(string: "http://127.0.0.1:\(stats.port)")
  }

  @discardableResult
  public func ensureServerRunning() async -> UInt16? {
    if let server, server.isRunning, server.currentPort > 0 {
      return server.currentPort
    }
    guard let server else { return nil }
    isStarting = true
    errorMessage = nil
    defer { isStarting = false }

    do {
      let port = try await server.start(port: UInt16(settings.port))
      if settings.serverMode == .onDemand {
        server.scheduleAutoStopIfNeeded(graceSeconds: 45)
      }
      return port
    } catch {
      errorMessage = "Port \(settings.port) couldn't be opened (\(error.localizedDescription)). Try another port in Settings."
      return nil
    }
  }

  public func startServerManually() {
    Task { _ = await ensureServerRunning() }
  }

  public func stopServer() {
    server?.stop()
    stats = .stopped
    errorMessage = nil
  }

  private func handleServerConfigChange() {
    guard let server else { return }
    if settings.serverMode == .alwaysOn {
      if !server.isRunning || Int(server.currentPort) != settings.port {
        Task {
          server.stop()
          _ = await ensureServerRunning()
        }
      }
    } else if server.isRunning && Int(server.currentPort) != settings.port {
      Task {
        server.stop()
        _ = await ensureServerRunning()
      }
    }
  }

  // MARK: - Open in Browser

  public func openPlayer(filePath: String? = nil, autoPlay: Bool = false) {
    Task {
      guard let port = await ensureServerRunning() else { return }
      var comps = URLComponents()
      comps.scheme = "http"
      comps.host = "127.0.0.1"
      comps.port = Int(port)
      comps.path = "/"
      if let filePath, !filePath.isEmpty {
        let key = autoPlay ? "play" : "file"
        comps.queryItems = [URLQueryItem(name: key, value: filePath)]
      }
      guard let url = comps.url else { return }
      NotificationCenter.default.post(name: .kitbagCloseMenu, object: nil)
      launchInDestinationBrowser(url)
    }
  }

  public func chooseVideoAndOpen() {
    NotificationCenter.default.post(name: .kitbagCloseMenu, object: nil)
    Task {
      if let picked = await pickFile(kind: "video") {
        openPlayer(filePath: picked, autoPlay: false)
      }
    }
  }

  public func chooseDefaultFolder() {
    let panel = NSOpenPanel()
    panel.title = "Choose Default Video Folder"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    let current = VideoMediaEngine.expandPath(settings.defaultFolder)
    if FileManager.default.fileExists(atPath: current) {
      panel.directoryURL = URL(fileURLWithPath: current)
    }
    NSApp.activate(ignoringOtherApps: true)
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor in
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if url.path == home {
          self?.settings.defaultFolder = "~"
        } else if url.path.hasPrefix(home + "/") {
          self?.settings.defaultFolder = "~/" + url.path.dropFirst(home.count + 1)
        } else {
          self?.settings.defaultFolder = url.path
        }
      }
    }
  }

  public func chooseCustomBackground() {
    Task {
      if let picked = await pickFile(kind: "image") {
        settings.customBackgroundPath = picked
        settings.backgroundPreset = .custom
      }
    }
  }

  public func chooseCustomFFmpeg() {
    let panel = NSOpenPanel()
    panel.title = "Locate ffmpeg Binary or Folder"
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    NSApp.activate(ignoringOtherApps: true)
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor in
        self?.settings.customFFmpegPath = url.path
        self?.refreshFFmpeg()
      }
    }
  }

  @discardableResult
  public func handleDroppedURLs(_ urls: [URL]) -> Bool {
    if let video = urls.first(where: { VideoMediaEngine.isVideoPath($0.path) }) {
      openPlayer(filePath: video.path, autoPlay: false)
      return true
    }
    if let folder = urls.first(where: {
      var isDir: ObjCBool = false
      return FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDir) && isDir.boolValue
    }) {
      openPlayer(filePath: folder.path, autoPlay: false)
      return true
    }
    errorMessage = "Drop a video file (.mkv, .mp4, .mov, .webm…) or folder."
    return false
  }

  private func launchInDestinationBrowser(_ url: URL) {
    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    if !settings.browserBundleID.isEmpty,
      let appURL = BrowserDiscovery.browser(for: settings.browserBundleID)?.appURL
    {
      NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) {
        [weak self] _, err in
        if let err {
          Task { @MainActor [weak self] in
            self?.errorMessage = "Couldn't open browser: \(err.localizedDescription)"
          }
        }
      }
    } else {
      NSWorkspace.shared.open(url)
    }
  }

  // MARK: - Native File Picker (for both UI and /api/pick)

  public func pickFile(kind: String) async -> String? {
    await withCheckedContinuation { cont in
      let panel = NSOpenPanel()
      panel.canChooseFiles = true
      panel.canChooseDirectories = false
      panel.allowsMultipleSelection = false

      switch kind {
      case "subtitle":
        panel.title = "Choose a Subtitle File"
        panel.allowedContentTypes = VideoMediaEngine.subtitleExtensions.compactMap {
          UTType(filenameExtension: String($0.dropFirst()))
        }
      case "image":
        panel.title = "Choose a Background Image"
        panel.allowedContentTypes = [.image]
      default:
        panel.title = "Choose a Video File"
        var types: [UTType] = [.movie, .video]
        for ext in VideoMediaEngine.videoExtensions {
          if let t = UTType(filenameExtension: String(ext.dropFirst())) {
            types.append(t)
          }
        }
        panel.allowedContentTypes = types
        let defaultDir = VideoMediaEngine.expandPath(settings.defaultFolder)
        if FileManager.default.fileExists(atPath: defaultDir) {
          panel.directoryURL = URL(fileURLWithPath: defaultDir)
        }
      }

      NSApp.activate(ignoringOtherApps: true)
      panel.begin { response in
        cont.resume(returning: response == .OK ? panel.url?.path : nil)
      }
    }
  }

  // MARK: - FFmpeg Check & Homebrew Install

  public func refreshFFmpeg() {
    let custom = settings.customFFmpegPath
    Task.detached(priority: .utility) {
      let status = VideoMediaEngine.checkFFmpeg(customFFmpegPath: custom)
      await MainActor.run { [weak self] in
        self?.ffmpegStatus = status
      }
    }
  }

  public func installFFmpegViaHomebrew() {
    guard !isInstallingFFmpeg else { return }
    guard let brew = Shell.brewPath else {
      Toast.shared.show("Homebrew isn't installed (brew.sh).", error: true)
      return
    }
    isInstallingFFmpeg = true
    TerminalModel.shared.isOpen = true
    TerminalModel.shared.echo("$ brew install ffmpeg\n")
    Task {
      let res = await Shell.run(brew, ["install", "ffmpeg"], env: ["NONINTERACTIVE": "1"]) { chunk in
        TerminalModel.shared.echo(chunk)
      }
      isInstallingFFmpeg = false
      refreshFFmpeg()
      if res?.ok == true {
        Toast.shared.show("FFmpeg installed and ready.")
      } else {
        Toast.shared.show("FFmpeg installation failed. Check the terminal output.", error: true)
      }
    }
  }

  // MARK: - Recents & Progress

  public func syncProgress(path: String, position: Double, duration: Double) {
    settings.recordProgress(path: path, position: position, duration: duration)
    serverBridge?.updateRecents(settings.recents)
  }

  public func clearRecents() {
    settings.clearRecents()
    serverBridge?.updateRecents([])
    Toast.shared.show("Cleared recent videos and saved positions.")
  }

  public func removeRecent(_ item: RecentVideo) {
    settings.removeRecent(path: item.path)
    serverBridge?.updateRecents(settings.recents)
  }

  // MARK: - Global Shortcut

  private func registerShortcut() {
    guard let s = shortcut else {
      hotKey.unregister()
      shortcutWorks = true
      return
    }
    shortcutWorks = hotKey.register(keyCode: s.keyCode, modifiers: s.modifiers)
  }

  @discardableResult
  public func setShortcut(_ new: KeyShortcut?) -> Bool {
    if hotKeyEnabled, let new {
      guard hotKey.register(keyCode: new.keyCode, modifiers: new.modifiers) else {
        if let old = shortcut { hotKey.register(keyCode: old.keyCode, modifiers: old.modifiers) }
        return false
      }
    } else if hotKeyEnabled {
      hotKey.unregister()
    }
    shortcut = new
    shortcutWorks = true
    KeyShortcut.save(new, to: defaults, prefix: Self.shortcutPrefix)
    return true
  }

  public func pauseHotKey(_ pause: Bool) {
    guard hotKeyEnabled else { return }
    if pause { hotKey.unregister() } else { registerShortcut() }
  }

  // MARK: - Internal bridge updates

  fileprivate func applyPatchFromServer(_ patch: WebConfigPatch) {
    settings.apply(patch: patch)
  }

  fileprivate func updateStats(_ newStats: ServerStats) {
    stats = newStats
  }
}

// MARK: - Thread-Safe Delegate Bridge

private final class ServerBridge: LocalVideoServerDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private var config: VideoPlayerConfigSnapshot
  private var recents: [RecentVideo]
  weak var owner: VideoPlayerModel?

  init(initialConfig: VideoPlayerConfigSnapshot, initialRecents: [RecentVideo]) {
    self.config = initialConfig
    self.recents = initialRecents
  }

  func updateConfig(_ snap: VideoPlayerConfigSnapshot) {
    lock.lock()
    config = snap
    lock.unlock()
  }

  func updateRecents(_ list: [RecentVideo]) {
    lock.lock()
    recents = list
    lock.unlock()
  }

  func serverConfigSnapshot() -> VideoPlayerConfigSnapshot {
    lock.lock()
    defer { lock.unlock() }
    return config
  }

  func serverApplyConfigPatch(_ patch: WebConfigPatch) -> VideoPlayerConfigSnapshot {
    lock.lock()
    var next = config
    if let v = patch.theme, PlayerTheme(rawValue: v) != nil { next.theme = v }
    if let v = patch.glassStyle, PlayerGlassStyle(rawValue: v) != nil { next.glassStyle = v }
    if let v = patch.glassTransparency { next.glassTransparency = min(max(v, 0), 100) }
    if let v = patch.glassBlur { next.glassBlur = min(max(v, 0), 60) }
    if let v = patch.backgroundDimming { next.backgroundDimming = min(max(v, 0), 85) }
    if let v = patch.backgroundPreset, BackgroundPreset(rawValue: v) != nil {
      next.backgroundPreset = v
    }
    if let v = patch.customBackgroundPath { next.customBackgroundPath = v }
    if let v = patch.subtitleSize, SubtitleSize(rawValue: v) != nil { next.subtitleSize = v }
    if let v = patch.subtitleStyle, SubtitleStyle(rawValue: v) != nil { next.subtitleStyle = v }
    if let v = patch.defaultQuality, VideoQuality(rawValue: v) != nil { next.defaultQuality = v }
    if let v = patch.defaultSpeed, VideoPlayerSettings.speedOptions.contains(v) {
      next.defaultSpeed = v
    }
    if let v = patch.skipSeconds, VideoPlayerSettings.skipOptions.contains(v) {
      next.skipSeconds = v
    }
    next.configVersion += 1
    config = next
    lock.unlock()

    Task { @MainActor [weak owner] in
      owner?.applyPatchFromServer(patch)
    }
    return next
  }

  func serverRecents() -> [RecentVideo] {
    lock.lock()
    defer { lock.unlock() }
    return recents
  }

  func serverRecordProgress(path: String, position: Double, duration: Double) {
    Task { @MainActor [weak owner] in
      owner?.syncProgress(path: path, position: position, duration: duration)
    }
  }

  func serverPickFile(kind: String) async -> String? {
    await MainActor.run { owner }?.pickFile(kind: kind)
  }

  func serverStatsChanged(_ stats: ServerStats) {
    Task { @MainActor [weak owner] in
      owner?.updateStats(stats)
    }
  }

  func serverDidAutoStop() {
    Task { @MainActor [weak owner] in
      owner?.updateStats(.stopped)
    }
  }
}
