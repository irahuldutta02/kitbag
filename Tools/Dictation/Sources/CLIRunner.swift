import Foundation
import KitbagCore

/// Runs a provider CLI once, with a time limit, and hands back what it printed.
enum CLIRunner {
  struct Output {
    let status: Int32
    let out: Data
    let err: Data
  }

  static func run(
    _ cli: String, _ args: [String], timeout: TimeInterval, startFailure: String
  ) async throws -> Output {
    try await withCheckedThrowingContinuation { cont in
      DispatchQueue.global().async {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cli)
        p.arguments = args
        p.currentDirectoryURL = FileManager.default.temporaryDirectory  // no project files
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (AIProviderID.searchDirs() + [env["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        p.environment = env
        let output = Pipe(), errors = Pipe()
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = output
        p.standardError = errors
        do { try p.run() } catch {
          return cont.resume(throwing: ClaudeCLI.RefineError.failed(startFailure))
        }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = errors.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        cont.resume(returning: Output(status: p.terminationStatus, out: out, err: err))
      }
    }
  }

  static func lastLine(_ data: Data) -> String? {
    String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).last.map(String.init)
  }
}
