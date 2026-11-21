import AppKit
import Foundation
import KitbagCore

/// Installs and tracks the two local helpers: whisper.cpp (speech to text) and Ollama (runs Gemma).
@MainActor
final class LocalSetup: ObservableObject {
  struct Option: Identifiable, Hashable {
    let id: String
    let name: String
  }

  static let whisperModels = [
    Option(id: "large-v3-q5_0", name: "Large v3 (most accurate, about 1.1 GB)"),
    Option(id: "large-v3-turbo-q5_0", name: "Large v3 Turbo (faster, about 570 MB)"),
    Option(id: "small-q5_1", name: "Small (about 180 MB)"),
    Option(id: "base-q5_1", name: "Base (about 60 MB, least accurate)"),
  ]

  private static let whisperCodes = """
    en zh de es ru ko fr ja pt tr pl ca nl ar sv it id hi fi vi he uk el ms cs ro da hu ta no th ur hr bg \
    lt la mi ml cy sk te fa lv bn sr az sl kn et mk br eu is hy ne mn bs kk sq sw gl mr pa si km sn yo so \
    af oc ka be tg sd gu am yi lo uz fo ht ps tk nn mt sa lb my bo tl mg as tt haw ln ha ba jw su
    """.split(separator: " ").map(String.init)

  /// Every language Whisper knows, by name, after "Auto-detect". All are treated alike.
  static let whisperLanguages: [Option] = {
    let current = Locale.current
    let all = whisperCodes.map { Option(id: $0, name: current.localizedString(forLanguageCode: $0)?.capitalized ?? $0) }
    return [Option(id: "auto", name: "Auto-detect")] + all.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
  }()

  static let gemmaModels = [
    Option(id: "gemma3:4b", name: "Gemma 3 4B (about 3.3 GB)"),
    Option(id: "gemma3:12b", name: "Gemma 3 12B (about 8 GB)"),
    Option(id: "gemma3:1b", name: "Gemma 3 1B (about 0.8 GB)"),
    Option(id: "gemma3n:e4b", name: "Gemma 3n E4B (about 7 GB)"),
  ]

  @Published private(set) var whisperBinary: String?
  @Published private(set) var whisperModelReady = false
  @Published private(set) var whisperBusy: String?
  @Published private(set) var whisperProgress: Double?
  @Published private(set) var ollamaPath: String?
  @Published private(set) var gemmaReady = false
  @Published private(set) var ollamaBusy: String?
  @Published var error: String?

  private let settings: DictationSettings
  private var server: Process?

  init(settings: DictationSettings) { self.settings = settings }

  // MARK: Where things live

  static var whisperDir: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Kitbag/whisper")
  }

  static func whisperModelURL(_ id: String) -> URL {
    whisperDir.appendingPathComponent("ggml-\(id).bin")
  }

  private static func firstExecutable(_ paths: [String]) -> String? {
    paths.first(where: FileManager.default.isExecutableFile)
  }

  func refresh() {
    whisperBinary = Self.firstExecutable(["/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli"])
    ollamaPath = Self.firstExecutable([
      "/opt/homebrew/bin/ollama", "/usr/local/bin/ollama",
      "/Applications/Ollama.app/Contents/Resources/ollama",
    ])
    whisperModelReady = FileManager.default.fileExists(
      atPath: Self.whisperModelURL(settings.whisperModel).path)
    gemmaReady = Self.ollamaHasModel(settings.gemmaModel)
  }

  /// Ollama keeps a manifest file for every model it has downloaded.
  static func ollamaHasModel(_ tag: String) -> Bool {
    let parts = tag.split(separator: ":", maxSplits: 1).map(String.init)
    guard let name = parts.first, !name.isEmpty else { return false }
    let version = parts.count > 1 ? parts[1] : "latest"
    var url = URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent(".ollama/models/manifests/registry.ollama.ai")
    if !name.contains("/") { url.appendPathComponent("library") }
    url.appendPathComponent(name)
    url.appendPathComponent(version)
    return FileManager.default.fileExists(atPath: url.path)
  }

  func stop() {
    server?.terminate()  // only the server Kitbag started itself
    server = nil
  }

  // MARK: Whisper

  func installWhisper() {
    guard whisperBusy == nil else { return }
    guard let brew = Shell.brewPath else {
      error = String(localized: "Homebrew isn't installed (brew.sh).")
      return
    }
    error = nil
    whisperBusy = String(localized: "Installing…")
    Task {
      let r = await Shell.run(brew, ["install", "whisper-cpp"], env: ["NONINTERACTIVE": "1"])
      whisperBusy = nil
      if r?.ok != true { error = r?.output.split(separator: "\n").last.map(String.init) ?? "brew failed" }
      refresh()
    }
  }

  func downloadWhisperModel() {
    guard whisperBusy == nil else { return }
    let id = settings.whisperModel
    guard let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(id).bin")
    else { return }
    error = nil
    whisperBusy = String(localized: "Downloading…")
    whisperProgress = 0
    try? FileManager.default.createDirectory(at: Self.whisperDir, withIntermediateDirectories: true)
    let dest = Self.whisperModelURL(id)
    Task { [weak self] in
      guard let self else { return }
      let failure = await Self.download(url, to: dest) { p in
        Task { @MainActor in self.whisperProgress = p }
      }
      whisperBusy = nil
      whisperProgress = nil
      if let failure { error = failure }
      refresh()
    }
  }

  private final class Holder: @unchecked Sendable { var observation: NSKeyValueObservation? }

  private nonisolated static func download(
    _ url: URL, to dest: URL, progress: @escaping @Sendable (Double) -> Void
  ) async -> String? {
    await withCheckedContinuation { cont in
      let holder = Holder()
      let task = URLSession.shared.downloadTask(with: url) { tmp, response, err in
        holder.observation = nil
        if let err { return cont.resume(returning: err.localizedDescription) }
        guard let tmp, (response as? HTTPURLResponse)?.statusCode == 200 else {
          return cont.resume(returning: String(localized: "The download failed."))
        }
        do {
          try? FileManager.default.removeItem(at: dest)
          try FileManager.default.moveItem(at: tmp, to: dest)
          cont.resume(returning: nil)
        } catch { cont.resume(returning: error.localizedDescription) }
      }
      holder.observation = task.progress.observe(\.fractionCompleted) { p, _ in
        progress(p.fractionCompleted)
      }
      task.resume()
    }
  }

  func deleteWhisperModel() {
    guard whisperBusy == nil,
      Shell.confirm(
        String(localized: "Delete the Whisper model?"),
        String(localized: "The file is removed from this Mac. You can download it again later."),
        action: String(localized: "Delete"))
    else { return }
    try? FileManager.default.removeItem(at: Self.whisperModelURL(settings.whisperModel))
    refresh()
  }

  func uninstallWhisper() {
    guard whisperBusy == nil, let brew = Shell.brewPath,
      Shell.confirm(
        String(localized: "Uninstall Whisper?"),
        String(localized: "whisper-cpp is removed with Homebrew. Downloaded models stay until you delete them."),
        action: String(localized: "Uninstall"))
    else { return }
    error = nil
    whisperBusy = String(localized: "Removing…")
    Task { [weak self] in
      guard let self else { return }
      let r = await Shell.run(brew, ["uninstall", "whisper-cpp"], env: ["NONINTERACTIVE": "1"])
      whisperBusy = nil
      if r?.ok != true { error = r?.output.split(separator: "\n").last.map(String.init) ?? "brew failed" }
      refresh()
    }
  }

  // MARK: Ollama and Gemma

  func deleteGemma() {
    guard ollamaBusy == nil, let ollama = ollamaPath else { return }
    let tag = settings.gemmaModel
    guard
      Shell.confirm(
        String(localized: "Delete \(tag)?"),
        String(localized: "The model is removed from Ollama and frees its disk space. You can download it again later."),
        action: String(localized: "Delete"))
    else { return }
    error = nil
    ollamaBusy = String(localized: "Removing…")
    Task { [weak self] in
      guard let self else { return }
      if await ensureServer() {
        let r = await Shell.run(ollama, ["rm", tag])
        if r?.ok != true { error = r?.output.split(separator: "\n").last.map(String.init) ?? "Couldn't remove it." }
      }
      ollamaBusy = nil
      refresh()
    }
  }

  func uninstallOllama() {
    guard ollamaBusy == nil, let brew = Shell.brewPath,
      Shell.confirm(
        String(localized: "Uninstall Ollama?"),
        String(localized: "Ollama is removed with Homebrew. Models you downloaded stay in ~/.ollama until you delete them first."),
        action: String(localized: "Uninstall"))
    else { return }
    error = nil
    stop()
    ollamaBusy = String(localized: "Removing…")
    Task { [weak self] in
      guard let self else { return }
      let r = await Shell.run(brew, ["uninstall", "ollama"], env: ["NONINTERACTIVE": "1"])
      ollamaBusy = nil
      if r?.ok != true { error = r?.output.split(separator: "\n").last.map(String.init) ?? "brew failed" }
      refresh()
    }
  }

  func installOllama() {
    guard ollamaBusy == nil else { return }
    guard let brew = Shell.brewPath else {
      error = String(localized: "Homebrew isn't installed (brew.sh).")
      return
    }
    error = nil
    ollamaBusy = String(localized: "Installing…")
    Task {
      let r = await Shell.run(brew, ["install", "ollama"], env: ["NONINTERACTIVE": "1"])
      ollamaBusy = nil
      if r?.ok != true { error = r?.output.split(separator: "\n").last.map(String.init) ?? "brew failed" }
      refresh()
    }
  }

  func downloadGemma() {
    guard ollamaBusy == nil, let ollama = ollamaPath else { return }
    let tag = settings.gemmaModel
    error = nil
    ollamaBusy = String(localized: "Starting…")
    Task { [weak self] in
      guard let self else { return }
      guard await ensureServer() else {
        ollamaBusy = nil
        error = String(localized: "Couldn't start Ollama.")
        return
      }
      let r = await Shell.run(ollama, ["pull", tag]) { [weak self] chunk in
        let last = chunk.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
          .components(separatedBy: CharacterSet(charactersIn: "\r\n")).map { $0.trimmingCharacters(in: .whitespaces) }
          .last { !$0.isEmpty }
        if let last { self?.ollamaBusy = last }
      }
      ollamaBusy = nil
      if r?.ok != true { error = r?.output.split(separator: "\n").last.map(String.init) ?? "pull failed" }
      refresh()
    }
  }

  /// Makes sure the Ollama server is answering, starting it if needed.
  func ensureServer() async -> Bool {
    if await OllamaClient.isUp() { return true }
    guard let path = ollamaPath else { return false }
    if server?.isRunning != true {
      let p = Process()
      p.executableURL = URL(fileURLWithPath: path)
      p.arguments = ["serve"]
      p.standardOutput = FileHandle.nullDevice
      p.standardError = FileHandle.nullDevice
      p.standardInput = FileHandle.nullDevice
      do { try p.run() } catch { return false }
      server = p
    }
    for _ in 0..<40 {
      try? await Task.sleep(nanoseconds: 250_000_000)
      if await OllamaClient.isUp() { return true }
    }
    return false
  }
}

/// Cleans up a transcript with a model running in Ollama (for example Gemma).
enum OllamaClient {
  static let base = URL(string: "http://127.0.0.1:11434")!

  static func isUp() async -> Bool {
    var req = URLRequest(url: base.appendingPathComponent("api/tags"))
    req.timeoutInterval = 1.5
    guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
    return (resp as? HTTPURLResponse)?.statusCode == 200
  }

  static func refine(_ text: String, model: String, prompt: String = ClaudeCLI.instructions) async throws -> ClaudeCLI.Refined {
    var req = URLRequest(url: base.appendingPathComponent("api/chat"))
    req.httpMethod = "POST"
    req.timeoutInterval = 90
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let body: [String: Any] = [
      "model": model, "stream": false, "keep_alive": "30m",
      "options": ["temperature": 0.2, "num_ctx": 4096],
      "messages": [
        ["role": "system", "content": prompt],
        ["role": "user", "content": "<transcript>\(text)</transcript>"],
      ],
    ]
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard (resp as? HTTPURLResponse)?.statusCode == 200,
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let message = obj["message"] as? [String: Any], let content = message["content"] as? String
    else { throw ClaudeCLI.RefineError.failed(String(localized: "Ollama didn't answer.")) }
    let cleaned = ClaudeCLI.clean(content)
    guard !cleaned.isEmpty else { throw ClaudeCLI.RefineError.failed(String(localized: "Empty answer.")) }
    var usage = ClaudeCLI.Usage()  // local, so no cost
    usage.inputTokens = (obj["prompt_eval_count"] as? NSNumber)?.intValue ?? 0
    usage.outputTokens = (obj["eval_count"] as? NSNumber)?.intValue ?? 0
    return ClaudeCLI.Refined(text: cleaned, usage: usage)
  }
}
