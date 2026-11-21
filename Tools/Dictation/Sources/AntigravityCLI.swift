import Foundation
import KitbagCore

/// Asks Google's Antigravity CLI (`agy`) to tidy a transcript.
enum AntigravityCLI {
  static func refine(
    _ text: String, model: String, effort: String, prompt: String = ClaudeCLI.instructions,
    cli: String
  ) async throws -> ClaudeCLI.Refined {
    // `agy -p` takes the prompt as its argument, not on stdin.
    let full = "\(prompt)\n\n<transcript>\(text)</transcript>"
    var args = ["--output-format", "json", "--disable-slash-commands", "--model", model]
    if !effort.isEmpty { args += ["--effort", effort] }
    args += ["--print-timeout", "45s", "--print=\(full)"]
    let r = try await CLIRunner.run(
      cli, args, timeout: 55, startFailure: String(localized: "Couldn't start Antigravity."))
    if r.status == 0, let parsed = parse(r.out), !parsed.text.isEmpty { return parsed }
    let reason = CLIRunner.lastLine(r.err)
    throw ClaudeCLI.RefineError.failed(reason ?? String(localized: "Antigravity didn't answer."))
  }

  /// Reads `agy --output-format json`: `{"status":"SUCCESS","response":"…","usage":{…}}`.
  static func parse(_ data: Data) -> ClaudeCLI.Refined? {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      (obj["status"] as? String)?.uppercased() == "SUCCESS", let response = obj["response"] as? String
    else { return nil }
    var u = ClaudeCLI.Usage()
    if let usage = obj["usage"] as? [String: Any] {
      u.inputTokens = (usage["input_tokens"] as? NSNumber)?.intValue ?? 0
      u.outputTokens = (usage["output_tokens"] as? NSNumber)?.intValue ?? 0
    }
    return ClaudeCLI.Refined(text: ClaudeCLI.clean(response), usage: u)
  }
}
