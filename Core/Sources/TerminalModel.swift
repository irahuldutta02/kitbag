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
    return (extra + [ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"]).joined(
      separator: ":")
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
  @Environment(\.colorScheme) private var scheme

  public init(model: TerminalModel) { self.model = model }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Label("Terminal", systemImage: "terminal")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        if model.running {
          HStack(spacing: 4) {
            StatusDot(color: KitbagUI.warning, active: true, size: 5.5)
            Text("Running").font(.caption2.weight(.medium)).foregroundStyle(KitbagUI.warning)
          }
          .padding(.horizontal, 6).padding(.vertical, 2)
          .background(KitbagUI.warning.opacity(0.14), in: Capsule())
        }
        Spacer()
        if model.running {
          Button("Stop") { model.stop() }
            .buttonStyle(.bordered)
            .tint(KitbagUI.danger)
            .controlSize(.mini)
        }
        Button("Clear") { model.clear() }
          .buttonStyle(.plain)
          .font(.caption.weight(.medium))
          .foregroundStyle(model.log.isEmpty ? .tertiary : .secondary)
          .padding(.horizontal, 6).padding(.vertical, 3)
          .hoverHighlight(cornerRadius: 5)
          .disabled(model.log.isEmpty)
        Button {
          model.isOpen = false
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .semibold))
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .hoverHighlight(cornerRadius: 5)
        .help("Close terminal (⌘J)")
      }

      ScrollViewReader { proxy in
        ScrollView {
          Text(
            model.log.isEmpty
              ? "Output appears here. Installs, updates, and Docker commands show up here too."
              : model.log
          )
          .font(.system(size: 11.5, design: .monospaced))
          .foregroundStyle(
            model.log.isEmpty ? Color.white.opacity(0.45) : Color.white.opacity(0.92)
          )
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(10)
          Color.clear.frame(height: 1).id("end")
        }
        .background(
          Color.black.opacity(scheme == .dark ? 0.55 : 0.82),
          in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .onChange(of: model.log) { _, _ in proxy.scrollTo("end") }
      }

      HStack(spacing: 8) {
        Text("$")
          .font(.system(size: 12, weight: .semibold, design: .monospaced))
          .foregroundStyle(Color.accentColor)
        TextField("Run a shell command…", text: $model.command)
          .font(.system(size: 12, design: .monospaced))
          .textFieldStyle(.plain)
          .onSubmit { model.runTyped() }
          .disabled(model.running)
        if model.running {
          ProgressView().controlSize(.mini)
        } else if !model.command.isEmpty {
          KeycapBadge("↵")
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(
        scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05),
        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(
            scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07),
            lineWidth: 0.5
          )
      )
    }
  }
}
