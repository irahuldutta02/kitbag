import AVFoundation
import AppKit
import Combine
import KitbagCore
import Speech

/// Runs one dictation at a time: shortcut -> record -> (Claude cleans it up) -> paste.
@MainActor
final class DictationModel: ObservableObject {
  enum Phase: Equatable { case idle, listening, processing }

  struct StartError: LocalizedError {
    let errorDescription: String?
  }

  let settings = DictationSettings()
  @Published private(set) var phase: Phase = .idle
  @Published private(set) var lastText = ""
  @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
  /// True while a run started from the settings test box is in progress.
  @Published private(set) var testing = false
  private var testSink: ((String) -> Void)?

  lazy var local = LocalSetup(settings: settings)
  private let appleCapture = SpeechCapture()
  private let whisper = WhisperCapture()
  private lazy var recorder: any Recorder = appleCapture
  private let overlay = DictationOverlay()
  private let silencer = Silencer()
  private let hotKey = GlobalHotKey()
  private let escKey = GlobalHotKey()
  private let guide = AccessibilityGuide()
  private let fnWatcher = FnKeyWatcher()
  private var fnDownAt: Date?
  private var lastTapAt: Date?
  private var locked = false  // started by a double click: stays on until the next double click
  private var abortStart = false
  private var stopAfterStart = false
  private var fnTriggered = false
  private static let holdThreshold = 0.3
  private static let doubleClickWindow = 0.45
  private var bag = Set<AnyCancellable>()
  private var starting = false
  private var hideTask: Task<Void, Never>?
  private var listeningSince: Date?

  // MARK: Lifecycle

  func start() throws {
    hotKey.onPress = { [weak self] in self?.toggle() }
    escKey.onPress = { [weak self] in self?.cancel() }
    fnWatcher.onDown = { [weak self] in self?.fnDown() }
    fnWatcher.onUp = { [weak self] in self?.fnUp() }
    appleCapture.onLevel = { [weak self] in self?.overlay.state.push($0) }
    whisper.onLevel = { [weak self] in self?.overlay.state.push($0) }
    settings.$shortcut.dropFirst().sink { [weak self] _ in _ = self?.registerHotKey() }.store(in: &bag)
    refreshStatus()
    guard registerHotKey() else {
      throw StartError(
        errorDescription: String(localized: "\(settings.shortcut.display) is used by another app. Pick a different shortcut."))
    }
  }

  func stop() {
    cancel()
    silencer.restore()
    hotKey.unregister()
    escKey.unregister()
    fnWatcher.stop()
    bag.removeAll()
    guide.close()
    local.stop()
  }

  func registerHotKey() -> Bool {
    if settings.shortcut.isFn {
      hotKey.unregister()
      fnWatcher.start()
      return true
    }
    fnWatcher.stop()
    return hotKey.register(keyCode: settings.shortcut.keyCode, modifiers: settings.shortcut.modifiers)
  }

  /// Frees the shortcut while the person is choosing a new one.
  func pauseHotKey(_ paused: Bool) {
    if paused {
      hotKey.unregister()
      fnWatcher.stop()
    } else {
      _ = registerHotKey()
    }
  }

  func refreshStatus() {
    ProviderManager.shared.refreshAll()
    local.refresh()
    let granted = AXIsProcessTrusted()
    if granted && !accessibilityGranted { _ = registerHotKey() }  // the Globe key can be heard now
    accessibilityGranted = granted
  }

  // MARK: Dictation

  // MARK: Globe (fn) key: hold to speak, or double click to start and double click to stop

  private func fnDown() {
    let now = Date()
    fnDownAt = now
    if locked {  // second click of the stop
      if let t = lastTapAt, now.timeIntervalSince(t) < Self.doubleClickWindow {
        lastTapAt = nil
        finish()
      }
      return
    }
    if phase == .idle && !starting {
      fnTriggered = true
      abortStart = false
      stopAfterStart = false
      begin()
    }
  }

  private func fnUp() {
    guard let down = fnDownAt else { return }
    fnDownAt = nil
    let now = Date()
    let held = now.timeIntervalSince(down)
    if locked {
      if held < Self.holdThreshold { lastTapAt = now }
      return
    }
    if held >= Self.holdThreshold {  // hold to speak: let go to finish
      lastTapAt = nil
      if phase == .listening { finish() } else if starting { stopAfterStart = true }
      return
    }
    if let t = lastTapAt, now.timeIntervalSince(t) < Self.doubleClickWindow {  // double click: keep going
      lastTapAt = nil
      locked = true
      if phase == .idle && !starting { begin() }
      return
    }
    lastTapAt = now  // a single click: not dictation (yet), so drop the recording quietly
    stopSilently()
  }

  private func stopSilently() {
    if starting {
      abortStart = true
    } else if phase == .listening {
      escKey.unregister()
      recorder.cancel()
      silencer.restore()
      phase = .idle
      overlay.hide()
    }
  }

  /// Start/stop from the test box in settings: the text goes to `sink` instead of being pasted elsewhere.
  func toggleTest(_ sink: @escaping (String) -> Void) {
    if phase == .idle && !starting {
      testSink = sink
      testing = true
    }
    toggle()
  }

  private func endTest() {
    testSink = nil
    testing = false
  }

  func toggle() {
    fnTriggered = false
    switch phase {
    case .idle: begin()
    case .listening: finish()
    case .processing: break
    }
  }

  private func begin() {
    guard !starting else { return }
    starting = true
    hideTask?.cancel()
    Task {
      defer {
        starting = false
        if phase != .listening { endTest() }
      }
      local.refresh()
      let useWhisper = settings.engine == "whisper"
      if useWhisper && (local.whisperBinary == nil || !local.whisperModelReady) {
        return flash(String(localized: "Set up Whisper in Dictation settings first"), error: true)
      }
      guard await ensurePermissions(speech: !useWhisper) else { return }
      if abortStart {
        abortStart = false
        return
      }
      silencer.silence()  // keep the Mac quiet while listening
      do {
        overlay.state.reset()
        if useWhisper {
          whisper.binary = local.whisperBinary
          whisper.modelPath = LocalSetup.whisperModelURL(settings.whisperModel).path
          whisper.allowed = settings.allowedLanguages
          recorder = whisper
        } else {
          recorder = appleCapture
        }
        try recorder.start(language: useWhisper ? settings.whisperLanguage : settings.language)
        phase = .listening
        listeningSince = Date()
        if fnTriggered {  // a quick tap shouldn't flash the pill
          Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if phase == .listening { overlay.show() }
          }
        } else {
          overlay.show()
        }
        _ = escKey.register(keyCode: 53, modifiers: 0)  // esc cancels while listening
        if stopAfterStart {
          stopAfterStart = false
          finish()
        }
      } catch {
        silencer.restore()
        flash(error.localizedDescription, error: true)
      }
    }
  }

  private func finish() {
    locked = false
    let sink = testSink
    endTest()
    phase = .processing
    escKey.unregister()
    overlay.state.mode = .processing
    let spoke = listeningSince.map { Date().timeIntervalSince($0) } ?? 0
    listeningSince = nil
    Task {
      let raw = await recorder.stop()
      silencer.restore()  // recording is over: bring the sound back before the slow clean-up
      guard !raw.isEmpty else {
        phase = .idle
        return flash(String(localized: "Didn't catch that"), error: true)
      }
      var text = raw
      var note: String?
      var usage: ClaudeCLI.Usage?
      var usedModel: String?
      let prompt = settings.effectivePrompt
      switch settings.provider {
      case "claude":
        if let cli = ProviderManager.shared.effectiveBinaryPath(for: .claude) {
          do {
            let r = try await ClaudeCLI.refine(
              raw, model: settings.model, effort: settings.effort, prompt: prompt, cli: cli)
            text = r.text
            usage = r.usage
            usedModel = settings.model
          } catch {
            note = String(localized: "Claude couldn't clean it up, pasted as spoken")
          }
        } else {
          note = String(localized: "Claude Code isn't installed, pasted as spoken")
        }
      case "antigravity":
        if let cli = ProviderManager.shared.effectiveBinaryPath(for: .antigravity) {
          do {
            let r = try await AntigravityCLI.refine(
              raw, model: settings.agyModel, effort: settings.agyEffort, prompt: prompt, cli: cli)
            text = r.text
            usage = r.usage
            usedModel = settings.agyModel
          } catch {
            note = String(localized: "Antigravity couldn't clean it up, pasted as spoken")
          }
        } else {
          note = String(localized: "Antigravity isn't installed, pasted as spoken")
        }
      case "codex":
        if let cli = ProviderManager.shared.effectiveBinaryPath(for: .codex) {
          do {
            let r = try await CodexCLI.refine(
              raw, model: settings.codexModel, effort: settings.codexEffort, prompt: prompt, cli: cli)
            text = r.text
            usage = r.usage
            usedModel = settings.codexModel.isEmpty ? "codex" : settings.codexModel
          } catch {
            note = String(localized: "Codex couldn't clean it up, pasted as spoken")
          }
        } else {
          note = String(localized: "Codex isn't installed, pasted as spoken")
        }
      case "gemma":
        if await local.ensureServer() {
          do {
            local.noteLoaded(settings.gemmaModel)
            let r = try await OllamaClient.refine(raw, model: settings.gemmaModel, prompt: prompt)
            text = r.text
            usage = r.usage
            usedModel = settings.gemmaModel
          } catch {
            note = String(localized: "Gemma couldn't clean it up, pasted as spoken")
          }
        } else {
          note = String(localized: "Ollama isn't running, pasted as spoken")
        }
      default: break
      }
      if let sink {
        phase = .idle
        sink(text)
        if let note { flash(note, error: true) } else { overlay.hide() }
        return
      }
      lastText = text
      phase = .idle
      DictationStats.shared.add(
        DictationSession(
          date: Date(), speakSeconds: spoke, rawWords: DictationStats.words(raw),
          finalWords: DictationStats.words(text), model: usedModel,
          inputTokens: usage?.inputTokens ?? 0, outputTokens: usage?.outputTokens ?? 0,
          cost: usage?.cost ?? 0, text: text))
      if !Paster.paste(text) {
        flash(String(localized: "Copied. Press ⌘V to paste (allow Accessibility for auto-paste)"), error: true)
      } else if let note {
        flash(note, error: true)
      } else {
        overlay.hide()
      }
    }
  }

  private func cancel() {
    locked = false
    guard phase == .listening else { return }
    escKey.unregister()
    recorder.cancel()
    silencer.restore()
    phase = .idle
    overlay.hide()
    endTest()
  }

  private func flash(_ text: String, error: Bool) {
    overlay.state.mode = .message(text, error: error)
    overlay.show()
    hideTask?.cancel()
    hideTask = Task {
      try? await Task.sleep(nanoseconds: 2_800_000_000)
      if !Task.isCancelled { overlay.hide() }
    }
  }

  private func ensurePermissions(speech: Bool) async -> Bool {
    if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
      _ = await AVCaptureDevice.requestAccess(for: .audio)
    }
    guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
      flash(String(localized: "Allow Microphone for Kitbag in System Settings"), error: true)
      Self.openPrivacy("Privacy_Microphone")
      return false
    }
    guard speech else { return true }  // Whisper only needs the microphone
    if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
      await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
        SFSpeechRecognizer.requestAuthorization { _ in c.resume() }
      }
    }
    guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
      flash(String(localized: "Allow Speech Recognition for Kitbag in System Settings"), error: true)
      Self.openPrivacy("Privacy_SpeechRecognition")
      return false
    }
    return true
  }

  private static func openPrivacy(_ pane: String) {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
      NSWorkspace.shared.open(url)
    }
  }

  // MARK: Settings actions

  func openKeyboardSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
      NSWorkspace.shared.open(url)
    }
  }

  func allowAutoPaste() {
    guide.begin { [weak self] in self?.refreshStatus() }
  }
}
