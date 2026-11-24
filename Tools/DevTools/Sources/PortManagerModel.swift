import AppKit
import Darwin
import KitbagCore

/// One process listening on a TCP port.
struct ListeningPort: Identifiable, Equatable {
  let port: Int
  let pid: pid_t
  let command: String
  let address: String
  var id: String { "\(port)-\(pid)" }
}

/// A named set of ports you can kill together. Saved by port number, since process ids change.
struct PortGroup: Identifiable, Codable, Equatable {
  var id = UUID()
  var name: String
  var ports: [Int] = []
}

/// What a process is, in words: the app or project name, and the command that started it.
struct ProcessLabel: Equatable {
  let title: String
  let detail: String
}

@MainActor
final class PortManagerModel: ObservableObject {
  @Published private(set) var listening: [ListeningPort] = []
  @Published private(set) var groups: [PortGroup] = []
  @Published var filter = ""
  @Published var newGroupName = ""
  @Published private(set) var lastError: String?
  /// The card a port is being dragged over (a group's id, or `otherTarget`), to highlight it.
  @Published var dropTarget: String?
  /// Processes being stopped: hidden at once, so a killed port leaves the list right away.
  private var stopping = Set<pid_t>()
  /// Readable names for the listening processes, by pid.
  @Published private(set) var labels: [pid_t: ProcessLabel] = [:]
  static let otherTarget = "other"
  static let dragPrefix = "kitbag-port:"

  static func dragPayload(_ port: Int) -> String { dragPrefix + String(port) }

  /// Handles a dropped row: moves its port into `group`, or out of every group when nil.
  @discardableResult
  func drop(_ items: [String], on group: PortGroup?) -> Bool {
    let ports = items.compactMap { s -> Int? in
      s.hasPrefix(Self.dragPrefix) ? Int(s.dropFirst(Self.dragPrefix.count)) : nil
    }
    guard !ports.isEmpty else { return false }
    for p in ports { assign(port: p, to: group) }
    return true
  }

  private let defaults: UserDefaults
  private static let groupsKey = "kitbag.ports.groups"
  private static let namesKey = "kitbag.ports.names"
  /// Names you gave to ports (by port number), shown instead of the process name.
  @Published private(set) var portNames: [Int: String] = [:]
  private var polling: Task<Void, Never>?
  var confirmKills = true  // tests turn this off

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let saved = defaults.dictionary(forKey: Self.namesKey) as? [String: String] {
      portNames = Dictionary(uniqueKeysWithValues: saved.compactMap { k, v in Int(k).map { ($0, v) } })
    }
    if let data = defaults.data(forKey: Self.groupsKey),
      let saved = try? JSONDecoder().decode([PortGroup].self, from: data)
    {
      groups = saved
    }
  }

  // MARK: Reading ports

  /// Parses `lsof -F pcn` output. A process listening on IPv4 and IPv6 shows up once per port.
  nonisolated static func parse(_ text: String) -> [ListeningPort] {
    var result: [ListeningPort] = []
    var seen = Set<String>()
    var pid: pid_t = 0
    var command = ""
    for line in text.split(separator: "\n") {
      guard let tag = line.first else { continue }
      let value = String(line.dropFirst())
      switch tag {
      case "p": pid = pid_t(value) ?? 0
      case "c": command = value
      case "n":
        guard let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]),
          pid > 0
        else { continue }
        let item = ListeningPort(
          port: port, pid: pid, command: command, address: String(value[..<colon]))
        if seen.insert(item.id).inserted { result.append(item) }
      default: break
      }
    }
    return result.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
  }

  func refresh() async {
    guard
      let r = await Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"])
    else { return }
    // lsof exits 1 when nothing is listening; that is not an error.
    let items = Self.parse(r.output).filter { !stopping.contains($0.pid) }
    let pids = Set(items.map(\.pid))
    let missing = pids.filter { labels[$0] == nil }
    if !missing.isEmpty { await loadLabels(for: missing, fallback: items) }
    for pid in labels.keys where !pids.contains(pid) { labels[pid] = nil }
    if items != listening { listening = items }
  }

  /// Reads each new process's full command line and working folder, so a row can say
  /// "kitbag-web" and "node vite dev" instead of just "node".
  private func loadLabels(for pids: Set<pid_t>, fallback: [ListeningPort]) async {
    let list = pids.map(String.init).joined(separator: ",")
    async let psOut = Shell.run("/bin/ps", ["-o", "pid=,args=", "-p", list])
    async let cwdOut = Shell.run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-Fpn", "-p", list])
    let args = Self.parseArgs((await psOut)?.output ?? "")
    let cwds = Self.parseCwds((await cwdOut)?.output ?? "")
    for pid in pids {
      let name = fallback.first { $0.pid == pid }?.command ?? "pid \(pid)"
      labels[pid] = Self.describe(args: args[pid] ?? "", cwd: cwds[pid], fallback: name)
    }
  }

  nonisolated static func parseArgs(_ text: String) -> [pid_t: String] {
    var out: [pid_t: String] = [:]
    for line in text.split(separator: "\n") {
      let t = line.trimmingCharacters(in: .whitespaces)
      guard let space = t.firstIndex(of: " "), let pid = pid_t(t[..<space]) else { continue }
      out[pid] = String(t[t.index(after: space)...]).trimmingCharacters(in: .whitespaces)
    }
    return out
  }

  nonisolated static func parseCwds(_ text: String) -> [pid_t: String] {
    var out: [pid_t: String] = [:]
    var pid: pid_t = 0
    for line in text.split(separator: "\n") {
      let v = String(line.dropFirst())
      if line.first == "p" { pid = pid_t(v) ?? 0 } else if line.first == "n", pid > 0 { out[pid] = v }
    }
    return out
  }

  private nonisolated static let runtimes: [String] = [
    "node", "nodejs", "python", "ruby", "java", "deno", "bun", "php", "perl", "npm", "npx", "pnpm",
    "yarn", "uvicorn", "gunicorn", "next", "vite", "tsx", "ts-node", "nodemon", "go", "dotnet",
  ]

  /// Turns a command line into a readable name. Apps use their bundle name; scripts and servers
  /// use the project folder they run in; anything else uses the program name.
  nonisolated static func describe(args: String, cwd: String?, fallback: String) -> ProcessLabel {
    guard !args.isEmpty else { return ProcessLabel(title: fallback, detail: fallback) }
    // Executable path can contain spaces inside an .app bundle ("Docker Desktop.app/...").
    if let r = args.range(of: ".app/") {
      let app = String(args[..<r.lowerBound])
      let name = (app as NSString).lastPathComponent
      let exe = (String(args[r.upperBound...]).split(separator: " ").first.map(String.init) ?? "")
      return ProcessLabel(title: name, detail: (exe as NSString).lastPathComponent)
    }
    let tokens = args.split(separator: " ").map(String.init)
    let exe = (tokens.first.map { ($0 as NSString).lastPathComponent }) ?? fallback
    let rest = tokens.dropFirst().map { $0.contains("/") ? ($0 as NSString).lastPathComponent : $0 }
    let detail = ([exe] + rest).joined(separator: " ")
    let short = detail.count > 56 ? String(detail.prefix(55)) + "…" : detail

    let lower = exe.lowercased()
    let isRuntime = runtimes.contains { lower == $0 || lower.hasPrefix($0 + "3") || lower.hasPrefix($0 + "-") }
    if isRuntime, let cwd, cwd != "/", cwd != NSHomeDirectory(),
      !["/usr", "/System", "/Library", "/private", "/opt/homebrew/Cellar"].contains(where: cwd.hasPrefix)
    {
      return ProcessLabel(title: (cwd as NSString).lastPathComponent, detail: short)
    }
    return ProcessLabel(title: exe, detail: short)
  }

  func label(for p: ListeningPort) -> ProcessLabel {
    labels[p.pid] ?? ProcessLabel(title: p.command, detail: p.command)
  }

  func startPolling() {
    guard polling == nil else { return }
    polling = Task { [weak self] in
      while !Task.isCancelled {
        await self?.refresh()
        try? await Task.sleep(nanoseconds: 3_000_000_000)
      }
    }
  }

  func stopPolling() {
    polling?.cancel()
    polling = nil
  }

  // MARK: Lists the view shows

  func matches(_ p: ListeningPort) -> Bool {
    let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
    return q.isEmpty || String(p.port).contains(q) || p.command.lowercased().contains(q)
  }

  func listeners(on port: Int) -> [ListeningPort] { listening.filter { $0.port == port } }

  func group(of port: Int) -> PortGroup? { groups.first { $0.ports.contains(port) } }

  /// Listening ports that belong to no group.
  var ungrouped: [ListeningPort] {
    let grouped = Set(groups.flatMap(\.ports))
    return listening.filter { !grouped.contains($0.port) && matches($0) }
  }

  func runningPIDs(in group: PortGroup) -> [pid_t] {
    var seen = Set<pid_t>()
    return group.ports.flatMap { listeners(on: $0) }.map(\.pid).filter { seen.insert($0).inserted }
  }

  // MARK: Port names

  /// Gives a port your own name; an empty name goes back to the process name.
  func setName(_ name: String, for port: Int) {
    let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { portNames[port] = nil } else { portNames[port] = t }
    defaults.set(Dictionary(uniqueKeysWithValues: portNames.map { (String($0.key), $0.value) }), forKey: Self.namesKey)
  }

  /// What to call this port: your name for it, or what is running on it.
  func displayName(for p: ListeningPort) -> String { portNames[p.port] ?? label(for: p).title }

  // MARK: Groups

  private func save() {
    if let data = try? JSONEncoder().encode(groups) { defaults.set(data, forKey: Self.groupsKey) }
  }

  @discardableResult
  func addGroup(_ name: String) -> PortGroup? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let g = PortGroup(name: trimmed)
    groups.append(g)
    save()
    return g
  }

  func createGroupFromField() {
    if addGroup(newGroupName) != nil { newGroupName = "" }
  }

  func deleteGroup(_ g: PortGroup) {
    groups.removeAll { $0.id == g.id }
    save()
  }

  func renameGroup(_ g: PortGroup, to name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let i = groups.firstIndex(where: { $0.id == g.id }) else { return }
    groups[i].name = trimmed
    save()
  }

  /// A port lives in at most one group.
  func assign(port: Int, to g: PortGroup?) {
    for i in groups.indices { groups[i].ports.removeAll { $0 == port } }
    if let g, let i = groups.firstIndex(where: { $0.id == g.id }) { groups[i].ports.append(port) }
    save()
  }

  func addToNewGroup(port: Int, name: String) {
    guard let g = addGroup(name) else { return }
    assign(port: port, to: g)
  }

  // MARK: Killing

  /// Asks the processes to quit, then forces any that are still there after two seconds.
  func kill(pids: [pid_t]) {
    let targets = Set(pids).filter { $0 > 1 && $0 != getpid() }
    guard !targets.isEmpty else { return }
    lastError = nil
    var accepted = Set<pid_t>()
    for pid in targets {
      if Darwin.kill(pid, SIGTERM) == 0 {
        accepted.insert(pid)
      } else if errno == EPERM {
        lastError = String(localized: "Not allowed to stop process \(pid).")
      }  // ESRCH: already gone, nothing to hide
    }
    // Take them off the list now instead of waiting for the next refresh.
    stopping.formUnion(accepted)
    listening.removeAll { accepted.contains($0.pid) }
    Task { [weak self] in
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      for pid in accepted where Darwin.kill(pid, 0) == 0 { Darwin.kill(pid, SIGKILL) }
      try? await Task.sleep(nanoseconds: 400_000_000)
      self?.stopping.subtract(accepted)
      await self?.refresh()
    }
  }

  func killGroup(_ g: PortGroup) {
    let pids = runningPIDs(in: g)
    guard !pids.isEmpty else { return }
    if confirmKills {
      let ok = Shell.confirm(
        String(localized: "Stop everything in “\(g.name)”?"),
        String(localized: "\(pids.count) process(es) on \(g.ports.count) port(s) will be stopped."),
        action: String(localized: "Stop All"))
      guard ok else { return }
    }
    kill(pids: pids)
  }

  func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
}
