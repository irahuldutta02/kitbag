import AVFoundation
import Foundation
import Speech

/// Records the microphone and turns it into text while you talk (on this Mac when possible).
@MainActor
final class SpeechCapture {
  enum CaptureError: LocalizedError {
    case unavailable
    var errorDescription: String? { String(localized: "Speech recognition isn't available.") }
  }

  /// The tap feeds whichever request is current, so the recognizer can be restarted mid-session.
  private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    func set(_ r: SFSpeechAudioBufferRecognitionRequest?) { lock.lock(); request = r; lock.unlock() }
    func append(_ b: AVAudioPCMBuffer) { lock.lock(); request?.append(b); lock.unlock() }
    func end() { lock.lock(); request?.endAudio(); lock.unlock() }
  }

  private let mic = MicSource()
  private let box = RequestBox()
  private var recognizer: SFSpeechRecognizer?
  private var task: SFSpeechRecognitionTask?
  private var generation = 0
  private var running = false
  private var stopping = false
  /// Finished pieces of the session, plus the piece still being recognized.
  private var committed: [String] = []
  private var current = ""
  private var finishWaiter: CheckedContinuation<Void, Never>?

  var onLevel: ((Float) -> Void)?

  func start(language: String = "") throws {
    let locale = language.isEmpty ? Locale.current : Locale(identifier: language)
    let r = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer()
    guard let r, r.isAvailable else { throw CaptureError.unavailable }
    recognizer = r
    committed = []
    current = ""
    stopping = false
    beginTask()

    do {
      try mic.start(
        Self.makeTap(box: box) { [weak self] level in
          Task { @MainActor in self?.onLevel?(level) }
        })
      running = true
    } catch {
      task?.cancel()
      task = nil
      box.set(nil)
      throw error
    }
  }

  /// Starts a fresh recognition request. The recognizer ends a request after a long pause, so a
  /// session may need several; their texts are joined.
  private func beginTask() {
    guard let recognizer else { return }
    generation += 1
    let mine = generation
    let req = SFSpeechAudioBufferRecognitionRequest()
    req.shouldReportPartialResults = true  // needed to keep every phrase, not shown anywhere
    req.addsPunctuation = true
    if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
    box.set(req)
    task = recognizer.recognitionTask(
      with: req,
      resultHandler: Self.makeResultHandler { [weak self] text, done in
        Task { @MainActor in self?.received(text, done: done, generation: mine) }
      })
  }

  /// Stops recording and returns everything that was said.
  func stop() async -> String {
    guard running else { return joined() }
    running = false
    stopping = true
    teardownAudio()
    box.end()
    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
      finishWaiter = cont
      Task { @MainActor [weak self] in  // the recognizer can be slow to say it is done
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        self?.resumeWaiter()
      }
    }
    task?.cancel()
    task = nil
    box.set(nil)
    return joined()
  }

  func cancel() {
    running = false
    stopping = true
    teardownAudio()
    task?.cancel()
    task = nil
    box.set(nil)
    committed = []
    current = ""
    resumeWaiter()
  }

  private func joined() -> String {
    (committed + [current]).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }.joined(separator: " ")
  }

  private func teardownAudio() {
    mic.stop()
  }

  private func received(_ text: String?, done: Bool, generation gen: Int) {
    guard gen == generation else { return }  // an older request
    if let text, !text.isEmpty {
      // After a pause the recognizer can start over with new words instead of extending the old ones.
      if !current.isEmpty && text.count < current.count / 2 {
        committed.append(current)
      }
      current = text
    }
    if done {
      if !current.isEmpty { committed.append(current) }
      current = ""
      if stopping {
        resumeWaiter()
      } else if running {
        beginTask()  // it ended during a pause; keep listening
      }
    }
  }

  private func resumeWaiter() {
    finishWaiter?.resume()
    finishWaiter = nil
  }

  // These run on audio / recognizer threads, so they must not inherit the main actor.
  private nonisolated static func makeTap(
    box: RequestBox, level: @escaping @Sendable (Float) -> Void
  ) -> @Sendable (AVAudioPCMBuffer) -> Void {
    return { buffer in
      box.append(buffer)
      guard let data = buffer.floatChannelData?[0] else { return }
      let n = Int(buffer.frameLength)
      guard n > 0 else { return }
      var sum: Float = 0
      for i in 0..<n { sum += data[i] * data[i] }
      let rms = (sum / Float(n)).squareRoot()
      level(min(1, rms * 14))
    }
  }

  private nonisolated static func makeResultHandler(
    _ deliver: @escaping @Sendable (String?, Bool) -> Void
  ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
    return { result, error in
      deliver(result?.bestTranscription.formattedString, result?.isFinal == true || error != nil)
    }
  }
}
