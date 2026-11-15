import AppKit
import KitbagCore
import SwiftUI

/// nvm (Node.js) and pyenv (Python): install the manager, install/remove versions, pick the default.
@MainActor
final class VersionsModel: ObservableObject {
  enum Kind: String, CaseIterable, Identifiable {
    case node, python
    var id: String { rawValue }
    var title: String { self == .node ? "Node.js" : "Python" }
    var manager: String { self == .node ? "nvm" : "pyenv" }
    var symbol: String { self == .node ? "hexagon.fill" : "curlybraces" }
    var tint: Color { self == .node ? .green : .blue }
  }

  struct State {
    var installed = false
    var versions: [String] = []
    var defaultVersion: String?
    var available: [String] = []
  }

  @Published private(set) var states: [Kind: State] = [.node: State(), .python: State()]
  /// The thing happening right now ("node", "node:v20.1.0", …); one action at a time.
  @Published private(set) var busy: String?
  /// What's typed in each runtime's "install a version" field.
  @Published var drafts: [Kind: String] = [:]

  var isBusy: Bool { busy != nil }
  func state(_ k: Kind) -> State { states[k] ?? State() }

  private let home = NSHomeDirectory()
  private var nvmDir: String { home + "/.nvm" }
  private var pyenvRoot: String { home + "/.pyenv" }

  private static let path =
    "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

  // MARK: Where things live

  private var nvmScript: String? {
    [nvmDir + "/nvm.sh", "/opt/homebrew/opt/nvm/nvm.sh", "/usr/local/opt/nvm/nvm.sh"]
      .first(where: FileManager.default.fileExists)
  }

  private var pyenvBinary: String? {
    ["/opt/homebrew/bin/pyenv", "/usr/local/bin/pyenv", pyenvRoot + "/bin/pyenv"]
      .first(where: FileManager.default.isExecutableFile)
  }

  // MARK: Running

  private func echo(_ t: String) { TerminalModel.shared.echo(t) }
  private func fail(_ message: String) { Toast.shared.show(message, error: true) }
  private func succeed(_ message: String) { Toast.shared.show(message) }

  /// Runs `script` in bash with the manager's environment; output is mirrored to the terminal.
  private func sh(_ script: String, show: Bool = true) async -> Shell.Result? {
    let env = ["PATH": Self.path, "NVM_DIR": nvmDir, "PYENV_ROOT": pyenvRoot, "NONINTERACTIVE": "1"]
    guard show else { return await Shell.run("/bin/bash", ["-c", script], env: env) }
    let handler: @MainActor @Sendable (String) -> Void = { [weak self] text in
      guard let self else { return }
      self.echo(text)
    }
    return await Shell.run("/bin/bash", ["-c", script], env: env, onOutput: handler)
  }

  private func nvm(_ command: String, show: Bool = true) async -> Shell.Result? {
    guard let s = nvmScript else { return nil }
    if show { echo("$ nvm \(command)\n") }
    return await sh("mkdir -p \"$NVM_DIR\"; . '\(s)' >/dev/null 2>&1; nvm \(command)", show: show)
  }

  private func pyenv(_ command: String, show: Bool = true) async -> Shell.Result? {
    guard let b = pyenvBinary else { return nil }
    if show { echo("$ pyenv \(command)\n") }
    return await sh("'\(b)' \(command)", show: show)
  }

  // MARK: State

  func refresh() async {
    await refreshNode()
    await refreshPython()
  }

  private func refreshNode() async {
    var s = state(.node)
    s.installed = nvmScript != nil
    guard s.installed else { states[.node] = State(); return }
    let dir = nvmDir + "/versions/node"
    let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
    s.versions = Self.sorted(names.filter { Self.isVersion($0) })
    if let r = await nvm("version default", show: false), r.ok {
      s.defaultVersion = Self.parseNodeDefault(r.output)
    } else {
      s.defaultVersion = nil
    }
    states[.node] = s
  }

  private func refreshPython() async {
    var s = state(.python)
    s.installed = pyenvBinary != nil
    guard s.installed else { states[.python] = State(); return }
    if let r = await pyenv("versions --bare", show: false), r.ok {
      s.versions = Self.sorted(r.output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { Self.isVersion($0) })
    }
    if let r = await pyenv("global", show: false), r.ok {
      let d = r.output.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) }
      s.defaultVersion = d == "system" ? nil : d
    }
    states[.python] = s
  }

  /// Fetches the list of versions that can be installed (a network call, so only on demand).
  func loadAvailable(_ k: Kind) {
    guard state(k).installed, state(k).available.isEmpty, busy == nil else { return }
    Task {
      let r = k == .node ? await nvm("ls-remote --lts --no-colors", show: false) : await pyenv("install --list", show: false)
      guard let r, r.ok else { return }
      var s = state(k)
      s.available = k == .node ? Self.parseNodeAvailable(r.output) : Self.parsePythonAvailable(r.output)
      states[k] = s
    }
  }

  // MARK: Shell setup

  /// Adds the manager's startup lines to ~/.zshrc (once, between marker comments) so new terminals
  /// find it. Skipped when the file already sets the manager up by hand.
  private func configureShell(_ k: Kind) async {
    let (marker, existing, block): (String, String, String) =
      k == .node
      ? ("nvm", "NVM_DIR",
        """
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \\. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \\. "$NVM_DIR/bash_completion"
        """)
      : ("pyenv", "pyenv init",
        """
        export PYENV_ROOT="$HOME/.pyenv"
        [ -d "$PYENV_ROOT/bin" ] && export PATH="$PYENV_ROOT/bin:$PATH"
        command -v pyenv >/dev/null 2>&1 && eval "$(pyenv init - zsh)"
        """)
    // Single-quoted text keeps $ and quotes literal; no heredoc, so no indentation traps.
    let text = "# >>> Kitbag \(marker) >>>\n\(block)\n# <<< Kitbag \(marker) <<<"
    let script = """
      rc="$HOME/.zshrc"; touch "$rc"
      if grep -q 'Kitbag \(marker)' "$rc" || grep -q '\(existing)' "$rc"; then
        echo "~/.zshrc already set up for \(marker)"
      else
        printf '\\n%s\\n' '\(text)' >> "$rc"
        echo "Added \(marker) setup to ~/.zshrc"
      fi
      """
    _ = await sh(script)
  }

  private func removeShellSetup(_ k: Kind) async {
    let m = k == .node ? "nvm" : "pyenv"
    _ = await sh("[ -f \"$HOME/.zshrc\" ] && sed -i '' '/# >>> Kitbag \(m) >>>/,/# <<< Kitbag \(m) <<</d' \"$HOME/.zshrc\"; true")
  }

  // MARK: Actions
  // Progress and output go to the terminal; the outcome is a toast.

  func installManager(_ k: Kind) {
    run(k.rawValue) {
      let r: Shell.Result?
      switch k {
      case .node:
        self.echo("$ install nvm\n")
        // PROFILE=/dev/null: don't edit the user's shell startup files.
        r = await self.sh(
          "curl -fsSL 'https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh' | PROFILE=/dev/null bash")
      case .python:
        if let brew = Shell.brewPath {
          self.echo("$ brew install pyenv\n")
          r = await self.sh("'\(brew)' install pyenv")
        } else {
          self.echo("$ install pyenv\n")
          r = await self.sh("curl -fsSL https://pyenv.run | bash")
        }
      }
      if r?.ok == true {
        await self.configureShell(k)
        self.succeed(String(localized: "\(k.manager) installed and set up in ~/.zshrc. Open a new terminal to use it."))
      } else {
        self.fail(String(localized: "Couldn't install \(k.manager). See the terminal for details."))
      }
    }
  }

  func uninstallManager(_ k: Kind) {
    guard Shell.confirm(
      String(localized: "Uninstall \(k.manager)?"),
      String(localized: "\(k.manager) and every \(k.title) version it installed are removed."),
      action: String(localized: "Uninstall"))
    else { return }
    run(k.rawValue) {
      switch k {
      case .node:
        _ = await self.sh("rm -rf \"$NVM_DIR\"")
        if let brew = Shell.brewPath, FileManager.default.fileExists(atPath: "/opt/homebrew/opt/nvm") {
          _ = await self.sh("'\(brew)' uninstall nvm")
        }
      case .python:
        if let brew = Shell.brewPath, self.pyenvBinary?.contains("/.pyenv/") == false {
          _ = await self.sh("'\(brew)' uninstall pyenv")
        }
        _ = await self.sh("rm -rf \"$PYENV_ROOT\"")
      }
      await self.removeShellSetup(k)
      self.succeed(String(localized: "\(k.manager) uninstalled"))
    }
  }

  /// Installs `version` (typed or picked) and, if asked or if nothing is the default yet, makes it
  /// the default. A malformed or non-existent version is reported as an error.
  func install(_ k: Kind, version raw: String, makeDefault: Bool = false) {
    var version = raw.trimmingCharacters(in: .whitespaces)
    if k == .node, version.lowercased() == "latest" { version = "node" }
    guard Self.isVersionOrTag(version) else {
      fail(String(localized: "\"\(version)\" isn't a valid version. Use a number like 20.11.0 or 3.12.4."))
      return
    }
    if state(k).versions.contains(where: { Self.key($0) == Self.key(version) && Self.key(version).count == 3 }) {
      fail(String(localized: "\(k.title) \(version) is already installed."))
      return
    }
    run("\(k.rawValue):\(version)") {
      let r = k == .node ? await self.nvm("install \(version)") : await self.pyenv("install -s \(version)")
      guard r?.ok == true else {
        self.fail(Self.failureReason(r?.output, k: k, version: version))
        return
      }
      await self.refresh()
      var wasDefault = false
      if makeDefault || self.state(k).defaultVersion == nil {
        wasDefault = await self.applyDefault(k, version == "node" ? (self.state(k).versions.last ?? version) : version)
      }
      let name = version == "node" ? String(localized: "the latest release") : version
      self.succeed(String(localized: "\(k.title) \(name) installed") + (wasDefault ? String(localized: " and set as default") : ""))
    }
  }

  /// A readable reason from the manager's output, e.g. "version not found".
  static func failureReason(_ output: String?, k: Kind, version: String) -> String {
    let lines = (output ?? "").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    let lower = lines.joined(separator: " ").lowercased()
    if lower.contains("not found") || lower.contains("definition not found") || lower.contains("n/a") {
      return String(localized: "\(k.title) \(version) doesn't exist. Check the version number.")
    }
    return String(localized: "Couldn't install \(k.title) \(version). See the terminal for details.")
  }

  func setDefault(_ k: Kind, _ version: String) {
    guard Self.isVersion(version) else { return }
    run("\(k.rawValue):\(version)") {
      if await self.applyDefault(k, version) {
        self.succeed(String(localized: "\(k.title) \(version) is now the default"))
      }
    }
  }

  func remove(_ k: Kind, _ version: String) {
    guard Self.isVersion(version) else { return }
    guard Shell.confirm(
      String(localized: "Remove \(k.title) \(version)?"), String(localized: "This version is deleted."),
      action: String(localized: "Remove"))
    else { return }
    run("\(k.rawValue):\(version)") {
      let ok: Bool
      switch k {
      case .node: ok = await self.nvm("uninstall \(version)")?.ok == true
      case .python: ok = await self.pyenv("uninstall -f \(version)")?.ok == true
      }
      if ok {
        self.succeed(String(localized: "\(k.title) \(version) removed"))
      } else {
        self.fail(String(localized: "Couldn't remove \(version). See the terminal for details."))
      }
    }
  }

  @discardableResult
  private func applyDefault(_ k: Kind, _ version: String) async -> Bool {
    let ok: Bool
    switch k {
    case .node: ok = await nvm("alias default \(version)")?.ok == true
    case .python: ok = await pyenv("global \(version)")?.ok == true
    }
    if !ok { fail(String(localized: "Couldn't set the default. See the terminal for details.")) }
    if ok { await configureShell(k) }  // also covers managers installed outside Kitbag
    return ok
  }

  private func run(_ key: String, _ work: @escaping () async -> Void) {
    guard busy == nil else { return }
    busy = key
    Task {
      await work()
      await refresh()
      busy = nil
    }
  }

  // MARK: Parsing (pure, tested)

  static func isVersion(_ s: String) -> Bool {
    s.range(of: #"^v?\d+(\.\d+){1,3}$"#, options: .regularExpression) != nil
  }

  static func isVersionOrTag(_ s: String) -> Bool { s == "node" || isVersion(s) }

  static func key(_ v: String) -> [Int] {
    v.drop(while: { $0 == "v" }).split(separator: ".").map { Int($0) ?? 0 }
  }

  static func sorted(_ v: [String]) -> [String] {
    v.sorted { a, b in
      let (x, y) = (key(a), key(b))
      for i in 0..<max(x.count, y.count) {
        let (p, q) = (i < x.count ? x[i] : 0, i < y.count ? y[i] : 0)
        if p != q { return p < q }
      }
      return false
    }
  }

  /// `nvm version default` prints e.g. "v20.11.0", or "N/A" when there is none.
  static func parseNodeDefault(_ out: String) -> String? {
    out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.last { isVersion($0) }
  }

  /// The newest release of each LTS line, newest first, preceded by "node" (the latest release).
  static func parseNodeAvailable(_ out: String, limit: Int = 6) -> [String] {
    var latest: [Int: String] = [:]
    for line in out.split(separator: "\n") {
      guard let r = line.range(of: #"v\d+\.\d+\.\d+"#, options: .regularExpression) else { continue }
      let v = String(line[r])
      let major = key(v)[0]
      if latest[major] == nil || sorted([latest[major]!, v]).last == v { latest[major] = v }
    }
    let lts = latest.keys.sorted(by: >).prefix(limit).compactMap { latest[$0] }
    return ["node"] + lts
  }

  /// The newest patch of each 3.x line (final releases only), newest first.
  static func parsePythonAvailable(_ out: String, limit: Int = 8) -> [String] {
    var latest: [String: String] = [:]
    for line in out.split(separator: "\n") {
      let v = line.trimmingCharacters(in: .whitespaces)
      guard v.range(of: #"^3\.\d+\.\d+$"#, options: .regularExpression) != nil else { continue }
      let minor = v.split(separator: ".").prefix(2).joined(separator: ".")
      if latest[minor] == nil || sorted([latest[minor]!, v]).last == v { latest[minor] = v }
    }
    return sorted(Array(latest.values)).reversed().prefix(limit).map { $0 }
  }
}
