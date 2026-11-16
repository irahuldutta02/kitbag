import AppKit
import CoreImage
import ImageIO
import KitbagCore

/// Reads QR codes: from a region of the screen you drag over (macOS's own snipping tool), from an
/// image file, or from an image on the clipboard. Everything stays on this Mac.
@MainActor
enum QRScanner {
  enum Outcome {
    case found([String])
    case none
    case cancelled
    case failed(String)
  }

  /// Shows macOS's crosshair snipping tool. Esc cancels.
  static func snipScreen() async -> Outcome {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kitbag-qr-\(UUID().uuidString)")
    do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
    catch { return .failed("Couldn't prepare a temporary folder.") }
    defer { try? FileManager.default.removeItem(at: dir) }  // never leave a screenshot of your secrets behind
    let file = dir.appendingPathComponent("snip.png")
    guard let result = await Shell.run("/usr/sbin/screencapture", ["-i", "-s", "-x", file.path]) else {
      return .failed("macOS's screenshot tool couldn't be started.")
    }
    guard FileManager.default.fileExists(atPath: file.path) else {
      return result.ok ? .cancelled : .failed(result.output.isEmpty ? "The screenshot failed." : result.output)
    }
    let found = messages(inFile: file)
    return found.isEmpty ? .none : .found(found)
  }

  static func messages(inFile url: URL) -> [String] {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { return [] }
    return messages(in: image)
  }

  static func messages(inPasteboard pb: NSPasteboard = .general) -> [String] {
    for type in [NSPasteboard.PasteboardType.png, .tiff] {
      if let data = pb.data(forType: type), let src = CGImageSourceCreateWithData(data as CFData, nil),
        let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
      {
        return messages(in: image)
      }
    }
    return []
  }

  /// Tries the picture as it is, then enlarged (small codes), then inverted (light-on-dark codes).
  static func messages(in image: CGImage) -> [String] {
    guard
      let detector = CIDetector(
        ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
    else { return [] }
    let base = CIImage(cgImage: image)
    var attempts = [base, base.transformed(by: CGAffineTransform(scaleX: 2, y: 2))]
    if let inverted = CIFilter(name: "CIColorInvert", parameters: [kCIInputImageKey: base])?.outputImage {
      attempts.append(inverted)
    }
    for candidate in attempts {
      let found = detector.features(in: candidate).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
      if !found.isEmpty { return found }
    }
    return []
  }
}
