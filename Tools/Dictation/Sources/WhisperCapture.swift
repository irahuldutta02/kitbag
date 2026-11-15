import AVFoundation
import Foundation
import KitbagCore

/// Anything that can record your voice and hand back the text.
@MainActor
protocol Recorder: AnyObject {
  var onLevel: ((Float) -> Void)? { get set }
  func start(language: String) throws
  func stop() async -> String
  func cancel()
}

extension SpeechCapture: Recorder {}

/// Records to a 16 kHz WAV file, then transcribes it on this Mac with whisper.cpp.
@MainActor
final class WhisperCapture: Recorder {
  enum WhisperError: LocalizedError {
    case notReady
    var errorDescription: String? { String(localized: "Whisper isn't set up yet.") }
  }

  /// Paths filled in by the model before each recording.
  var binary: String?
  var modelPath: String?
  /// Languages the person speaks; with auto-detect, Whisper's guess is steered towards these.
  var allowed: [String] = []
  var onLevel: ((Float) -> Void)?

  private let engine = AVAudioEngine()
  private let sink = WavSink()
  private var wav: URL?
  private var language = "auto"

  /// `language` is a Whisper language code, or "auto".
  func start(language: String) throws {
    guard binary != nil, let modelPath, FileManager.default.fileExists(atPath: modelPath) else {
      throw WhisperError.notReady
    }
    self.language = language.isEmpty ? "auto" : language
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("kitbag-\(UUID().uuidString).wav")
    try sink.open(url)
    wav = url

    let input = engine.inputNode
    let inFormat = input.outputFormat(forBus: 0)
    guard
      let outFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
      let converter = AVAudioConverter(from: inFormat, to: outFormat)
    else { throw WhisperError.notReady }
    input.installTap(
      onBus: 0, bufferSize: 4096, format: inFormat,
      block: Self.makeTap(sink: sink, converter: converter, outFormat: outFormat) { [weak self] level in
        Task { @MainActor in self?.onLevel?(level) }
      })
    engine.prepare()
    do { try engine.start() } catch {
      input.removeTap(onBus: 0)
      cleanup()
      throw error
    }
  }

  func stop() async -> String {
    teardown()
    guard let wav, let binary, let modelPath else { return "" }
    let seconds = sink.seconds
    sink.close()
    defer { cleanup() }
    guard seconds > 0.4 else { return "" }  // a tap, not speech

    let base = FileManager.default.temporaryDirectory.appendingPathComponent("kitbag-\(UUID().uuidString)").path
    let threads = max(2, min(8, ProcessInfo.processInfo.activeProcessorCount - 2))
    var lang = language
    if lang == "auto", !allowed.isEmpty,
      let r = await Shell.run(binary, ["-m", modelPath, "-f", wav.path, "-dl", "-t", "\(threads)"]),
      let detected = Self.parseDetected(r.output)
    {
      lang = Self.resolve(detected, allowed: allowed)
    }
    _ = await Shell.run(
      binary, ["-m", modelPath, "-f", wav.path, "-l", lang, "-nt", "-np", "-t", "\(threads)", "-otxt", "-of", base])
    let out = URL(fileURLWithPath: base + ".txt")
    defer { try? FileManager.default.removeItem(at: out) }
    guard let text = try? String(contentsOf: out, encoding: .utf8) else { return "" }
    return Self.tidy(text)
  }

  func cancel() {
    teardown()
    sink.close()
    cleanup()
  }

  private func teardown() {
    if engine.isRunning { engine.stop() }
    engine.inputNode.removeTap(onBus: 0)
  }

  private func cleanup() {
    if let wav { try? FileManager.default.removeItem(at: wav) }
    wav = nil
  }

  /// The language whisper-cli reports after `-dl`, for example "xx" from "auto-detected language: xx (p = 0.93)".
  nonisolated static func parseDetected(_ output: String) -> String? {
    guard let r = output.range(of: "auto-detected language: ") else { return nil }
    let code = output[r.upperBound...].prefix { $0.isLetter }
    return code.isEmpty ? nil : String(code)
  }

  /// With auto-detect, a guess outside the languages you picked is corrected when you picked just one.
  nonisolated static func resolve(_ detected: String, allowed: [String]) -> String {
    if allowed.contains(detected) { return detected }
    return allowed.count == 1 ? allowed[0] : detected
  }

  /// Joins lines and drops markers Whisper prints for silence or noise, like [BLANK_AUDIO].
  nonisolated static func tidy(_ s: String) -> String {
    let noMarks = s.replacingOccurrences(of: "\\[[A-Za-z_ ]+\\]", with: " ", options: .regularExpression)
    return noMarks.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }.joined(separator: " ")
      .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // Runs on the audio thread, so it must not inherit the main actor.
  private nonisolated static func makeTap(
    sink: WavSink, converter: AVAudioConverter, outFormat: AVAudioFormat,
    level: @escaping @Sendable (Float) -> Void
  ) -> AVAudioNodeTapBlock {
    return { buffer, _ in
      let ratio = outFormat.sampleRate / buffer.format.sampleRate
      let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
      guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
      nonisolated(unsafe) var supplied = false
      var error: NSError?
      converter.convert(to: out, error: &error) { _, status in
        if supplied {
          status.pointee = .noDataNow
          return nil
        }
        supplied = true
        status.pointee = .haveData
        return buffer
      }
      guard error == nil, out.frameLength > 0, let data = out.floatChannelData?[0] else { return }
      sink.write(out)
      let n = Int(out.frameLength)
      var sum: Float = 0
      for i in 0..<n { sum += data[i] * data[i] }
      level(min(1, (sum / Float(n)).squareRoot() * 14))
    }
  }
}

/// Thread-safe writer for the WAV file the audio thread fills.
final class WavSink: @unchecked Sendable {
  private let lock = NSLock()
  private var file: AVAudioFile?
  private var frames: AVAudioFramePosition = 0

  func open(_ url: URL) throws {
    lock.lock()
    defer { lock.unlock() }
    frames = 0
    file = try AVAudioFile(
      forWriting: url,
      settings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
      ],
      commonFormat: .pcmFormatFloat32, interleaved: false)
  }

  func write(_ buffer: AVAudioPCMBuffer) {
    lock.lock()
    defer { lock.unlock() }
    guard let file else { return }
    try? file.write(from: buffer)
    frames += AVAudioFramePosition(buffer.frameLength)
  }

  var seconds: Double {
    lock.lock()
    defer { lock.unlock() }
    return Double(frames) / 16_000
  }

  func close() {
    lock.lock()
    file = nil  // closing the file writes the WAV header
    lock.unlock()
  }
}
