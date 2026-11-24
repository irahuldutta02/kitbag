@preconcurrency import AVFoundation
import KitbagCore
import SwiftUI

/// The camera picture, filled into a fixed 4:3 frame so the window never changes size.
private struct CameraPreview: NSViewRepresentable {
  let session: AVCaptureSession
  let flipped: Bool

  func makeNSView(context: Context) -> PreviewHost {
    let v = PreviewHost()
    v.previewLayer.session = session
    v.previewLayer.videoGravity = .resizeAspectFill
    return v
  }

  func updateNSView(_ v: PreviewHost, context: Context) {
    if let c = v.previewLayer.connection, c.isVideoMirroringSupported {
      c.automaticallyAdjustsVideoMirroring = false
      c.isVideoMirrored = flipped
    }
  }

  final class PreviewHost: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    override init(frame: NSRect) {
      super.init(frame: frame)
      wantsLayer = true
      layer = previewLayer
    }
    required init?(coder: NSCoder) { fatalError() }
  }
}

struct MirrorView: View {
  @ObservedObject var model: MirrorModel

  var body: some View {
    VStack(spacing: 10) {
      ZStack {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.35))
        if model.state == .running || model.state == .starting {
          CameraPreview(session: model.session, flipped: model.flipped)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        overlay
      }
      .frame(width: 300, height: 225)
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))

      HStack {
        Toggle(isOn: $model.flipped) {
          Label("Flip like a mirror", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            .font(.caption)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        Spacer()
        Text(model.state == .running ? "Camera on" : "Camera off")
          .font(.caption)
          .foregroundStyle(model.state == .running ? KitbagUI.success : .secondary)
      }
      .frame(height: 20)
    }
    .onAppear { model.start() }
    .onDisappear { model.stop() }
  }

  @ViewBuilder private var overlay: some View {
    switch model.state {
    case .idle, .starting:
      ProgressView().controlSize(.small)
    case .running:
      EmptyView()
    case .denied:
      message(
        "Camera access is off", "Allow Kitbag in System Settings ▸ Privacy & Security ▸ Camera.",
        action: ("Open Settings", { MirrorModel.openCameraSettings() }))
    case .noCamera:
      message("No camera found", "Connect a camera and open Mirror again.", action: nil)
    case .failed:
      message("Camera couldn't start", "Another app may be using it.", action: ("Try Again", { model.start() }))
    }
  }

  private func message(_ title: LocalizedStringKey, _ detail: LocalizedStringKey, action: (String, () -> Void)?)
    -> some View
  {
    VStack(spacing: 6) {
      Image(systemName: "video.slash").font(.system(size: 22, weight: .light)).foregroundStyle(.secondary)
      Text(title).font(.callout.weight(.semibold))
      Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
      if let action {
        Button(action.0, action: action.1).controlSize(.small).buttonStyle(.borderedProminent)
      }
    }
    .padding(16)
  }
}
