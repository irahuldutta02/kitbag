import AppKit
import Foundation

/// Finds new Kitbag versions on GitHub, downloads and checks them, and swaps the app in.
///
/// Nothing is installed without you pressing a button, every download is checked against a SHA-256
/// and (when this copy has a stable signature) against the signature of the running app, and the old
/// app is put back if the new one fails to start. The only request made is the public GitHub
/// release list; nothing about you or your Mac is sent.
@MainActor
public final class Updater: ObservableObject {
  public static let shared = Updater()
  public static let defaultRepo = "irahuldutta02/kitbag"

  public enum State: Equatable {
    case idle
    case checking
    case upToDate
    case available(UpdateRelease)
    case downloading(Double)
    case preparing(UpdateRelease)
    case ready(UpdateRelease)
    case installing
    case failed(String)
  }

  @Published public private(set) var state: State = .idle
  @Published public private(set) var lastChecked: Date?
  @Published public private(set) var skippedVersion: String?
  /// The last failure happened while downloading or installing an update (not while merely checking).
  @Published public private(set) var failedWhileUpdating = false
  @Published public var automatic: Bool { didSet { defaults.set(automatic, forKey: Keys.auto) } }

  public let currentVersion: AppVersion
  public let repo: String
  private let bundleID: String
  private let appURL: URL
  private let defaults: UserDefaults
  private let fetch: (URLRequest) async throws -> (Data, URLResponse)
  private let now: () -> Date
  private let workRoot: URL
  private var staged: (app: URL, release: UpdateRelease, dir: URL)?
  private var timer: Timer?
  private var task: Task<Void, Never>?
  private let requirement: String?

  private enum Keys {
    static let auto = "kitbag.update.auto"
    static let last = "kitbag.update.lastCheck"
    static let skipped = "kitbag.update.skipped"
  }

  public init(
    bundle: Bundle = .main, defaults: UserDefaults = .standard,
    fetch: @escaping (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) },
    now: @escaping () -> Date = Date.init,
    workRoot: URL? = nil, requirement: String?? = nil,
    currentVersion: AppVersion? = nil, repo: String? = nil, appURL: URL? = nil
  ) {
    self.defaults = defaults
    self.fetch = fetch
    self.now = now
    self.currentVersion = currentVersion
      ?? (bundle.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init) ?? AppVersion("0.0.0")!
    self.repo = repo ?? (bundle.infoDictionary?["KitbagUpdateRepo"] as? String) ?? Self.defaultRepo
    bundleID = bundle.bundleIdentifier ?? ""
    self.appURL = appURL ?? bundle.bundleURL
    self.workRoot = workRoot ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Kitbag/Update", isDirectory: true)
    self.requirement = requirement ?? CodeIdentity.requirement(of: appURL ?? bundle.bundleURL)
    automatic = (defaults.object(forKey: Keys.auto) as? Bool) ?? true
    lastChecked = defaults.object(forKey: Keys.last) as? Date
    skippedVersion = defaults.string(forKey: Keys.skipped)
  }

  // MARK: What this copy of the app can do

  /// Why the update can't be installed from here, if it can't.
  public var installBlocker: String? {
    if appURL.pathExtension != "app" || appURL.path.contains("/.build/") {
      return "This copy of Kitbag isn't installed as an app, so it can't update itself."
    }
    let parent = appURL.deletingLastPathComponent().path
    if !FileManager.default.isWritableFile(atPath: parent) {
      return "Kitbag lives in a folder you can't change (\(parent)). Download the update and replace it yourself."
    }
    return nil
  }

  /// False when the app has no stable signature, so macOS will ask again for permissions after an update.
  public var hasStableSignature: Bool { CodeIdentity.isPinned(requirement) }

  public var isBusy: Bool {
    switch state {
    case .checking, .downloading, .preparing, .installing: return true
    default: return false
    }
  }

  /// Whether the menu pop-up should show its update strip.
  public var bannerVisible: Bool {
    switch state {
    case .available, .downloading, .preparing, .ready, .installing: return true
    case .failed: return failedWhileUpdating
    default: return false
    }
  }

  /// An update the person hasn't dealt with yet (for the menu banner).
  public var pendingRelease: UpdateRelease? {
    switch state {
    case .available(let r), .preparing(let r), .ready(let r): return r
    default: return nil
    }
  }

  // MARK: Checking

  /// Checks now, and then about once a day while Kitbag is running (if automatic checks are on).
  public func start() {
    guard timer == nil else { return }
    let t = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.checkIfDue() }
    }
    t.tolerance = 300
    RunLoop.main.add(t, forMode: .common)
    timer = t
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.checkIfDue() }
  }

  public func stop() {
    timer?.invalidate()
    timer = nil
  }

  func checkIfDue() {
    guard automatic, !isBusy, pendingRelease == nil else { return }
    if let last = lastChecked, now().timeIntervalSince(last) < 22 * 3600 { return }
    Task { await check(userInitiated: false) }
  }

  public func checkNow() { Task { await check(userInitiated: true) } }

  public func check(userInitiated: Bool) async {
    guard !isBusy else { return }
    failedWhileUpdating = false
    guard UpdateTrust.isValidRepo(repo) else {
      if userInitiated { state = .failed(UpdateError.notConfigured.localizedDescription) }
      return
    }
    let before = state
    state = .checking
    do {
      let release = try await latestRelease()
      lastChecked = now()
      defaults.set(lastChecked, forKey: Keys.last)
      if release.version > currentVersion {
        state = (!userInitiated && skippedVersion == release.versionText) ? .upToDate : .available(release)
      } else {
        state = .upToDate
      }
    } catch {
      // A quiet background check shouldn't bother anyone with an error.
      state = userInitiated ? .failed(error.localizedDescription) : before
    }
  }

  private func latestRelease() async throws -> UpdateRelease {
    var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
    request.timeoutInterval = 20
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("Kitbag-Updater", forHTTPHeaderField: "User-Agent")  // a generic name; nothing about you
    let data: Data, response: URLResponse
    do { (data, response) = try await fetch(request) } catch { throw UpdateError.network(error.localizedDescription) }
    if let http = response as? HTTPURLResponse {
      switch http.statusCode {
      case 200: break
      case 404: throw UpdateError.noReleases
      case 403, 429: throw UpdateError.rateLimited
      default: throw UpdateError.network("GitHub answered \(http.statusCode).")
      }
    }
    return try ReleaseParser.parse(data)
  }

  public func skip() {
    guard case .available(let r) = state else { return }
    skippedVersion = r.versionText
    defaults.set(r.versionText, forKey: Keys.skipped)
    state = .upToDate
  }

  // MARK: Downloading and getting ready

  public func update() { task = Task { await download() } }

  public func download() async {
    guard case .available(let release) = state else { return }
    failedWhileUpdating = false
    if let blocker = installBlocker {
      failedWhileUpdating = true
      state = .failed(blocker)
      return
    }
    let dir = workRoot.appendingPathComponent(UpdateTrust.safeName(release.versionText), isDirectory: true)
    do {
      try? FileManager.default.removeItem(at: dir)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      state = .downloading(0)
      let dmg = try await UpdateDownload.fetch(release.dmgURL, to: dir.appendingPathComponent(UpdateTrust.safeName(release.dmgName))) {
        [weak self] p in Task { @MainActor in self?.setProgress(p) }
      }
      state = .preparing(release)

      let expected = try await expectedChecksum(for: release)
      let actual = try await Task.detached { try Checksum.sha256(of: dmg) }.value
      guard actual == expected else { throw UpdateError.checksumMismatch }

      let app = try await UpdateInstaller.stage(
        dmg: dmg, workDir: dir, bundleID: bundleID, currentVersion: currentVersion, requirement: requirement)
      try? FileManager.default.removeItem(at: dmg)  // the app is out; the disk image isn't needed
      staged = (app, release, dir)
      state = .ready(release)
    } catch {
      try? FileManager.default.removeItem(at: dir)
      failedWhileUpdating = true
      state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }
  }

  fileprivate func setProgress(_ p: Double) {
    if case .downloading = state { state = .downloading(min(max(p, 0), 1)) }
  }

  /// The SHA-256 the download must match: GitHub's own digest, or the release's `.sha256` file.
  private func expectedChecksum(for release: UpdateRelease) async throws -> String {
    if let d = release.digest { return d }
    guard let url = release.checksumURL else { throw UpdateError.checksumMissing }
    guard UpdateTrust.isTrusted(url) else { throw UpdateError.untrustedURL(url.host ?? "unknown") }
    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.setValue("Kitbag-Updater", forHTTPHeaderField: "User-Agent")
    let data: Data
    do { data = try await fetch(request).0 } catch { throw UpdateError.network(error.localizedDescription) }
    guard let hash = Checksum.parse(String(decoding: data.prefix(4096), as: UTF8.self)) else { throw UpdateError.checksumMissing }
    return hash
  }

  // MARK: Installing

  /// Quits Kitbag; the helper then swaps in the new app and starts it.
  public func restart() {
    guard case .ready = state, let staged else { return }
    do {
      try UpdateInstaller.launchHelper(
        staged: staged.app, app: appURL, pid: ProcessInfo.processInfo.processIdentifier, workDir: staged.dir)
      state = .installing
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
    } catch {
      failedWhileUpdating = true
      state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }
  }

  public func openReleasePage() {
    switch state {
    case .available(let r), .preparing(let r), .ready(let r): NSWorkspace.shared.open(r.pageURL)
    default: break
    }
  }

  /// Back to a neutral state after an error.
  public func dismissError() { if case .failed = state { state = .idle } }
}
