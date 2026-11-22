import AppKit
import Foundation

// MARK: - Enums

public enum VideoQuality: String, CaseIterable, Codable, Identifiable, Sendable {
  case orig
  case enhance
  case p1080 = "1080"
  case p1440 = "1440"
  case p2160 = "2160"

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .orig: return "Original"
    case .enhance: return "Enhanced (Denoise + Sharpen)"
    case .p1080: return "Upscale to 1080p"
    case .p1440: return "Upscale to 1440p"
    case .p2160: return "Upscale to 4K"
    }
  }

  public var shortTitle: String {
    switch self {
    case .orig: return "Original"
    case .enhance: return "Enhanced"
    case .p1080: return "1080p"
    case .p1440: return "1440p"
    case .p2160: return "4K"
    }
  }
}

public enum SubtitleBehavior: String, CaseIterable, Codable, Identifiable, Sendable {
  case auto
  case externalOnly
  case defaultTrack
  case off

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .auto: return "Auto (External or English)"
    case .externalOnly: return "External files only"
    case .defaultTrack: return "Default embedded track"
    case .off: return "Off by default"
    }
  }
}

public enum PlayerTheme: String, CaseIterable, Codable, Identifiable, Sendable {
  case system
  case dark
  case light

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .system: return "System"
    case .dark: return "Dark"
    case .light: return "Light"
    }
  }
}

public enum PlayerGlassStyle: String, CaseIterable, Codable, Identifiable, Sendable {
  case clear
  case tinted

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .clear: return "Clear"
    case .tinted: return "Tinted"
    }
  }
}

public enum BackgroundPreset: String, CaseIterable, Codable, Identifiable, Sendable {
  case desktop
  case aurora
  case sunset
  case midnight
  case ember
  case graphite
  case custom

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .desktop: return "Desktop Wallpaper"
    case .aurora: return "Aurora"
    case .sunset: return "Sunset"
    case .midnight: return "Midnight"
    case .ember: return "Ember"
    case .graphite: return "Graphite"
    case .custom: return "Custom Image"
    }
  }
}

public enum SubtitleSize: String, CaseIterable, Codable, Identifiable, Sendable {
  case small
  case medium
  case large
  case extraLarge

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .small: return "Small"
    case .medium: return "Medium"
    case .large: return "Large"
    case .extraLarge: return "Extra Large"
    }
  }
}

public enum SubtitleStyle: String, CaseIterable, Codable, Identifiable, Sendable {
  case pill
  case classic
  case contrast

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .pill: return "Apple Pill"
    case .classic: return "Classic Shadow"
    case .contrast: return "High Contrast"
    }
  }
}

public enum ServerMode: String, CaseIterable, Codable, Identifiable, Sendable {
  case onDemand
  case alwaysOn

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .onDemand: return "Start on demand & stop when tabs close"
    case .alwaysOn: return "Keep running while Kitbag is open"
    }
  }
}

public struct LanguageOption: Identifiable, Hashable, Sendable {
  public let id: String
  public let title: String
}

// MARK: - Browser Discovery

public struct BrowserInfo: Identifiable, Hashable, Sendable {
  public let id: String  // bundle identifier
  public let name: String
  public let appURL: URL
}

public enum BrowserDiscovery {
  private static let probeURL = URL(string: "https://example.com")!

  public static func systemDefaultBrowser() -> BrowserInfo? {
    guard let url = NSWorkspace.shared.urlForApplication(toOpen: probeURL) else { return nil }
    return info(for: url)
  }

  public static func installedBrowsers() -> [BrowserInfo] {
    let urls = NSWorkspace.shared.urlsForApplications(toOpen: probeURL)
    var seen = Set<String>()
    var result: [BrowserInfo] = []
    for url in urls {
      guard FileManager.default.fileExists(atPath: url.path) else { continue }
      guard let browser = info(for: url), !seen.contains(browser.id) else { continue }
      seen.insert(browser.id)
      result.append(browser)
    }
    return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  public static func browser(for bundleID: String) -> BrowserInfo? {
    guard !bundleID.isEmpty,
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
      FileManager.default.fileExists(atPath: url.path)
    else { return nil }
    return info(for: url)
  }

  public static func icon(for appURL: URL, size: CGFloat = 16) -> NSImage {
    let img = NSWorkspace.shared.icon(forFile: appURL.path)
    img.size = NSSize(width: size, height: size)
    return img
  }

  private static func info(for url: URL) -> BrowserInfo? {
    guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
    let name =
      (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
      ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
      ?? url.deletingPathExtension().lastPathComponent
    return BrowserInfo(id: id, name: name, appURL: url)
  }
}

// MARK: - Recent Video Entry

public struct RecentVideo: Codable, Identifiable, Equatable, Sendable {
  public var id: String { path }
  public let path: String
  public var name: String
  public var position: Double
  public var duration: Double
  public var lastPlayedAt: Date

  public var progress: Double {
    guard duration > 0 else { return 0 }
    return min(max(position / duration, 0), 1)
  }

  public var canResume: Bool {
    duration > 0 && position > 15 && position < duration - 30
  }

  public init(
    path: String, name: String, position: Double, duration: Double, lastPlayedAt: Date = Date()
  ) {
    self.path = path
    self.name = name
    self.position = position
    self.duration = duration
    self.lastPlayedAt = lastPlayedAt
  }
}

// MARK: - Snapshot & Patch DTOs (Thread-Safe for HTTP Server)

public struct VideoPlayerConfigSnapshot: Codable, Equatable, Sendable {
  public var configVersion: Int
  public var defaultFolder: String
  public var defaultQuality: String
  public var defaultSpeed: Double
  public var skipSeconds: Int
  public var preferredAudioLanguage: String
  public var subtitleBehavior: String
  public var rememberPosition: Bool
  public var hardwareAcceleration: Bool
  public var theme: String
  public var glassStyle: String
  public var glassTransparency: Double
  public var glassBlur: Double
  public var backgroundDimming: Double
  public var backgroundPreset: String
  public var customBackgroundPath: String
  public var subtitleSize: String
  public var subtitleStyle: String
  public var port: Int
  public var serverMode: String
  public var customFFmpegPath: String
}

public struct WebConfigPatch: Codable, Sendable {
  public var theme: String?
  public var glassStyle: String?
  public var glassTransparency: Double?
  public var glassBlur: Double?
  public var backgroundDimming: Double?
  public var backgroundPreset: String?
  public var customBackgroundPath: String?
  public var subtitleSize: String?
  public var subtitleStyle: String?
  public var defaultQuality: String?
  public var defaultSpeed: Double?
  public var skipSeconds: Int?
}

// MARK: - Settings Store

@MainActor
public final class VideoPlayerSettings: ObservableObject {
  public nonisolated static let supportedLanguages: [LanguageOption] = [
    LanguageOption(id: "default", title: "File Default"),
    LanguageOption(id: "eng", title: "English"),
    LanguageOption(id: "jpn", title: "Japanese"),
    LanguageOption(id: "hin", title: "Hindi"),
    LanguageOption(id: "spa", title: "Spanish"),
    LanguageOption(id: "fra", title: "French"),
    LanguageOption(id: "deu", title: "German"),
    LanguageOption(id: "kor", title: "Korean"),
    LanguageOption(id: "zho", title: "Chinese"),
  ]

  public nonisolated static let speedOptions: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
  public nonisolated static let skipOptions: [Int] = [5, 10, 15, 30]

  private enum Key {
    static let prefix = "kitbag.videoplayer."
    static let browserBundleID = prefix + "browserBundleID"
    static let defaultFolder = prefix + "defaultFolder"
    static let defaultQuality = prefix + "defaultQuality"
    static let defaultSpeed = prefix + "defaultSpeed"
    static let skipSeconds = prefix + "skipSeconds"
    static let preferredAudioLanguage = prefix + "preferredAudioLanguage"
    static let subtitleBehavior = prefix + "subtitleBehavior"
    static let rememberPosition = prefix + "rememberPosition"
    static let hardwareAcceleration = prefix + "hardwareAcceleration"
    static let theme = prefix + "theme"
    static let glassStyle = prefix + "glassStyle"
    static let glassTransparency = prefix + "glassTransparency"
    static let glassBlur = prefix + "glassBlur"
    static let backgroundDimming = prefix + "backgroundDimming"
    static let backgroundPreset = prefix + "backgroundPreset"
    static let customBackgroundPath = prefix + "customBackgroundPath"
    static let subtitleSize = prefix + "subtitleSize"
    static let subtitleStyle = prefix + "subtitleStyle"
    static let port = prefix + "port"
    static let serverMode = prefix + "serverMode"
    static let customFFmpegPath = prefix + "customFFmpegPath"
    static let recents = prefix + "recents"
  }

  private let defaults: UserDefaults
  public var onChange: ((VideoPlayerConfigSnapshot) -> Void)?
  public var onServerConfigChange: (() -> Void)?

  @Published public private(set) var configVersion: Int = 1

  /// Empty string means follow macOS System Default browser.
  @Published public var browserBundleID: String {
    didSet {
      defaults.set(browserBundleID, forKey: Key.browserBundleID)
      bump()
    }
  }

  @Published public var defaultFolder: String {
    didSet {
      defaults.set(defaultFolder, forKey: Key.defaultFolder)
      bump()
    }
  }

  @Published public var defaultQuality: VideoQuality {
    didSet {
      defaults.set(defaultQuality.rawValue, forKey: Key.defaultQuality)
      bump()
    }
  }

  @Published public var defaultSpeed: Double {
    didSet {
      defaults.set(defaultSpeed, forKey: Key.defaultSpeed)
      bump()
    }
  }

  @Published public var skipSeconds: Int {
    didSet {
      defaults.set(skipSeconds, forKey: Key.skipSeconds)
      bump()
    }
  }

  @Published public var preferredAudioLanguage: String {
    didSet {
      defaults.set(preferredAudioLanguage, forKey: Key.preferredAudioLanguage)
      bump()
    }
  }

  @Published public var subtitleBehavior: SubtitleBehavior {
    didSet {
      defaults.set(subtitleBehavior.rawValue, forKey: Key.subtitleBehavior)
      bump()
    }
  }

  @Published public var rememberPosition: Bool {
    didSet {
      defaults.set(rememberPosition, forKey: Key.rememberPosition)
      bump()
    }
  }

  @Published public var hardwareAcceleration: Bool {
    didSet {
      defaults.set(hardwareAcceleration, forKey: Key.hardwareAcceleration)
      bump()
    }
  }

  @Published public var theme: PlayerTheme {
    didSet {
      defaults.set(theme.rawValue, forKey: Key.theme)
      bump()
    }
  }

  @Published public var glassStyle: PlayerGlassStyle {
    didSet {
      defaults.set(glassStyle.rawValue, forKey: Key.glassStyle)
      bump()
    }
  }

  @Published public var glassTransparency: Double {
    didSet {
      let clamped = min(max(glassTransparency, 0), 100)
      if clamped != glassTransparency {
        glassTransparency = clamped
        return
      }
      defaults.set(clamped, forKey: Key.glassTransparency)
      bump()
    }
  }

  @Published public var glassBlur: Double {
    didSet {
      let clamped = min(max(glassBlur, 0), 60)
      if clamped != glassBlur {
        glassBlur = clamped
        return
      }
      defaults.set(clamped, forKey: Key.glassBlur)
      bump()
    }
  }

  @Published public var backgroundDimming: Double {
    didSet {
      let clamped = min(max(backgroundDimming, 0), 85)
      if clamped != backgroundDimming {
        backgroundDimming = clamped
        return
      }
      defaults.set(clamped, forKey: Key.backgroundDimming)
      bump()
    }
  }

  @Published public var backgroundPreset: BackgroundPreset {
    didSet {
      defaults.set(backgroundPreset.rawValue, forKey: Key.backgroundPreset)
      bump()
    }
  }

  @Published public var customBackgroundPath: String {
    didSet {
      defaults.set(customBackgroundPath, forKey: Key.customBackgroundPath)
      bump()
    }
  }

  @Published public var subtitleSize: SubtitleSize {
    didSet {
      defaults.set(subtitleSize.rawValue, forKey: Key.subtitleSize)
      bump()
    }
  }

  @Published public var subtitleStyle: SubtitleStyle {
    didSet {
      defaults.set(subtitleStyle.rawValue, forKey: Key.subtitleStyle)
      bump()
    }
  }

  @Published public var port: Int {
    didSet {
      let clamped = Self.clampPort(port)
      if clamped != port {
        port = clamped
        return
      }
      defaults.set(clamped, forKey: Key.port)
      bump()
      onServerConfigChange?()
    }
  }

  @Published public var serverMode: ServerMode {
    didSet {
      defaults.set(serverMode.rawValue, forKey: Key.serverMode)
      bump()
      onServerConfigChange?()
    }
  }

  @Published public var customFFmpegPath: String {
    didSet {
      defaults.set(customFFmpegPath, forKey: Key.customFFmpegPath)
      bump()
    }
  }

  @Published public private(set) var recents: [RecentVideo]

  private var suppressNotify = false

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    browserBundleID = defaults.string(forKey: Key.browserBundleID) ?? ""
    defaultFolder = defaults.string(forKey: Key.defaultFolder) ?? "~/Movies"
    defaultQuality =
      defaults.string(forKey: Key.defaultQuality).flatMap(VideoQuality.init(rawValue:)) ?? .orig
    let storedSpeed = defaults.object(forKey: Key.defaultSpeed) as? Double ?? 1.0
    defaultSpeed = Self.speedOptions.contains(storedSpeed) ? storedSpeed : 1.0
    let storedSkip = defaults.object(forKey: Key.skipSeconds) as? Int ?? 10
    skipSeconds = Self.skipOptions.contains(storedSkip) ? storedSkip : 10
    preferredAudioLanguage = defaults.string(forKey: Key.preferredAudioLanguage) ?? "default"
    subtitleBehavior =
      defaults.string(forKey: Key.subtitleBehavior).flatMap(SubtitleBehavior.init(rawValue:))
      ?? .auto
    rememberPosition = (defaults.object(forKey: Key.rememberPosition) as? Bool) ?? true
    hardwareAcceleration = (defaults.object(forKey: Key.hardwareAcceleration) as? Bool) ?? true
    theme = defaults.string(forKey: Key.theme).flatMap(PlayerTheme.init(rawValue:)) ?? .system
    glassStyle =
      defaults.string(forKey: Key.glassStyle).flatMap(PlayerGlassStyle.init(rawValue:)) ?? .clear
    glassTransparency = (defaults.object(forKey: Key.glassTransparency) as? Double) ?? 42
    glassBlur = (defaults.object(forKey: Key.glassBlur) as? Double) ?? 28
    backgroundDimming = (defaults.object(forKey: Key.backgroundDimming) as? Double) ?? 42
    backgroundPreset =
      defaults.string(forKey: Key.backgroundPreset).flatMap(BackgroundPreset.init(rawValue:))
      ?? .desktop
    customBackgroundPath = defaults.string(forKey: Key.customBackgroundPath) ?? ""
    subtitleSize =
      defaults.string(forKey: Key.subtitleSize).flatMap(SubtitleSize.init(rawValue:)) ?? .medium
    subtitleStyle =
      defaults.string(forKey: Key.subtitleStyle).flatMap(SubtitleStyle.init(rawValue:)) ?? .pill
    let storedPort = defaults.object(forKey: Key.port) as? Int ?? 7077
    port = Self.clampPort(storedPort)
    serverMode =
      defaults.string(forKey: Key.serverMode).flatMap(ServerMode.init(rawValue:)) ?? .onDemand
    customFFmpegPath = defaults.string(forKey: Key.customFFmpegPath) ?? ""
    if let data = defaults.data(forKey: Key.recents),
      let decoded = try? JSONDecoder().decode([RecentVideo].self, from: data)
    {
      recents = decoded
    } else {
      recents = []
    }
  }

  public static func clampPort(_ p: Int) -> Int {
    min(max(p, 1024), 65535)
  }

  public func snapshot() -> VideoPlayerConfigSnapshot {
    VideoPlayerConfigSnapshot(
      configVersion: configVersion,
      defaultFolder: defaultFolder,
      defaultQuality: defaultQuality.rawValue,
      defaultSpeed: defaultSpeed,
      skipSeconds: skipSeconds,
      preferredAudioLanguage: preferredAudioLanguage,
      subtitleBehavior: subtitleBehavior.rawValue,
      rememberPosition: rememberPosition,
      hardwareAcceleration: hardwareAcceleration,
      theme: theme.rawValue,
      glassStyle: glassStyle.rawValue,
      glassTransparency: glassTransparency,
      glassBlur: glassBlur,
      backgroundDimming: backgroundDimming,
      backgroundPreset: backgroundPreset.rawValue,
      customBackgroundPath: customBackgroundPath,
      subtitleSize: subtitleSize.rawValue,
      subtitleStyle: subtitleStyle.rawValue,
      port: port,
      serverMode: serverMode.rawValue,
      customFFmpegPath: customFFmpegPath
    )
  }

  /// Applies changes pushed from the web UI appearance popover, keeping Kitbag Settings in sync.
  public func apply(patch: WebConfigPatch) {
    suppressNotify = true
    defer {
      suppressNotify = false
      bump()
    }
    if let t = patch.theme.flatMap(PlayerTheme.init(rawValue:)) { theme = t }
    if let g = patch.glassStyle.flatMap(PlayerGlassStyle.init(rawValue:)) { glassStyle = g }
    if let a = patch.glassTransparency { glassTransparency = min(max(a, 0), 100) }
    if let b = patch.glassBlur { glassBlur = min(max(b, 0), 60) }
    if let d = patch.backgroundDimming { backgroundDimming = min(max(d, 0), 85) }
    if let bg = patch.backgroundPreset.flatMap(BackgroundPreset.init(rawValue:)) {
      backgroundPreset = bg
    }
    if let img = patch.customBackgroundPath { customBackgroundPath = img }
    if let ss = patch.subtitleSize.flatMap(SubtitleSize.init(rawValue:)) { subtitleSize = ss }
    if let st = patch.subtitleStyle.flatMap(SubtitleStyle.init(rawValue:)) { subtitleStyle = st }
    if let q = patch.defaultQuality.flatMap(VideoQuality.init(rawValue:)) { defaultQuality = q }
    if let sp = patch.defaultSpeed, Self.speedOptions.contains(sp) { defaultSpeed = sp }
    if let sk = patch.skipSeconds, Self.skipOptions.contains(sk) { skipSeconds = sk }
  }

  public func recordProgress(path: String, position: Double, duration: Double) {
    guard !path.isEmpty else { return }
    let cleanPath = VideoMediaEngine.expandPath(path)
    let name = URL(fileURLWithPath: cleanPath).lastPathComponent
    let savedPos: Double
    if !rememberPosition {
      savedPos = 0
    } else if duration > 0 && position > 15 && position < duration - 30 {
      savedPos = position
    } else {
      savedPos = 0
    }

    var updated = recents.filter { $0.path != cleanPath }
    updated.insert(
      RecentVideo(
        path: cleanPath, name: name, position: savedPos, duration: max(0, duration),
        lastPlayedAt: Date()),
      at: 0
    )
    if updated.count > 20 { updated = Array(updated.prefix(20)) }
    recents = updated
    persistRecents()
  }

  public func removeRecent(path: String) {
    recents.removeAll { $0.path == path }
    persistRecents()
  }

  public func clearRecents() {
    recents = []
    persistRecents()
    bump()
  }

  public func resetAppearanceDefaults() {
    suppressNotify = true
    theme = .system
    glassStyle = .clear
    glassTransparency = 42
    glassBlur = 28
    backgroundDimming = 42
    backgroundPreset = .desktop
    customBackgroundPath = ""
    subtitleSize = .medium
    subtitleStyle = .pill
    suppressNotify = false
    bump()
  }

  private func persistRecents() {
    if let data = try? JSONEncoder().encode(recents) {
      defaults.set(data, forKey: Key.recents)
    }
  }

  private func bump() {
    guard !suppressNotify else { return }
    configVersion += 1
    onChange?(snapshot())
  }
}
