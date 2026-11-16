import AVFoundation
import CoreAudio

/// Records the microphone without touching any system audio setting.
///
/// Bluetooth headphones drop to low-quality "call" mode while their own microphone is in use, and
/// can stay there afterwards. So the Mac's built-in microphone is always recorded instead, and the
/// capture session is torn down completely when recording ends.
final class MicSource: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
  enum MicError: LocalizedError {
    case noMicrophone
    var errorDescription: String? { String(localized: "No microphone is available.") }
  }

  private let queue = DispatchQueue(label: "kitbag.dictation.mic")
  private var session: AVCaptureSession?
  private var handler: (@Sendable (AVAudioPCMBuffer) -> Void)?

  /// Starts delivering audio buffers on a background queue.
  func start(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
    guard let device = Self.pickDevice(), let input = try? AVCaptureDeviceInput(device: device) else {
      throw MicError.noMicrophone
    }
    let session = AVCaptureSession()
    let output = AVCaptureAudioDataOutput()
    output.audioSettings = [
      AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
      AVLinearPCMIsNonInterleaved: true, AVLinearPCMIsBigEndianKey: false,
    ]
    guard session.canAddInput(input), session.canAddOutput(output) else { throw MicError.noMicrophone }
    session.addInput(input)
    session.addOutput(output)
    handler = onBuffer
    output.setSampleBufferDelegate(self, queue: queue)
    session.startRunning()
    guard session.isRunning else {
      output.setSampleBufferDelegate(nil, queue: nil)
      handler = nil
      throw MicError.noMicrophone
    }
    self.session = session
  }

  /// Stops recording and releases the microphone.
  func stop() {
    guard let session else { return }
    self.session = nil
    session.outputs.forEach { ($0 as? AVCaptureAudioDataOutput)?.setSampleBufferDelegate(nil, queue: nil) }
    session.stopRunning()
    session.inputs.forEach { session.removeInput($0) }
    session.outputs.forEach { session.removeOutput($0) }
    handler = nil
  }

  func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
  ) {
    guard let handler, let buffer = Self.pcm(sampleBuffer) else { return }
    handler(buffer)
  }

  // MARK: Device choice

  /// The Mac's built-in microphone, whatever headphones are connected. The system's default input
  /// is never changed. Falls back to the default microphone on a Mac without a built-in one.
  private static func pickDevice() -> AVCaptureDevice? {
    let all = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
    ).devices
    return all.first(where: { $0.transportType == kAudioDeviceTransportTypeBuiltIn })
      ?? AVCaptureDevice.default(for: .audio) ?? all.first
  }

  // MARK: Sample buffer -> PCM buffer

  private static func pcm(_ sample: CMSampleBuffer) -> AVAudioPCMBuffer? {
    guard let desc = CMSampleBufferGetFormatDescription(sample) else { return nil }
    let format = AVAudioFormat(cmAudioFormatDescription: desc)
    let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
    guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
    buffer.frameLength = frames
    let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
      sample, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
    return status == noErr ? buffer : nil
  }
}
