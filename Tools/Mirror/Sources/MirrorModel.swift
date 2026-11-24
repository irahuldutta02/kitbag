@preconcurrency import AVFoundation
import AppKit
import SwiftUI

/// Runs the camera for the Mirror window. The camera is on only while the window is open.
@MainActor
final class MirrorModel: ObservableObject {
  enum State: Equatable { case idle, starting, running, denied, noCamera, failed }

  @Published private(set) var state: State = .idle
  @Published var flipped = true  // a mirror shows you reversed, like a real one

  let session = AVCaptureSession()
  private let queue = DispatchQueue(label: "kitbag.mirror.session")
  private var configured = false

  static func openCameraSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
      NSWorkspace.shared.open(url)
    }
  }

  func start() {
    guard state != .running, state != .starting else { return }
    state = .starting
    Task {
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized: break
      case .notDetermined:
        guard await AVCaptureDevice.requestAccess(for: .video) else { return state = .denied }
      default: return state = .denied
      }
      guard let device = AVCaptureDevice.default(for: .video)
        ?? AVCaptureDevice.DiscoverySession(
          deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified
        ).devices.first
      else { return state = .noCamera }

      if !configured {
        session.beginConfiguration()
        session.sessionPreset = .high
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
          session.commitConfiguration()
          return state = .failed
        }
        session.addInput(input)
        session.commitConfiguration()
        configured = true
      }
      let s = session
      queue.async { s.startRunning() }
      state = .running
    }
  }

  func stop() {
    let s = session
    queue.async { if s.isRunning { s.stopRunning() } }
    if state != .denied && state != .noCamera && state != .failed { state = .idle }
  }
}
