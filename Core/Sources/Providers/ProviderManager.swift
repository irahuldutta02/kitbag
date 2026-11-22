import AppKit
import Foundation

/// Finds the AI CLIs, reads their version and sign-in status, and installs/updates/signs them in.
@MainActor
public final class ProviderManager: ObservableObject {
  public static let shared = ProviderManager()

  @Published public private(set) var states: [AIProviderID: ProviderState]
  @Published public private(set) var lastChecked: Date?
  @Published public private(set) var refreshing = false
  @Published public private(set) var customPaths: [AIProviderID: String] = [:]
  @Published public private(set) var enabled: [AIProviderID: Bool] = [:]

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    var s: [AIProviderID: ProviderState] = [:]
    var paths: [AIProviderID: String] = [:]
    var on: [AIProviderID: Bool] = [:]
    for id in AIProviderID.allCases {
      s[id] = ProviderState()
      let path = defaults.string(forKey: "kitbag.provider.\(id.rawValue).binaryPath") ?? ""
      if !path.isEmpty { paths[id] = path }
      on[id] = defaults.object(forKey: "kitbag.provider.\(id.rawValue).enabled") as? Bool ?? true
    }
    states = s
    customPaths = paths
    enabled = on
  }

  public func state(_ id: AIProviderID) -> ProviderState { states[id] ?? ProviderState() }

  // MARK: Settings

  public func isEnabled(_ id: AIProviderID) -> Bool { enabled[id] ?? true }

  public func setEnabled(_ id: AIProviderID, _ on: Bool) {
    enabled[id] = on
    defaults.set(on, forKey: "kitbag.provider.\(id.rawValue).enabled")
  }

  public func customPath(for id: AIProviderID) -> String { customPaths[id] ?? "" }

  public func setCustomPath(_ path: String, for id: AIProviderID) {
    let t = path.trimmingCharacters(in: .whitespacesAndNewlines)
    customPaths[id] = t.isEmpty ? nil : t
    defaults.set(t, forKey: "kitbag.provider.\(id.rawValue).binaryPath")
    refresh(id)
  }

  /// The custom path when it is an executable, otherwise the first match in the standard folders.
  public func effectiveBinaryPath(for id: AIProviderID) -> String? {
    if let custom = customPaths[id], FileManager.default.isExecutableFile(atPath: custom) {
      return custom
    }
    return Self.locate(id)
  }

  nonisolated static func locate(_ id: AIProviderID) -> String? {
    AIProviderID.searchDirs().map { $0 + "/" + id.binaryName }
      .first(where: FileManager.default.isExecutableFile)
  }

  // MARK: Refresh

  public func refreshAll() {
    refreshing = true
    Task {
      await withTaskGroup(of: Void.self) { group in
        for id in AIProviderID.allCases { group.addTask { await self.check(id) } }
      }
      refreshing = false
      lastChecked = Date()
    }
  }

  public func refresh(_ id: AIProviderID) {
    Task {
      await check(id)
      lastChecked = Date()
    }
  }

  private func check(_ id: AIProviderID) async {
    let path = effectiveBinaryPath(for: id)
    let result = await Self.detect(id, path: path)
    var s = state(id)
    s.installed = path != nil
    s.binaryPath = path
    s.version = result.version
    s.authenticated = result.auth.authenticated
    s.authSummary = result.auth.summary
    s.accountDetail = result.auth.detail
    states[id] = s
  }

  nonisolated private static func detect(_ id: AIProviderID, path: String?) async
    -> (version: String?, auth: AuthParse)
  {
    guard let path else { return (nil, AuthParse(authenticated: false, summary: "Not installed")) }
    async let v = Proc.run(path, ["--version"], timeout: 6)
    async let a = authStatus(id, path: path)
    let version = await v.flatMap { $0.status == 0 ? parseVersion($0.output, for: id) : nil }
    return (version, await a)
  }

  nonisolated private static func authStatus(_ id: AIProviderID, path: String) async -> AuthParse {
    switch id {
    case .claude:
      guard let r = await Proc.run(path, ["auth", "status"], timeout: 8) else {
        return AuthParse(authenticated: false, summary: "Couldn't check sign-in")
      }
      return parseClaudeAuthStatus(r.output)
    case .codex:
      guard let r = await Proc.run(path, ["login", "status"], timeout: 8) else {
        return AuthParse(authenticated: false, summary: "Couldn't check sign-in")
      }
      return parseCodexLoginStatus(r.output, exitCode: r.status)
    case .antigravity:
      if usesGeminiAPIKey() {
        return AuthParse(authenticated: true, summary: "Authenticated · Gemini API key")
      }
      guard let r = await Proc.run(path, ["models"], timeout: 10) else {
        return AuthParse(authenticated: false, summary: "Not signed in")
      }
      let ok = r.status == 0 && r.output.lowercased().contains("gemini")
      return AuthParse(
        authenticated: ok, summary: ok ? "Authenticated · Google account" : "Not signed in")
    }
  }

  nonisolated private static func usesGeminiAPIKey() -> Bool {
    let url = URL(fileURLWithPath: NSHomeDirectory() + "/.gemini/antigravity-cli/settings.json")
    guard let data = try? Data(contentsOf: url),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return false }
    return (obj["modelProvider"] as? String) == "gemini"
      && !(ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? "").isEmpty
  }

  // MARK: Parsing (pure, for tests)

  /// "2.1.330 (Claude Code)", "codex-cli 0.171.0" or "1.5.14" -> "v2.1.330".
  nonisolated public static func parseVersion(_ text: String, for id: AIProviderID) -> String? {
    guard let r = text.range(of: #"\d+\.\d+(\.\d+)*"#, options: .regularExpression) else {
      return nil
    }
    return "v" + text[r]
  }

  nonisolated public static func parseClaudeAuthStatus(_ text: String) -> AuthParse {
    guard let data = text.data(using: .utf8),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      obj["loggedIn"] as? Bool == true
    else { return AuthParse(authenticated: false, summary: "Not signed in") }
    let email = obj["email"] as? String
    let plan = (obj["subscriptionType"] as? String) ?? (obj["planTier"] as? String)
    let method = (obj["authMethod"] as? String) ?? ""
    if let plan, !plan.isEmpty {
      return AuthParse(
        authenticated: true, summary: "Authenticated · Claude \(plan.capitalized) Subscription",
        detail: email)
    }
    if method.lowercased().contains("api") {
      return AuthParse(authenticated: true, summary: "Authenticated · API key", detail: email)
    }
    return AuthParse(authenticated: true, summary: "Authenticated", detail: email)
  }

  nonisolated public static func parseCodexLoginStatus(_ text: String, exitCode: Int32) -> AuthParse {
    let lower = text.lowercased()
    guard exitCode == 0, !lower.contains("not logged in") else {
      return AuthParse(authenticated: false, summary: "Not signed in")
    }
    if lower.contains("chatgpt") { return AuthParse(authenticated: true, summary: "Authenticated · ChatGPT") }
    if lower.contains("api key") { return AuthParse(authenticated: true, summary: "Authenticated · API key") }
    return AuthParse(authenticated: true, summary: "Authenticated")
  }

  // MARK: Actions

  public func install(_ id: AIProviderID) {
    guard
      Shell.confirm(
        "Install \(id.displayName)?",
        "Kitbag will run:\n\(installDescription(id))", action: String(localized: "Install"))
    else { return }
    runInstall(id, label: "Installing…")
  }

  public func reinstall(_ id: AIProviderID) {
    guard
      Shell.confirm(
        "Reinstall \(id.displayName)?",
        "Kitbag will run:\n\(installDescription(id, reinstall: true))",
        action: String(localized: "Reinstall"))
    else { return }
    runInstall(id, label: "Reinstalling…")
  }

  public func update(_ id: AIProviderID) {
    guard let path = effectiveBinaryPath(for: id) else { return install(id) }
    perform(id, label: "Updating…", command: "\(id.binaryName) update") {
      await Proc.run(path, ["update"], timeout: 300, onOutput: $0)
    }
  }

  public func signIn(_ id: AIProviderID) {
    guard let path = effectiveBinaryPath(for: id) else { return }
    switch id {
    case .claude:
      perform(id, label: "Signing in…", command: "claude auth login") {
        await Proc.run(path, ["auth", "login"], timeout: 300, onOutput: $0)
      }
    case .codex:
      perform(id, label: "Signing in…", command: "codex login") {
        await Proc.run(path, ["login"], timeout: 300, onOutput: $0)
      }
    case .antigravity:
      openInTerminal("\(quoted(path))")
      TerminalModel.shared.echo("Opened Terminal. Sign in to Antigravity there, then press Refresh.\n")
    }
  }

  /// Switches account: sign out, then sign in again.
  public func changeAccount(_ id: AIProviderID) {
    guard let path = effectiveBinaryPath(for: id) else { return }
    if id == .antigravity {
      openInTerminal("\(quoted(path))")
      TerminalModel.shared.echo("Opened Terminal. Type /logout in Antigravity, then sign in with another account.\n")
      return
    }
    perform(id, label: "Switching account…", command: "\(id.binaryName) logout, then login") { out in
      let args = id == .claude ? ["auth", "logout"] : ["logout"]
      _ = await Proc.run(path, args, timeout: 30, onOutput: out)
      let login = id == .claude ? ["auth", "login"] : ["login"]
      return await Proc.run(path, login, timeout: 300, onOutput: out)
    }
  }

  public func signOut(_ id: AIProviderID) {
    guard let path = effectiveBinaryPath(for: id) else { return }
    switch id {
    case .claude:
      perform(id, label: "Signing out…", command: "claude auth logout") {
        await Proc.run(path, ["auth", "logout"], timeout: 30, onOutput: $0)
      }
    case .codex:
      perform(id, label: "Signing out…", command: "codex logout") {
        await Proc.run(path, ["logout"], timeout: 30, onOutput: $0)
      }
    case .antigravity:
      openInTerminal("\(quoted(path))")
      TerminalModel.shared.echo("Opened Terminal. Type /logout in Antigravity to sign out, then press Refresh.\n")
    }
  }

  public func dismissError(_ id: AIProviderID) {
    var s = state(id)
    s.error = nil
    states[id] = s
  }

  // MARK: Plumbing

  private func installDescription(_ id: AIProviderID, reinstall: Bool = false) -> String {
    if let c = id.installCommand { return c }
    if Shell.brewPath != nil { return "brew \(reinstall ? "reinstall" : "install") --cask codex" }
    return "npm install -g @openai/codex"
  }

  private func runInstall(_ id: AIProviderID, label: String) {
    let reinstall = label.hasPrefix("Reinstall")
    perform(id, label: label, command: installDescription(id, reinstall: reinstall)) { out in
      if let script = id.installCommand {
        return await Proc.run("/bin/bash", ["-c", script], env: ["NONINTERACTIVE": "1"], timeout: 600, onOutput: out)
      }
      if let brew = Shell.brewPath {
        return await Proc.run(brew, [reinstall ? "reinstall" : "install", "--cask", "codex"], env: ["NONINTERACTIVE": "1"], timeout: 600, onOutput: out)
      }
      if let npm = Self.locateTool("npm") {
        return await Proc.run(npm, ["install", "-g", "@openai/codex"], timeout: 600, onOutput: out)
      }
      return nil
    }
  }

  nonisolated static func locateTool(_ name: String) -> String? {
    AIProviderID.searchDirs().map { $0 + "/" + name }.first(where: FileManager.default.isExecutableFile)
  }

  private func perform(
    _ id: AIProviderID, label: String, command: String,
    _ work: @escaping @Sendable (@escaping @MainActor @Sendable (String) -> Void) async -> Proc.Result?
  ) {
    guard state(id).busyAction == nil else { return }
    var s = state(id)
    s.busyAction = label
    s.error = nil
    states[id] = s
    let term = TerminalModel.shared
    term.echo("$ \(command)\n")
    Task {
      let r = await work { term.echo($0) }
      var s = state(id)
      s.busyAction = nil
      if let r {
        if r.status != 0 {
          s.error = Self.lastMeaningfulLine(r.output) ?? "\(id.displayName) exited with status \(r.status)."
        }
      } else {
        s.error = "Couldn't run \(id.displayName). Check Homebrew or npm is installed."
      }
      states[id] = s
      await check(id)
      lastChecked = Date()
    }
  }

  nonisolated static func lastMeaningfulLine(_ output: String) -> String? {
    output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
      .last { !$0.isEmpty && !$0.hasPrefix("==>") }
  }

  private func quoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

  /// `agy` is an interactive TUI, so sign-in happens in a real Terminal window.
  private func openInTerminal(_ command: String) {
    let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    let script = "tell application \"Terminal\"\nactivate\ndo script \"\(escaped)\"\nend tell"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", script]
    try? p.run()
  }
}

/// Runs a command with a timeout so nothing can hang, optionally streaming output.
enum Proc {
  struct Result: Sendable {
    let status: Int32
    let output: String
  }

  private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func add(_ d: Data) { lock.lock(); data.append(d); lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
  }

  static func run(
    _ path: String, _ args: [String], env: [String: String] = [:], timeout: TimeInterval,
    onOutput: (@MainActor @Sendable (String) -> Void)? = nil
  ) async -> Result? {
    await withCheckedContinuation { cont in
      DispatchQueue.global().async {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        var e = ProcessInfo.processInfo.environment
        e["PATH"] = (AIProviderID.searchDirs() + [e["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        p.environment = e.merging(env) { $1 }
        p.currentDirectoryURL = FileManager.default.temporaryDirectory
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
          // EOF reads as empty data forever; stop listening or this handler spins a CPU core.
          if d.isEmpty { h.readabilityHandler = nil; return }
          emit(d)
        }
        do { try p.run() } catch {
          pipe.fileHandleForReading.readabilityHandler = nil
          return cont.resume(returning: nil)
        }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        p.waitUntilExit()
        killer.cancel()
        pipe.fileHandleForReading.readabilityHandler = nil
        let rest = pipe.fileHandleForReading.readDataToEndOfFile()
        if !rest.isEmpty { emit(rest) }
        cont.resume(returning: Result(status: p.terminationStatus, output: box.text))
      }
    }
  }
}
