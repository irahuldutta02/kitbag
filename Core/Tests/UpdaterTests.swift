import Foundation
import Testing

@testable import KitbagCore

private let sampleRelease = """
  {
    "tag_name": "v1.2.0", "name": "Kitbag 1.2.0", "body": "- Faster\\n- Fixes",
    "html_url": "https://github.com/o/r/releases/tag/v1.2.0", "published_at": "2026-11-16T10:00:00Z",
    "assets": [
      {"name": "Kitbag-1.2.0.dmg", "browser_download_url": "https://github.com/o/r/releases/download/v1.2.0/Kitbag-1.2.0.dmg", "size": 5000000,
       "digest": "sha256:\(String(repeating: "ab", count: 32))"},
      {"name": "Kitbag-1.2.0.dmg.sha256", "browser_download_url": "https://github.com/o/r/releases/download/v1.2.0/Kitbag-1.2.0.dmg.sha256", "size": 90}
    ]
  }
  """

private func response(_ status: Int) -> URLResponse {
  HTTPURLResponse(url: URL(string: "https://api.github.com")!, statusCode: status, httpVersion: nil, headerFields: nil)!
}

@MainActor @Suite struct UpdaterTests {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kitbag-upd-\(UUID().uuidString)")
  let suite = "kitbag.upd.tests.\(UUID().uuidString)"

  private func updater(current: String = "1.0.0", reply: @escaping () throws -> (Data, URLResponse)) -> Updater {
    Updater(
      defaults: UserDefaults(suiteName: suite)!, fetch: { _ in try reply() }, workRoot: dir, requirement: .some(nil),
      currentVersion: AppVersion(current), repo: "o/r", appURL: URL(fileURLWithPath: "/Applications/Kitbag.app"))
  }

  // MARK: Versions

  @Test func versionsCompareLikeNumbers() throws {
    #expect(try #require(AppVersion("1.10.0")) > #require(AppVersion("1.9.9")))
    #expect(try #require(AppVersion("v2.0")) == #require(AppVersion("2.0.0")))
    #expect(try #require(AppVersion("1.2.0-beta")) < #require(AppVersion("1.2.0")))
    #expect(try #require(AppVersion("1.2.0-beta")) > #require(AppVersion("1.1.9")))
    #expect(try #require(AppVersion("1.0.0+45")) == #require(AppVersion("1.0.0")))
    #expect(AppVersion("") == nil && AppVersion("latest") == nil && AppVersion("1..2") == nil)
    #expect(try #require(AppVersion("v1.2.3")).description == "1.2.3")
  }

  // MARK: Releases

  @Test func readsAGitHubRelease() throws {
    let r = try ReleaseParser.parse(Data(sampleRelease.utf8))
    #expect(r.versionText == "1.2.0" && r.dmgName == "Kitbag-1.2.0.dmg" && r.size == 5_000_000)
    #expect(r.digest == String(repeating: "ab", count: 32))
    #expect(r.checksumURL?.lastPathComponent == "Kitbag-1.2.0.dmg.sha256")
    #expect(r.notes.contains("Faster") && r.published != nil)
  }

  @Test func refusesReleasesItCannotUse() {
    #expect(throws: UpdateError.self) { try ReleaseParser.parse(Data("{}".utf8)) }
    let noDmg = sampleRelease.replacingOccurrences(of: ".dmg\"", with: ".zip\"")
    #expect(throws: UpdateError.self) { try ReleaseParser.parse(Data(noDmg.utf8)) }
    let badTag = sampleRelease.replacingOccurrences(of: "v1.2.0\", \"name\"", with: "nightly\", \"name\"")
    #expect(throws: UpdateError.self) { try ReleaseParser.parse(Data(badTag.utf8)) }
  }

  @Test func onlyGitHubIsTrusted() {
    #expect(UpdateTrust.isTrusted(URL(string: "https://github.com/o/r/x.dmg")!))
    #expect(UpdateTrust.isTrusted(URL(string: "https://objects.githubusercontent.com/a")!))
    #expect(!UpdateTrust.isTrusted(URL(string: "http://github.com/x")!))
    #expect(!UpdateTrust.isTrusted(URL(string: "https://github.com.evil.com/x")!))
    #expect(!UpdateTrust.isTrusted(URL(string: "https://evilgithubusercontent.com/x")!))
    #expect(UpdateTrust.isValidRepo("irahuldutta02/kitbag") && !UpdateTrust.isValidRepo("a/b/../c") && !UpdateTrust.isValidRepo("a b/c"))
    #expect(UpdateTrust.safeName("1.2.0-beta/../x") == "1.2.0-beta_.._x")
  }

  // MARK: Checksums

  @Test func checksums() throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let f = dir.appendingPathComponent("abc.txt")
    try Data("abc".utf8).write(to: f)
    #expect(try Checksum.sha256(of: f) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    let h = String(repeating: "0a", count: 32)
    #expect(Checksum.parse("\(h)  Kitbag-1.2.0.dmg\n") == h && Checksum.parse(h.uppercased()) == h)
    #expect(Checksum.parse("not a hash") == nil && Checksum.parse("abc123") == nil)
  }

  // MARK: Checking (with a fake GitHub)

  @Test func findsANewerVersion() async {
    let u = updater { (Data(sampleRelease.utf8), response(200)) }
    await u.check(userInitiated: true)
    guard case .available(let r) = u.state else { return Issue.record("expected an update, got \(u.state)") }
    #expect(r.versionText == "1.2.0" && u.lastChecked != nil)
  }

  @Test func sameOrOlderMeansUpToDate() async {
    let same = updater(current: "1.2.0") { (Data(sampleRelease.utf8), response(200)) }
    await same.check(userInitiated: true)
    #expect(same.state == .upToDate)
    let newer = updater(current: "2.0.0") { (Data(sampleRelease.utf8), response(200)) }
    await newer.check(userInitiated: true)
    #expect(newer.state == .upToDate)
  }

  @Test func skippedVersionStaysQuietButManualCheckStillShowsIt() async {
    let u = updater { (Data(sampleRelease.utf8), response(200)) }
    await u.check(userInitiated: false)
    u.skip()
    #expect(u.state == .upToDate && u.skippedVersion == "1.2.0")
    await u.check(userInitiated: false)
    #expect(u.state == .upToDate)  // background check: not shown again
    await u.check(userInitiated: true)
    if case .available = u.state {} else { Issue.record("a manual check should still offer it") }
  }

  @Test func problemsAreShownOnlyWhenYouAskedForTheCheck() async {
    let none = updater { (Data(), response(404)) }
    await none.check(userInitiated: false)
    #expect(none.state == .idle)
    await none.check(userInitiated: true)
    #expect(none.state == .failed(UpdateError.noReleases.localizedDescription))
    let limited = updater { (Data(), response(403)) }
    await limited.check(userInitiated: true)
    #expect(limited.state == .failed(UpdateError.rateLimited.localizedDescription))
    struct Offline: Error {}
    let offline = updater { throw Offline() }
    await offline.check(userInitiated: true)
    if case .failed = offline.state {} else { Issue.record("offline should fail a manual check") }
  }

  @Test func automaticChecksRunOncePerDayAtMost() async {
    var calls = 0
    let u = updater(current: "9.9.9") { calls += 1; return (Data(sampleRelease.utf8), response(200)) }
    u.checkIfDue()
    try? await Task.sleep(nanoseconds: 300_000_000)
    #expect(calls == 1)
    u.checkIfDue()
    try? await Task.sleep(nanoseconds: 300_000_000)
    #expect(calls == 1)  // checked a moment ago
    u.automatic = false
    #expect(!u.automatic)
  }

  @Test func cannotInstallIntoAFolderItCannotWriteTo() {
    let locked = Updater(
      defaults: UserDefaults(suiteName: suite)!, workRoot: dir, requirement: .some(nil), currentVersion: AppVersion("1.0.0"),
      repo: "o/r", appURL: URL(fileURLWithPath: "/System/Applications/Kitbag.app"))
    #expect(locked.installBlocker != nil)
    let dev = Updater(
      defaults: UserDefaults(suiteName: suite)!, workRoot: dir, requirement: .some(nil), currentVersion: AppVersion("1.0.0"),
      repo: "o/r", appURL: URL(fileURLWithPath: "/x/.build/debug/Kitbag"))
    #expect(dev.installBlocker != nil)
  }

  // MARK: The checks a downloaded app must pass (real signed apps)

  private func makeApp(_ at: URL, id: String, version: String, sign: Bool = true) throws {
    let macos = at.appendingPathComponent("Contents/MacOS")
    try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
    let exe = macos.appendingPathComponent("Kitbag")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: exe)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
    let plist: [String: Any] = [
      "CFBundleIdentifier": id, "CFBundleExecutable": "Kitbag", "CFBundleShortVersionString": version,
      "CFBundleVersion": "1", "CFBundlePackageType": "APPL",
    ]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
      .write(to: at.appendingPathComponent("Contents/Info.plist"))
    if sign {
      let p = Process()
      p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
      p.arguments = ["--force", "--sign", "-", at.path]
      p.standardError = FileHandle.nullDevice
      try p.run()
      p.waitUntilExit()
    }
  }

  @Test func downloadedAppMustBeTheRightNewSignedApp() throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let good = dir.appendingPathComponent("good.app")
    try makeApp(good, id: "com.test.kitbag", version: "1.1.0")
    let now = AppVersion("1.0.0")!
    try UpdateInstaller.check(good, bundleID: "com.test.kitbag", currentVersion: now, requirement: nil)

    #expect(throws: UpdateError.self) { try UpdateInstaller.check(good, bundleID: "com.other.app", currentVersion: now, requirement: nil) }
    #expect(throws: UpdateError.notNewer) { try UpdateInstaller.check(good, bundleID: "com.test.kitbag", currentVersion: AppVersion("1.1.0")!, requirement: nil) }
    #expect(throws: UpdateError.notNewer) { try UpdateInstaller.check(good, bundleID: "com.test.kitbag", currentVersion: AppVersion("2.0.0")!, requirement: nil) }

    // Signed by someone else than the running copy: refused.
    #expect(throws: UpdateError.self) {
      try UpdateInstaller.check(good, bundleID: "com.test.kitbag", currentVersion: now, requirement: #"identifier "com.someone.else""#)
    }
    // An unsigned app, or one changed after signing: refused.
    let unsigned = dir.appendingPathComponent("unsigned.app")
    try makeApp(unsigned, id: "com.test.kitbag", version: "1.1.0", sign: false)
    #expect(throws: UpdateError.self) { try UpdateInstaller.check(unsigned, bundleID: "com.test.kitbag", currentVersion: now, requirement: nil) }
    try Data("#!/bin/sh\necho tampered\n".utf8).write(to: good.appendingPathComponent("Contents/MacOS/Kitbag"))
    #expect(throws: UpdateError.self) { try UpdateInstaller.check(good, bundleID: "com.test.kitbag", currentVersion: now, requirement: nil) }
  }

  @Test func identityPinningOnlyAppliesToCertificateSignedApps() {
    #expect(!CodeIdentity.isPinned(nil))
    #expect(!CodeIdentity.isPinned(#"cdhash H"abcdef0123""#))  // ad-hoc: nothing to compare
    #expect(CodeIdentity.isPinned(#"identifier "x" and certificate leaf = H"abcdef""#))
    #expect(CodeIdentity.isPinned(#"identifier "x" and anchor apple generic and certificate leaf[subject.OU] = "TEAM""#))
  }

  // MARK: The swap script

  private func runHelper(running: String) throws -> (app: URL, backup: URL, log: String) {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let app = dir.appendingPathComponent("Kitbag.app")
    let new = dir.appendingPathComponent("staging/Kitbag.app")
    for (url, text) in [(app, "old"), (new, "new")] {
      try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
      try Data(text.utf8).write(to: url.appendingPathComponent("Contents/version.txt"))
    }
    let script = dir.appendingPathComponent("update.sh")
    try UpdateInstaller.helperScript.write(to: script, atomically: true, encoding: .utf8)
    let backup = URL(fileURLWithPath: app.path + ".old")
    let log = dir.appendingPathComponent("update.log")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = [script.path, "999999", app.path, new.path, backup.path, log.path]  // 999999: no such process, so "Kitbag already quit"
    p.environment = ["KITBAG_OPEN": "/usr/bin/true", "KITBAG_RUNNING_CHECK": running, "KITBAG_WAIT": "0", "PATH": "/usr/bin:/bin"]
    try p.run()
    p.waitUntilExit()
    return (app, backup, (try? String(contentsOf: log, encoding: .utf8)) ?? "")
  }

  @Test func scriptSwapsTheAppAndCleansUp() throws {
    let r = try runHelper(running: "/usr/bin/true")
    #expect(try String(contentsOf: r.app.appendingPathComponent("Contents/version.txt"), encoding: .utf8) == "new")
    #expect(!FileManager.default.fileExists(atPath: r.backup.path))
    #expect(!FileManager.default.fileExists(atPath: r.app.path + ".update"))
    #expect(r.log.contains("update finished"))
  }

  @Test func scriptPutsTheOldAppBackIfTheNewOneDoesNotStart() throws {
    let r = try runHelper(running: "/usr/bin/false")
    #expect(try String(contentsOf: r.app.appendingPathComponent("Contents/version.txt"), encoding: .utf8) == "old")
    #expect(!FileManager.default.fileExists(atPath: r.backup.path))
    #expect(r.log.contains("rolling back"))
  }
}
