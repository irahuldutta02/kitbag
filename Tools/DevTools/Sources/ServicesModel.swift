import AppKit
import KitbagCore
import SwiftUI

/// Docker Desktop plus MongoDB, PostgreSQL and Valkey, each run from a docker compose file.
@MainActor
final class ServicesModel: ObservableObject {
  struct Service: Identifiable {
    let id: String
    let title: String
    let container: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let endpoint: String  // shown while running
    let connection: String  // what "copy" puts on the clipboard
    let volume: String  // data volume name inside the compose file
    let compose: String  // docker-compose.yml contents
    var companions: [String] = []  // other containers in the compose file, run along with it
    var web: String? = nil  // address of its web UI
    var note: String? = nil  // shown in Settings once installed

    /// Every container the service runs, companions first so they are stopped first.
    var allContainers: [String] { companions + [container] }
  }

  // Dev-only default credentials (admin/admin); ports are published to localhost.
  static let services = [
    Service(
      id: "mongo", title: "MongoDB", container: "mongo-db",
      subtitle: "mongo:7 · localhost:27017", symbol: "leaf.fill", tint: .green,
      endpoint: "localhost:27017", connection: "mongodb://admin:admin@localhost:27017",
      volume: "mongo_data",
      compose: """
        services:
          mongodb:
            image: mongo:7
            container_name: mongo-db
            restart: unless-stopped
            environment:
              MONGO_INITDB_ROOT_USERNAME: admin
              MONGO_INITDB_ROOT_PASSWORD: admin
            ports:
              - "27017:27017"
            volumes:
              - mongo_data:/data/db

        volumes:
          mongo_data:

        """),
    Service(
      id: "postgres", title: "PostgreSQL", container: "postgres-db",
      subtitle: "postgres:16 · localhost:5432", symbol: "cylinder.split.1x2.fill", tint: .indigo,
      endpoint: "localhost:5432", connection: "postgresql://admin:admin@localhost:5432/postgres",
      volume: "postgres_data",
      compose: """
        services:
          postgres:
            image: postgres:16
            container_name: postgres-db
            restart: unless-stopped
            environment:
              POSTGRES_USER: admin
              POSTGRES_PASSWORD: admin
            ports:
              - "5432:5432"
            volumes:
              - postgres_data:/var/lib/postgresql/data

        volumes:
          postgres_data:

        """),
    // The admin user matches the other databases; requirepass covers clients that only send a password.
    Service(
      id: "valkey", title: "Valkey", container: "valkey-db",
      subtitle: "valkey:9 · localhost:6379 · UI on 8085", symbol: "key.fill", tint: .blue,
      endpoint: "localhost:6379", connection: "redis://admin:admin@localhost:6379",
      volume: "valkey_data",
      compose: """
        services:
          valkey:
            image: valkey/valkey:9
            container_name: valkey-db
            restart: unless-stopped
            command: ["valkey-server", "--appendonly", "yes", "--requirepass", "admin",
              "--user", "admin", "on", ">admin", "~*", "&*", "+@all"]
            ports:
              - "6379:6379"
              # The web UI below, which has no login of its own: only reachable from this Mac.
              - "127.0.0.1:8085:8080"
            volumes:
              - valkey_data:/data

          valkey-admin:
            image: valkey/valkey-admin:1.3.0
            container_name: valkey-admin
            restart: unless-stopped
            # Shares Valkey's network, so "localhost" in the UI means this Valkey.
            network_mode: "service:valkey"
            depends_on:
              - valkey
            environment:
              DEPLOYMENT_MODE: Web
            # If Valkey stops or restarts, the shared network goes stale: exit, so Docker restarts
            # the UI onto the new one (or leaves it stopped while Valkey is).
            healthcheck:
              test: ["CMD", "node", "-e", "require('net').connect(6379).on('connect', () => process.exit(0)).on('error', () => process.kill(1))"]
              interval: 10s

        volumes:
          valkey_data:

        """,
      companions: ["valkey-admin"], web: "http://localhost:8085",
      note: String(
        localized:
          "In the web UI, add a connection with host localhost, port 6379, username admin, password admin, and Use TLS turned off."
      )),
  ]

  nonisolated static let dockerBundleID = "com.docker.docker"
  /// The launcher and the window app have different ids; both mean "Docker is up".
  nonisolated static let dockerAppIDs = ["com.docker.docker", "com.electron.dockerdesktop"]
  private static let dockerPaths = [
    "/usr/local/bin/docker", "/opt/homebrew/bin/docker",
    "/Applications/Docker.app/Contents/Resources/bin/docker",
  ]

  @Published private(set) var dockerInstalled = false
  @Published private(set) var dockerRunning = false
  @Published private(set) var daemonReady = false
  /// container name -> running
  @Published private(set) var containers: [String: Bool] = [:]
  @Published private(set) var busy: Set<String> = []
  /// What a switch was just flipped to, shown right away; cleared when the real state is known.
  @Published private(set) var desired: [String: Bool] = [:]
  private var observers: [(NotificationCenter, NSObjectProtocol)] = []
  @Published var notice: String?
  private var timer: Timer?

  /// The app has a bare PATH; Docker needs its own bin folder (credential helpers live there).
  private static let dockerEnv = [
    "PATH": "/Applications/Docker.app/Contents/Resources/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
  ]

  private var docker: String? {
    Self.dockerPaths.first(where: FileManager.default.isExecutableFile)
  }

  /// Everything Kitbag runs for Docker is shown in the app-wide terminal.
  func echo(_ text: String) { TerminalModel.shared.echo(text) }

  enum Phase { case installing, uninstalling, starting, stopping }

  /// What is happening to `id` ("docker", "mongo", "postgres", "valkey") right now, if anything.
  func phase(_ id: String) -> Phase? {
    if busy.contains("install-\(id)") { return .installing }
    if busy.contains("uninstall-\(id)") { return .uninstalling }
    if busy.contains(id) { return desired[id] == false ? .stopping : .starting }
    return nil
  }

  private func settled(_ id: String) -> Bool {
    let p = phase(id)
    return p != .installing && p != .uninstalling
  }

  /// Installed and not in the middle of installing/removing: safe to offer a switch for.
  var dockerReady: Bool { dockerInstalled && settled("docker") }

  func serviceReady(_ s: Service) -> Bool { dockerReady && isInstalled(s) && settled(s.id) }

  /// When Docker is stopped we can't ask it, so fall back to what we last saw.
  func isInstalled(_ s: Service) -> Bool {
    daemonReady ? containers[s.container] != nil : UserDefaults.standard.bool(forKey: "kitbag.svc.\(s.id)")
  }

  func isOn(_ id: String) -> Bool {
    if let d = desired[id] { return d }
    if id == "docker" { return daemonReady }
    return Self.services.first { $0.id == id }.map { containers[$0.container] == true } ?? false
  }

  /// Docker and every container exist, so there is nothing left to install.
  var fullyInstalled: Bool {
    dockerInstalled && Self.services.allSatisfy { containers[$0.container] != nil }
  }

  // MARK: State

  /// Re-sync on Docker launching/quitting, on wake from sleep and when Kitbag regains focus.
  func startObserving() {
    guard observers.isEmpty else { return }
    let ws = NSWorkspace.shared.notificationCenter
    let sync: @Sendable () -> Void = { [weak self] in Task { @MainActor in await self?.refresh() } }
    for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
      observers.append((ws, ws.addObserver(forName: name, object: nil, queue: .main) { note in
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if let id = app?.bundleIdentifier, ServicesModel.dockerAppIDs.contains(id) { sync() }
      }))
    }
    observers.append((ws, ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in sync() }))
    let nc = NotificationCenter.default
    observers.append((nc, nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in sync() }))
    sync()
  }

  func stopObserving() {
    observers.forEach { $0.0.removeObserver($0.1) }
    observers = []
  }

  func setPolling(_ on: Bool) {
    timer?.invalidate()
    timer = nil
    guard on else { return }
    Task { await refresh() }
    let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.refresh() }
    }
    t.tolerance = 1.5
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  private var dockerAppRunning: Bool {
    Self.dockerAppIDs.contains { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
  }

  private var socketExists: Bool {
    ["\(NSHomeDirectory())/.docker/run/docker.sock", "/var/run/docker.sock"]
      .contains { FileManager.default.fileExists(atPath: $0) }
  }

  /// The engine answering is the truth for "Docker is on"; the app process alone isn't enough.
  func refresh() async {
    // LaunchServices keeps remembering removed apps, so check the file itself.
    dockerInstalled = ["/Applications/Docker.app", NSHomeDirectory() + "/Applications/Docker.app"]
      .contains { FileManager.default.fileExists(atPath: $0) }
    dockerRunning = dockerAppRunning
    if !dockerInstalled {
      for s in Self.services { UserDefaults.standard.set(false, forKey: "kitbag.svc.\(s.id)") }
    }
    guard dockerInstalled, socketExists, let docker,
      let r = await Shell.run(docker, ["ps", "-a", "--format", "{{.Names}} {{.State}}"], env: Self.dockerEnv), r.ok
    else {
      daemonReady = false
      containers = [:]
      return
    }
    dockerRunning = true
    daemonReady = true
    defer {
      for s in Self.services {
        UserDefaults.standard.set(containers[s.container] != nil, forKey: "kitbag.svc.\(s.id)")
      }
    }
    containers = Dictionary(
      uniqueKeysWithValues: r.output.split(separator: "\n").compactMap { line in
        let p = line.split(separator: " ")
        return p.count == 2 ? (String(p[0]), p[1] == "running") : nil
      })
  }

  // MARK: Actions

  /// Opens the Docker Desktop window (the normal app), so Docker's own menu bar icon isn't needed.
  /// A running Docker is a menu bar agent that ignores a plain relaunch, so ask for its dashboard.
  func openDocker() {
    guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.dockerBundleID),
      let dashboard = URL(string: "docker-desktop://dashboard/open")
    else { return }
    NSWorkspace.shared.open([dashboard], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) {
      [weak self] _, error in
      guard let message = error?.localizedDescription else { return }
      Task { @MainActor in self?.notice = message }
    }
  }

  func toggleDocker(_ on: Bool) {
    run("docker", desired: on) {
      if on {
        _ = await self.startDocker()
      } else {
        if await self.docker(["desktop", "stop"], report: false) { return }
        Self.dockerAppIDs.forEach {
          NSRunningApplication.runningApplications(withBundleIdentifier: $0).forEach { $0.terminate() }
        }
      }
    }
  }

  func toggle(_ s: Service, _ on: Bool) {
    run(s.id, desired: on) {
      guard await self.startDocker() else { return }
      if !on {
        await self.docker(["stop"] + s.allContainers.filter { self.containers[$0] != nil })
      } else if !s.companions.isEmpty {
        // `up` starts them in order and adds any that an older install doesn't have yet. If it
        // can't (say a leftover container has the same name), recreate them; the data volume stays.
        if !(await self.compose(s, ["up", "-d"], report: false)) {
          self.echo("Start failed; recreating \(s.title)…\n")
          await self.docker(["rm", "-f"] + s.allContainers, report: false)
          await self.compose(s, ["up", "-d"])
        }
      } else if self.containers[s.container] != nil {
        // A container whose storage is broken ("RWLayer ... nil") can't start: remove and recreate it.
        if !(await self.docker(["start", s.container], report: false)) {
          self.echo("Start failed; recreating \(s.container)…\n")
          await self.docker(["rm", "-f", s.container])
          await self.compose(s, ["up", "-d"])
        }
      } else {
        await self.compose(s, ["up", "-d"])
      }
    }
  }

  var isBusy: Bool { !busy.isEmpty }

  func installDocker() {
    run("install-docker") { _ = await self.ensureDockerInstalled() }
  }

  func install(_ s: Service) {
    run("install-\(s.id)") {
      guard await self.ensureDockerInstalled(), await self.startDocker() else { return }
      if self.containers[s.container] == nil { await self.compose(s, ["create"]) }
    }
  }

  func uninstall(_ s: Service) {
    let a = NSAlert()
    a.messageText = String(localized: "Remove \(s.title)?")
    a.informativeText = String(localized: "The container is removed. You can keep or delete its data.")
    a.alertStyle = .warning
    a.addButton(withTitle: String(localized: "Remove, keep data"))
    a.addButton(withTitle: String(localized: "Remove and delete data"))
    a.addButton(withTitle: String(localized: "Cancel"))
    NSApp.activate(ignoringOtherApps: true)
    let choice = a.runModal()
    guard choice != .alertThirdButtonReturn else { return }
    let deleteData = choice == .alertSecondButtonReturn
    run("uninstall-\(s.id)") {
      guard await self.startDocker() else { return }
      await self.docker(["rm", "-f"] + s.allContainers.filter { self.containers[$0] != nil })
      if deleteData {
        // compose names the volume <project>_<volume>
        await self.docker(["volume", "rm", "kitbag-\(s.id)_\(s.volume)"])
      }
    }
  }

  func uninstallDocker() {
    guard Shell.confirm(
      String(localized: "Uninstall Docker Desktop?"),
      String(localized: "Docker Desktop is removed. Containers, images and volumes inside it, including MongoDB, PostgreSQL and Valkey data, may be lost."),
      action: String(localized: "Uninstall"))
    else { return }
    run("uninstall-docker") {
      Self.dockerAppIDs.forEach {
        NSRunningApplication.runningApplications(withBundleIdentifier: $0).forEach { $0.terminate() }
      }
      try? await Task.sleep(nanoseconds: 3_000_000_000)
      if let err = await Shell.brewUninstallCask("docker-desktop", onOutput: { self.echo($0) }) {
        self.notice = err
      } else {
        for s in Self.services { UserDefaults.standard.set(false, forKey: "kitbag.svc.\(s.id)") }
        self.dockerInstalled = false
        self.containers = [:]
        self.daemonReady = false
      }
    }
  }

  private func ensureDockerInstalled() async -> Bool {
    await refresh()
    if dockerInstalled { return true }
    if let err = await Shell.brewInstallCask("docker-desktop", onOutput: { [weak self] in self?.echo($0) }) {
      notice = err
      return false
    }
    await refresh()
    return dockerInstalled
  }

  private func run(_ key: String, desired want: Bool? = nil, _ work: @escaping () async -> Void) {
    guard busy.isEmpty else { return }  // one action at a time
    busy.insert(key)
    if let want { desired[key] = want }
    notice = nil
    Task {
      await work()
      await refresh()
      desired[key] = nil  // the real state is known now; a failed switch flips back
      busy.remove(key)
    }
  }

  /// Launches Docker Desktop, if needed, and waits for its engine. False if it never came up.
  /// It is opened like any other app, just without taking focus: Kitbag never hides its windows,
  /// so Docker's dashboard and menu bar icon behave the way Docker's own settings say.
  private func startDocker() async -> Bool {
    await refresh()
    if daemonReady { return true }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.dockerBundleID) else {
      notice = String(localized: "Docker isn't installed. Install it in Settings.")
      return false
    }
    if !dockerRunning {
      let c = NSWorkspace.OpenConfiguration()
      c.activates = false
      _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: c)
    }
    for _ in 0..<60 {
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      await refresh()
      if daemonReady { return true }
    }
    notice = String(localized: "Docker didn't start in time.")
    return false
  }

  /// Writes the service's compose file into Application Support and runs `docker compose` on it.
  @discardableResult
  private func compose(_ s: Service, _ args: [String], report: Bool = true) async -> Bool {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Kitbag/docker/\(s.id)", isDirectory: true)
    let file = dir.appendingPathComponent("docker-compose.yml")
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      try s.compose.write(to: file, atomically: true, encoding: .utf8)
    } catch {
      notice = error.localizedDescription
      return false
    }
    return await docker(["compose", "-p", "kitbag-\(s.id)", "-f", file.path] + args, report: report)
  }

  @discardableResult
  private func docker(_ args: [String], report: Bool = true) async -> Bool {
    guard let docker else { return false }
    echo("$ docker \(args.joined(separator: " "))\n")
    guard let r = await Shell.run(docker, args, env: Self.dockerEnv, onOutput: { [weak self] in self?.echo($0) })
    else { return false }
    if !r.ok && report { notice = r.output.split(separator: "\n").last.map(String.init) }
    return r.ok
  }
}
