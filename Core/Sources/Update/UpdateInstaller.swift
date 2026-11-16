import Foundation

/// Everything that happens between "the download finished" and "the new app is in place".
public enum UpdateInstaller {
  // MARK: 1. Get the app out of the disk image and check it

  /// Opens the disk image, copies the app out, closes it again, and checks that the copy is the
  /// Kitbag app, is newer than what is running, and is signed by the same identity. Nothing running is
  /// touched: this is done while Kitbag is still open so any problem can be shown to you.
  public static func stage(
    dmg: URL, workDir: URL, bundleID: String, currentVersion: AppVersion, requirement: String?
  ) async throws -> URL {
    let fm = FileManager.default
    let mount = workDir.appendingPathComponent("mount", isDirectory: true)
    let staged = workDir.appendingPathComponent("Kitbag.app", isDirectory: true)
    try? fm.removeItem(at: staged)
    try fm.createDirectory(at: mount, withIntermediateDirectories: true)

    try await attach(dmg, at: mount)
    let copied: Bool
    do {
      let apps = ((try? fm.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "app" }
      guard let source = apps.first(where: { $0.lastPathComponent == "Kitbag.app" }) ?? apps.first else {
        throw UpdateError.wrongApp("There is no app inside the disk image.")
      }
      let copy = await Shell.run("/usr/bin/ditto", [source.path, staged.path])
      copied = copy?.ok == true
    } catch {
      await detach(mount)  // always close the disk image, whatever happens
      throw error
    }
    await detach(mount)
    guard copied else { throw UpdateError.badDiskImage("The app couldn't be copied out of it.") }

    do { try check(staged, bundleID: bundleID, currentVersion: currentVersion, requirement: requirement) } catch {
      try? fm.removeItem(at: staged)  // never leave an app we don't trust lying around
      throw error
    }
    return staged
  }

  /// The checks an app must pass before it is allowed to replace the running one.
  public static func check(_ app: URL, bundleID: String, currentVersion: AppVersion, requirement: String?) throws {
    guard let bundle = Bundle(url: app), bundle.bundleIdentifier == bundleID else {
      throw UpdateError.wrongApp("It has a different identifier.")
    }
    guard let exe = bundle.executableURL, FileManager.default.isExecutableFile(atPath: exe.path) else {
      throw UpdateError.wrongApp("It has no program inside.")
    }
    guard let text = bundle.infoDictionary?["CFBundleShortVersionString"] as? String, let v = AppVersion(text),
      v > currentVersion
    else { throw UpdateError.notNewer }
    try CodeIdentity.verify(app, requirement: requirement)
  }

  /// Mounts the disk image read-only and hidden. `hdiutil attach` is what every macOS has; newer ones
  /// call it deprecated in favour of `diskutil image attach`, so that is the fallback.
  private static func attach(_ dmg: URL, at mount: URL) async throws {
    let first = await Shell.run(
      "/usr/bin/hdiutil",
      ["attach", "-nobrowse", "-readonly", "-noverify", "-noautoopen", "-mountpoint", mount.path, dmg.path])
    if first?.ok == true { return }
    let second = await Shell.run(
      "/usr/sbin/diskutil", ["image", "attach", "--readOnly", "--nobrowse", "--mountPoint", mount.path, dmg.path])
    if second?.ok == true { return }
    throw UpdateError.badDiskImage(readable(second?.output ?? first?.output))
  }

  private static func detach(_ mount: URL) async {
    var done = false
    for args in [["detach", mount.path, "-quiet"], ["detach", mount.path, "-force", "-quiet"]] {
      if await Shell.run("/usr/bin/hdiutil", args)?.ok == true { done = true; break }
    }
    if !done { _ = await Shell.run("/usr/sbin/diskutil", ["unmount", "force", mount.path]) }
    try? FileManager.default.removeItem(at: mount)
  }

  /// The tool's message without its deprecation notices.
  private static func readable(_ output: String?) -> String {
    (output ?? "").split(separator: "\n").map(String.init)
      .filter { !$0.localizedCaseInsensitiveContains("deprecated") && !$0.contains("WARNING") }
      .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: 2. Swap the app after Kitbag has quit

  /// A running app can't replace itself, so a small script waits for Kitbag to quit, swaps the
  /// folders, starts the new copy, and puts the old one back if the new one doesn't stay running.
  /// Paths are passed as arguments, never pasted into the script. Environment variables
  /// (`KITBAG_OPEN`, `KITBAG_RUNNING_CHECK`, `KITBAG_WAIT`) exist so the script can be tested.
  static let helperScript = #"""
    #!/bin/bash
    # Kitbag updater helper. Usage: update.sh <pid> <app> <new app> <backup> <log>
    PID="$1"; APP="$2"; NEW="$3"; BACKUP="$4"; LOG="$5"
    OPEN="${KITBAG_OPEN:-/usr/bin/open}"
    log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
    running() {
      if [ -n "$KITBAG_RUNNING_CHECK" ]; then "$KITBAG_RUNNING_CHECK"; else /usr/bin/pgrep -f "$APP/Contents/MacOS/" >/dev/null; fi
    }
    rollback() {
      log "rolling back"
      rm -rf "$APP"
      [ -e "$BACKUP" ] && mv "$BACKUP" "$APP"
      "$OPEN" "$APP"
    }

    log "waiting for Kitbag ($PID) to quit"
    for _ in $(seq 1 150); do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
    if kill -0 "$PID" 2>/dev/null; then log "Kitbag did not quit; leaving everything as it is"; exit 1; fi

    STAGING="$APP.update"
    rm -rf "$STAGING" "$BACKUP"
    if ! /usr/bin/ditto "$NEW" "$STAGING"; then log "copy failed"; rm -rf "$STAGING"; "$OPEN" "$APP"; exit 1; fi
    if ! mv "$APP" "$BACKUP"; then log "could not move the old app aside"; rm -rf "$STAGING"; "$OPEN" "$APP"; exit 1; fi
    if ! mv "$STAGING" "$APP"; then log "could not put the new app in place"; rm -rf "$STAGING"; rollback; exit 1; fi
    /usr/bin/xattr -dr com.apple.quarantine "$APP" 2>/dev/null

    log "starting the new version"
    "$OPEN" "$APP"
    sleep "${KITBAG_WAIT:-6}"
    if running; then
      log "update finished"
      rm -rf "$BACKUP"
      rm -rf "$(dirname "$NEW")"
      exit 0
    fi
    log "the new version did not stay running"
    rollback
    exit 1
    """#

  /// Writes the helper next to the staged app and starts it detached, so it outlives Kitbag.
  @discardableResult
  public static func launchHelper(staged: URL, app: URL, pid: Int32, workDir: URL) throws -> URL {
    let script = workDir.appendingPathComponent("update.sh")
    let log = workDir.deletingLastPathComponent().appendingPathComponent("update.log")
    let backup = URL(fileURLWithPath: app.path + ".old")
    do {
      try helperScript.write(to: script, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
    } catch { throw UpdateError.cannotInstall("Couldn't prepare the update. \(error.localizedDescription)") }

    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = [
      "-c", "nohup /bin/bash \"$@\" >/dev/null 2>&1 &", "sh",
      script.path, String(pid), app.path, staged.path, backup.path, log.path,
    ]
    do { try p.run() } catch { throw UpdateError.cannotInstall("Couldn't start the update. \(error.localizedDescription)") }
    return log
  }
}
