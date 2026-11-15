import SwiftUI

/// One app-wide terminal. Commands run in the background, so closing the panel or switching pages
/// doesn't stop them; the output is kept until you clear it.
@MainActor
public final class TerminalModel: ObservableObject {
  public static let shared = TerminalModel()

  @Published public private(set) var log = ""
  @Published public var command = ""
  @Published public var isOpen = false
  @Published public private(set) var running = false
  private var process: Process?

  /// GUI apps start with a bare PATH, so add the usual tool folders (Homebrew, Docker).
  private static var path: String {
    let extra = [
      "/Applications/Docker.app/Contents/Resources/bin", "/opt/homebrew/bin", "/usr/local/bin",
    ]
    return (extra + [ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
  }

  public func echo(_ text: String) {
    log += text
    if log.count > 30_000 { log = String(log.suffix(20_000)) }
  }

  public func clear() { log = "" }

  /// Runs what is typed in the prompt.
  public func runTyped() {
    let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cmd.isEmpty, !running else { return }
    command = ""
    echo("$ \(cmd)\n")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/zsh")
    p.arguments = ["-lc", cmd]
    p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
    p.environment = ProcessInfo.processInfo.environment.merging(["PATH": Self.path]) { $1 }
    p.standardInput = FileHandle.nullDevice
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
      let d = h.availableData
      guard !d.isEmpty else { return }
      let s = String(decoding: d, as: UTF8.self)
      Task { @MainActor in self?.echo(s) }
    }
    p.terminationHandler = { [weak self] _ in
      pipe.fileHandleForReading.readabilityHandler = nil
      let rest = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      Task { @MainActor in
        if !rest.isEmpty { self?.echo(rest) }
        self?.running = false
        self?.process = nil
      }
    }
    do {
      try p.run()
      process = p
      running = true
    } catch {
      echo("\(error.localizedDescription)\n")
    }
  }

  public func stop() { process?.terminate() }
}

/// The terminal panel: output, a prompt, Stop while something runs, and Clear.
public struct TerminalView: View {
  @ObservedObject var model: TerminalModel
  public init(model: TerminalModel) { self.model = model }

  public var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Label("Terminal", systemImage: "terminal").font(.caption.bold()).foregroundStyle(.secondary)
        Spacer()
        if model.running { Button("Stop") { model.stop() }.buttonStyle(.borderless).font(.caption) }
        Button("Clear") { model.clear() }.buttonStyle(.borderless).font(.caption)
          .disabled(model.log.isEmpty)
        Button { model.isOpen = false } label: { Image(systemName: "xmark") }
          .buttonStyle(.borderless).font(.caption).help("Close")
      }
      ScrollViewReader { proxy in
        ScrollView {
          Text(model.log.isEmpty ? "Output appears here. Installs and Docker commands show up too." : model.log)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(model.log.isEmpty ? .secondary : .primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
          Color.clear.frame(height: 1).id("end")
        }
        .padding(6)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: model.log) { _, _ in proxy.scrollTo("end") }
      }
      HStack {
        Text("$").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
        TextField("docker ps", text: $model.command)
          .font(.system(size: 12, design: .monospaced))
          .textFieldStyle(.plain)
          .onSubmit { model.runTyped() }
          .disabled(model.running)
        if model.running { ProgressView().controlSize(.small) }
      }
    }
  }
}
