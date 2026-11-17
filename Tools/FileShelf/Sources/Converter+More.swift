import AVFoundation
import AppKit
import CoreText
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Everything that is not an image or PDF: documents, audio, video, SVG and zip.
extension Converter {
  // MARK: Zip (any file or folder)

  static func zipItem(_ url: URL, into dir: URL) throws -> URL {
    let name = url.hasDirectoryPath || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
      ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
    let out = unique(dir, name.isEmpty ? "Archive" : name, "zip")
    try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", url.path, out.path])
    return out
  }

  // MARK: SVG

  /// Draws a vector image (SVG) with AppKit, up to 2048 px on its longer side.
  static func rasterizeVector(_ url: URL, maxSide: Int?) throws -> CGImage {
    guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else {
      throw ConvertError.unreadable
    }
    let limit = CGFloat(min(2048, maxSide ?? 2048))
    let scale = limit / max(image.size.width, image.size.height)
    let w = max(Int((image.size.width * scale).rounded()), 1)
    let h = max(Int((image.size.height * scale).rounded()), 1)
    guard
      let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw ConvertError.unreadable }
    let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gc
    image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    guard let out = ctx.makeImage() else { throw ConvertError.unreadable }
    return out
  }

  // MARK: Documents (txt, rtf, html, docx, doc, odt, webarchive)

  static func convertDocument(_ url: URL, to format: ConvertFormat, into dir: URL) throws -> URL {
    let base = url.deletingPathExtension().lastPathComponent
    let text = try readDocument(url)
    switch format {
    case .txt: return try writeText(text.string, base: base, into: dir)
    case .rtf:
      return try writeData(
        try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]),
        base: base, ext: "rtf", into: dir)
    case .html:
      return try writeData(
        try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html]),
        base: base, ext: "html", into: dir)
    case .docx:
      return try writeData(
        try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]),
        base: base, ext: "docx", into: dir)
    case .pdf:
      return try writeData(try pdfData(from: text), base: base, ext: "pdf", into: dir)
    default: throw ConvertError.unreadable
    }
  }

  private static func readDocument(_ url: URL) throws -> NSAttributedString {
    let t = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
      ?? UTType(filenameExtension: url.pathExtension)
    func isType(_ id: String) -> Bool { UTType(id).map { t?.conforms(to: $0) == true } ?? false }
    let docType: NSAttributedString.DocumentType
    if t?.conforms(to: .html) == true { docType = .html }
    else if t?.conforms(to: .rtf) == true { docType = .rtf }
    else if t?.conforms(to: .webArchive) == true { docType = .webArchive }
    else if t?.conforms(to: docxType) == true { docType = .officeOpenXML }
    else if isType("com.microsoft.word.doc") { docType = .docFormat }
    else if isType("org.oasis-open.opendocument.text") { docType = .openDocument }
    else { docType = .plain }

    if docType == .plain {
      var encoding = String.Encoding.utf8
      let s = (try? String(contentsOf: url, usedEncoding: &encoding))
        ?? (try? String(contentsOf: url, encoding: .isoLatin1))
      guard let s else { throw ConvertError.unreadable }
      return NSAttributedString(
        string: s, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black])
    }
    let load = { try NSAttributedString(url: url, options: [.documentType: docType], documentAttributes: nil) }
    do {
      // AppKit's HTML importer must run on the main thread.
      if docType == .html || docType == .webArchive, !Thread.isMainThread {
        nonisolated(unsafe) var result: Result<NSAttributedString, Error>?
        DispatchQueue.main.sync { result = Result { try load() } }
        return try result!.get()
      }
      return try load()
    } catch { throw ConvertError.unreadable }
  }

  /// Lays the text out on US Letter pages with 0.75 inch margins.
  private static func pdfData(from text: NSAttributedString) throws -> Data {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
      let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)
    else { throw ConvertError.writeFailed(String(localized: "format not supported")) }
    let setter = CTFramesetterCreateWithAttributedString(text)
    let area = CGPath(rect: box.insetBy(dx: 54, dy: 54), transform: nil)
    var location = 0
    repeat {
      ctx.beginPDFPage(nil)
      let frame = CTFramesetterCreateFrame(setter, CFRange(location: location, length: 0), area, nil)
      CTFrameDraw(frame, ctx)
      ctx.endPDFPage()
      let shown = CTFrameGetVisibleStringRange(frame).length
      if shown == 0 { break }  // nothing fits: stop instead of looping forever
      location += shown
    } while location < text.length
    ctx.closePDF()
    return data as Data
  }

  static func writeText(_ text: String, base: String, into dir: URL) throws -> URL {
    try writeData(Data(text.utf8), base: base, ext: "txt", into: dir)
  }

  private static func writeData(_ data: Data, base: String, ext: String, into dir: URL) throws -> URL {
    let out = unique(dir, base, ext)
    do { try data.write(to: out) } catch {
      throw ConvertError.writeFailed(String(localized: "disk full or folder not writable"))
    }
    return out
  }

  // MARK: Audio and video

  static func convertMedia(_ url: URL, to format: ConvertFormat, into dir: URL) throws -> URL {
    let base = url.deletingPathExtension().lastPathComponent
    let out = unique(dir, base, format.ext)
    switch format {
    case .m4a:
      try export(url, preset: AVAssetExportPresetAppleM4A, type: .m4a, to: out)
    case .mp4, .mov:
      try export(
        url, preset: AVAssetExportPresetHighestQuality, type: format == .mp4 ? .mp4 : .mov, to: out)
    case .wav, .aiff:
      var source = url
      var scratch: URL?
      defer { if let scratch { try? FileManager.default.removeItem(at: scratch) } }
      if kind(of: url) == .video {  // take the sound track first
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("kitbag-\(UUID().uuidString).m4a")
        try export(url, preset: AVAssetExportPresetAppleM4A, type: .m4a, to: tmp)
        scratch = tmp
        source = tmp
      }
      let args = format == .wav ? ["-f", "WAVE", "-d", "LEI16"] : ["-f", "AIFF", "-d", "BEI16"]
      try run("/usr/bin/afconvert", args + [source.path, out.path])
    default: throw ConvertError.unreadable
    }
    return out
  }

  private static func export(_ url: URL, preset: String, type: AVFileType, to out: URL) throws {
    let asset = AVURLAsset(url: url)
    guard let session = AVAssetExportSession(asset: asset, presetName: preset),
      session.supportedFileTypes.contains(type)
    else { throw ConvertError.unreadable }
    session.outputURL = out
    session.outputFileType = type
    let done = DispatchSemaphore(value: 0)
    session.exportAsynchronously { done.signal() }
    done.wait()
    guard session.status == .completed else {
      try? FileManager.default.removeItem(at: out)
      throw ConvertError.writeFailed(session.error?.localizedDescription ?? String(localized: "export failed"))
    }
  }

  // MARK: Helper

  /// Runs a system tool and waits. A failing exit code becomes a conversion error.
  private static func run(_ tool: String, _ args: [String]) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    let err = Pipe()
    p.standardError = err
    p.standardOutput = FileHandle.nullDevice
    do { try p.run() } catch { throw ConvertError.writeFailed(error.localizedDescription) }
    let message = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else {
      let why = String(decoding: message, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
      if let out = args.last { try? FileManager.default.removeItem(atPath: out) }
      throw ConvertError.writeFailed(why.isEmpty ? String(localized: "conversion failed") : String(why.suffix(120)))
    }
  }
}
