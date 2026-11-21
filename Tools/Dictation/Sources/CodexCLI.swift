import Foundation

/// Asks the OpenAI Codex CLI to tidy a transcript.
enum CodexCLI {
  static func refine(
    _ text: String, model: String, effort: String, prompt: String = ClaudeCLI.instructions,
    cli: String
  ) async throws -> ClaudeCLI.Refined {
    var args = [
      "exec", "--ephemeral", "--skip-git-repo-check", "--ignore-user-config", "--ignore-rules",
      "--sandbox", "read-only", "--json",
    ]
    if !model.isEmpty { args += ["-m", model] }
    if !effort.isEmpty { args += ["-c", "model_reasoning_effort=\(effort)"] }
    args.append("\(prompt)\n\n<transcript>\(text)</transcript>")
    let r = try await CLIRunner.run(
      cli, args, timeout: 60, startFailure: String(localized: "Couldn't start Codex."))
    if r.status == 0, let parsed = parse(r.out), !parsed.text.isEmpty { return parsed }
    let reason = CLIRunner.lastLine(r.err)
    throw ClaudeCLI.RefineError.failed(reason ?? String(localized: "Codex didn't answer."))
  }

  /// Reads the JSONL stream of `codex exec --json`: the last agent message plus token usage.
  static func parse(_ data: Data) -> ClaudeCLI.Refined? {
    var message: String?
    var u = ClaudeCLI.Usage()
    for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
      guard let d = line.data(using: .utf8),
        let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
      else { continue }
      switch obj["type"] as? String {
      case "item.completed":
        if let item = obj["item"] as? [String: Any], item["type"] as? String == "agent_message",
          let t = item["text"] as? String
        {
          message = t
        }
      case "turn.completed":
        if let usage = obj["usage"] as? [String: Any] {
          u.inputTokens += (usage["input_tokens"] as? NSNumber)?.intValue ?? 0
          u.outputTokens += (usage["output_tokens"] as? NSNumber)?.intValue ?? 0
        }
      default: break
      }
    }
    guard let message else { return nil }
    return ClaudeCLI.Refined(text: ClaudeCLI.clean(message), usage: u)
  }
}
