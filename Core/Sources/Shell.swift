import AppKit
import Foundation

/// Runs a command off the main thread, optionally streaming its output as it arrives.
public enum Shell {
  public struct Result: Sendable {
    public let status: Int32
    public let output: String
    public var ok: Bool { status == 0 }
  }

  private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func add(_ d: Data) { lock.lock(); data.append(d); lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
  }

  public static func run(
    _ path: String, _ args: [String], env: [String: String] = [:],
    onOutput: (@MainActor @Sendable (String) -> Void)? = nil
  ) async -> Result? {
    await withCheckedContinuation { cont in
      DispatchQueue.global().async {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        if !env.isEmpty { p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 } }
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let box = Box()
        let emit: @Sendable (Data) -> Void = { d in
          box.add(d)
          if let onOutput { let s = String(decoding: d, as: UTF8.self); Task { @MainActor in onOutput(s) } }
        }
        pipe.fileHandleForReading.readabilityHandler = { h in
          let d = h.availableData
          if !d.isEmpty { emit(d) }
        }
        do { try p.run() } catch {
          pipe.fileHandleForReading.readabilityHandler = nil
          return cont.resume(returning: nil)
        }
        p.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        let rest = pipe.fileHandleForReading.readDataToEndOfFile()
        if !rest.isEmpty { emit(rest) }
        cont.resume(returning: Result(status: p.terminationStatus, output: box.text))
      }
    }
  }

  public static var brewPath: String? {
    ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: FileManager.default.isExecutableFile)
  }

  /// A helper `sudo -A` runs to ask for the password in a normal macOS dialog (no Terminal needed).
  private static func askpassScript() -> String? {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("kitbag-askpass.sh")
    let body = """
      #!/bin/sh
      /usr/bin/osascript -e 'display dialog "Kitbag needs your password to finish installing." default answer "" with hidden answer with title "Kitbag" buttons {"Cancel", "OK"} default button "OK"' -e 'text returned of result'
      """
    do {
      try body.write(to: url, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
      return url.path
    } catch { return nil }
  }

  /// `brew install|uninstall --cask <cask>`. Returns an error message, or nil on success.
  public static func brewCask(
    _ action: String, _ cask: String, onOutput: (@MainActor @Sendable (String) -> Void)? = nil
  ) async -> String? {
    guard let brew = brewPath else {
      return String(localized: "Homebrew isn't installed (brew.sh).")
    }
    var env = ["NONINTERACTIVE": "1"]
    if let askpass = askpassScript() { env["SUDO_ASKPASS"] = askpass }
    await onOutput?("$ brew \(action) --cask \(cask)\n")
    guard let r = await run(brew, [action, "--cask", cask], env: env, onOutput: onOutput) else {
      return String(localized: "Couldn't run brew.")
    }
    if r.ok { return nil }
    // macOS blocks edits inside an installed app unless the calling app has "App Management".
    if r.output.contains("Operation not permitted") {
      let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!
      await MainActor.run { _ = NSWorkspace.shared.open(pane) }
      return String(localized: "macOS blocked the install. Turn on Kitbag in the App Management list that just opened (System Settings ▸ Privacy & Security), then try again.")
    }
    let lines = r.output.split(separator: "\n").map(String.init)
    // brew ends with cleanup lines ("==> Purging…"); the real reason is the Error: line.
    return lines.first { $0.hasPrefix("Error:") }
      ?? lines.last { !$0.hasPrefix("==>") } ?? "brew failed"
  }

  public static func brewInstallCask(
    _ cask: String, onOutput: (@MainActor @Sendable (String) -> Void)? = nil
  ) async -> String? { await brewCask("install", cask, onOutput: onOutput) }

  public static func brewUninstallCask(
    _ cask: String, onOutput: (@MainActor @Sendable (String) -> Void)? = nil
  ) async -> String? { await brewCask("uninstall", cask, onOutput: onOutput) }

  /// Asks before something destructive. Returns true if the person chose the action.
  @MainActor public static func confirm(_ title: String, _ message: String, action: String) -> Bool {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = message
    a.alertStyle = .warning
    a.addButton(withTitle: action)
    a.addButton(withTitle: String(localized: "Cancel"))
    NSApp.activate(ignoringOtherApps: true)
    return a.runModal() == .alertFirstButtonReturn
  }
}
