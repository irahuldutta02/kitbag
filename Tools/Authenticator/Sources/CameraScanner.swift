@preconcurrency import AVFoundation
import AppKit
import CoreImage
import KitbagCore
import Vision

/// Reads a QR code held up to the Mac's camera. A small window shows what the camera sees and
/// closes by itself as soon as a code is read. Nothing is recorded or saved.
@MainActor
final class CameraScanner: NSObject, AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate,
  NSWindowDelegate
{
  private var session: AVCaptureSession?
  private var window: NSWindow?
  private var continuation: CheckedContinuation<QRScanner.Outcome, Never>?

  private static var current: CameraScanner?
  private let frameQueue = DispatchQueue(label: "kitbag.camera.frames")
  private nonisolated(unsafe) var lastRead = Date.distantPast

  static var cameraAllowed: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .authorized }
  static var cameraDenied: Bool {
    [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .video))
  }

  static func openCameraSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
      NSWorkspace.shared.open(url)
    }
  }

  /// Opens the camera window and waits for a code (or for the window to be closed).
  static func scan() async -> QRScanner.Outcome {
    guard current == nil else { return .cancelled }
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: break
    case .notDetermined:
      guard await AVCaptureDevice.requestAccess(for: .video) else { return .failed(deniedMessage) }
    default: return .failed(deniedMessage)
    }
    guard let device = AVCaptureDevice.default(for: .video)
      ?? AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified).devices.first
    else {
      return .failed("No camera was found on this Mac.")
    }
    let scanner = CameraScanner()
    current = scanner
    defer { current = nil }
    return await scanner.run(device: device)
  }

  static let deniedMessage =
    "Kitbag isn't allowed to use the camera. Allow it in System Settings ▸ Privacy & Security ▸ Camera, then try again."

  private func run(device: AVCaptureDevice) async -> QRScanner.Outcome {
    let session = AVCaptureSession()
    session.beginConfiguration()
    // Dense codes (Google Authenticator's export holds many accounts) need as many pixels as possible.
    for preset in [AVCaptureSession.Preset.hd1920x1080, .hd1280x720, .high] where device.supportsSessionPreset(preset) {
      session.sessionPreset = preset
      break
    }
    let output = AVCaptureMetadataOutput()
    guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input), session.canAddOutput(output)
    else {
      return .failed("The camera couldn't be started. Another app may be using it.")
    }
    session.addInput(input)
    session.addOutput(output)
    output.setMetadataObjectsDelegate(self, queue: .main)
    if output.availableMetadataObjectTypes.contains(.qr) { output.metadataObjectTypes = [.qr] }
    // The built-in detector misses large codes, so every few frames are also read with Vision.
    let frames = AVCaptureVideoDataOutput()
    frames.alwaysDiscardsLateVideoFrames = true
    frames.setSampleBufferDelegate(self, queue: frameQueue)
    if session.canAddOutput(frames) { session.addOutput(frames) }
    session.commitConfiguration()
    self.session = session

    showWindow(session: session)
    let queue = DispatchQueue(label: "kitbag.camera")
    queue.async { session.startRunning() }

    let outcome = await withCheckedContinuation { (c: CheckedContinuation<QRScanner.Outcome, Never>) in
      continuation = c
    }
    queue.async { session.stopRunning() }  // turn the camera light off
    self.session = nil
    window?.delegate = nil
    window?.orderOut(nil)
    window?.contentView = nil
    window = nil
    return outcome
  }

  private func finish(_ outcome: QRScanner.Outcome) {
    guard let c = continuation else { return }
    continuation = nil
    c.resume(returning: outcome)
  }

  // MARK: Window

  private func showWindow(session: AVCaptureSession) {
    let size = NSSize(width: 420, height: 380)
    let w = NSWindow(
      contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    w.title = "Scan QR Code"
    w.isReleasedWhenClosed = false
    w.level = .floating
    w.delegate = self
    w.collectionBehavior = [.moveToActiveSpace]

    let preview = PreviewView(session: session)
    preview.translatesAutoresizingMaskIntoConstraints = false
    let hint = NSTextField(wrappingLabelWithString: "Hold the QR code in front of the camera, close enough to fill most of the view. Turn the phone's brightness up and keep it steady. It's read on this Mac and nothing is recorded.")
    hint.font = .systemFont(ofSize: 12)
    hint.textColor = .secondaryLabelColor
    hint.alignment = .center
    hint.translatesAutoresizingMaskIntoConstraints = false
    let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
    cancel.keyEquivalent = "\u{1b}"
    cancel.translatesAutoresizingMaskIntoConstraints = false

    let content = NSView(frame: NSRect(origin: .zero, size: size))
    [preview, hint, cancel].forEach(content.addSubview)
    NSLayoutConstraint.activate([
      preview.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
      preview.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
      preview.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
      preview.heightAnchor.constraint(equalToConstant: 270),
      hint.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 8),
      hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
      hint.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
      cancel.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 8),
      cancel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
    ])
    w.contentView = content
    w.center()
    NSApp.activate(ignoringOtherApps: true)
    w.makeKeyAndOrderFront(nil)
    window = w
  }

  @objc private func cancelTapped() { finish(.cancelled) }

  func windowWillClose(_ notification: Notification) { finish(.cancelled) }

  // MARK: Detection

  nonisolated func metadataOutput(
    _ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection
  ) {
    let codes = objects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
    guard !codes.isEmpty else { return }
    MainActor.assumeIsolated { finish(.found(codes)) }  // delegate queue is the main queue
  }

  nonisolated func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
  ) {
    guard Date().timeIntervalSince(lastRead) > 0.25, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    lastRead = Date()
    let request = VNDetectBarcodesRequest()
    request.symbologies = [.qr]
    try? VNImageRequestHandler(cvPixelBuffer: buffer, options: [:]).perform([request])
    var codes = (request.results ?? []).compactMap(\.payloadStringValue)
    if codes.isEmpty,  // second opinion, which sometimes reads what Vision can't
      let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
    {
      codes = detector.features(in: CIImage(cvPixelBuffer: buffer)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }
    guard !codes.isEmpty else { return }
    DispatchQueue.main.async { MainActor.assumeIsolated { self.finish(.found(codes)) } }
  }
}

private final class PreviewView: NSView {
  init(session: AVCaptureSession) {
    super.init(frame: .zero)
    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    layer.cornerRadius = 10
    layer.masksToBounds = true
    layer.backgroundColor = NSColor.black.cgColor
    if let c = layer.connection, c.isVideoMirroringSupported {  // like a mirror, so it feels natural
      c.automaticallyAdjustsVideoMirroring = false
      c.isVideoMirrored = true
    }
    self.layer = layer
    wantsLayer = true
  }
  required init?(coder: NSCoder) { fatalError() }
}
