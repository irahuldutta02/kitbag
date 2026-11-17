import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Quartz
import UniformTypeIdentifiers

/// A format the shelf can convert to.
enum ConvertFormat: String, CaseIterable, Identifiable {
  case png, jpeg, heic, tiff, pdf
  case txt, rtf, html, docx
  case m4a, wav, aiff, mp4, mov
  case zip

  var id: String { rawValue }
  var type: UTType {
    switch self {
    case .png: return .png
    case .jpeg: return .jpeg
    case .heic: return .heic
    case .tiff: return .tiff
    case .pdf: return .pdf
    case .txt: return .plainText
    case .rtf: return .rtf
    case .html: return .html
    case .docx: return Converter.docxType
    case .m4a: return .mpeg4Audio
    case .wav: return .wav
    case .aiff: return .aiff
    case .mp4: return .mpeg4Movie
    case .mov: return .quickTimeMovie
    case .zip: return .zip
    }
  }
  var ext: String { self == .jpeg ? "jpg" : rawValue }
  var label: String { self == .jpeg ? "JPG" : rawValue.uppercased() }
  /// JPEG has no transparency: see-through areas are flattened onto white.
  var supportsAlpha: Bool { self != .jpeg }
  var isLossy: Bool { self == .jpeg || self == .heic }
  var isImage: Bool { [.png, .jpeg, .heic, .tiff].contains(self) }
  /// Whether the Compress option means anything for this target.
  var supportsCompress: Bool { isImage || self == .pdf }
  var isDocument: Bool { [.txt, .rtf, .html, .docx].contains(self) }
  var isAudio: Bool { [.m4a, .wav, .aiff].contains(self) }
  var isVideo: Bool { self == .mp4 || self == .mov }

  /// False where this Mac has no encoder (for example HEIC on very old systems).
  var canWrite: Bool {
    guard isImage else { return true }
    return (CGImageDestinationCopyTypeIdentifiers() as? [String])?.contains(type.identifier) == true
  }
}

enum ConvertError: LocalizedError {
  case unreadable, locked, empty, writeFailed(String)

  var errorDescription: String? {
    switch self {
    case .unreadable: return String(localized: "can't be read")
    case .locked: return String(localized: "is password protected")
    case .empty: return String(localized: "has no pages")
    case .writeFailed(let why): return String(localized: "couldn't be saved (\(why))")
    }
  }
}

/// How hard to compress. Lossy formats get lower quality; every image is also limited in size.
enum CompressLevel: String, CaseIterable, Identifiable {
  case light, medium, strong

  var id: String { rawValue }
  var label: String {
    switch self {
    case .light: return String(localized: "Light")
    case .medium: return String(localized: "Medium")
    case .strong: return String(localized: "Strong")
    }
  }
  /// JPG and HEIC quality.
  var quality: Double { [CompressLevel.light: 0.8, .medium: 0.6, .strong: 0.4][self]! }
  /// Longest side in pixels; bigger images are scaled down to this.
  var maxSide: Int { [CompressLevel.light: 3200, .medium: 2400, .strong: 1600][self]! }
  /// How many colors a PNG keeps.
  var colors: Int { [CompressLevel.light: 256, .medium: 128, .strong: 64][self]! }
}

/// What to do on top of converting.
struct ConvertOptions {
  var quality = 0.85  // JPG and HEIC when not compressing
  var compress: CompressLevel?
  var stripMetadata = false
  var effectiveQuality: Double { compress?.quality ?? quality }
}

/// Converts images and PDFs. Pure functions of files in and files out, with no UI or shelf state.
enum Converter {
  /// `other` is anything with no format of its own to convert to (folders, apps, archives, unknown
  /// types): those can still be zipped.
  enum Kind { case image, pdf, document, audio, video, other }

  static let docxType = UTType("org.openxmlformats.wordprocessingml.document") ?? .data
  private static let documentTypes: [UTType] = [
    .text, .rtf, .html, .webArchive, docxType,
    UTType("com.microsoft.word.doc"), UTType("org.oasis-open.opendocument.text"),
  ].compactMap { $0 }

  static func kind(of url: URL) -> Kind {
    let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
    if values?.isDirectory == true { return .other }
    let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
    guard let type else { return .other }
    if type.conforms(to: .pdf) { return .pdf }
    if type.conforms(to: .image) { return .image }  // SVG included: it is drawn by AppKit
    if type.conforms(to: .audio) { return .audio }
    if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
    if documentTypes.contains(where: { type.conforms(to: $0) }) { return .document }
    return .other
  }

  /// Whether `url` is worth converting to `format`: a different format that this kind of file can become.
  static func canConvert(_ url: URL, to format: ConvertFormat) -> Bool {
    if format == .zip { return !sameType(url, format) }  // anything can be zipped
    let k = kind(of: url)
    let reachable: Bool
    switch k {
    case .image: reachable = format.isImage || format == .pdf
    case .pdf: reachable = format.isImage || format == .txt
    case .document: reachable = format.isDocument || format == .pdf
    case .audio: reachable = format.isAudio
    case .video: reachable = format.isVideo || format.isAudio
    case .other: reachable = false
    }
    return reachable && (k == .pdf || !sameType(url, format))
  }

  private static func sameType(_ url: URL, _ format: ConvertFormat) -> Bool {
    let t = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
      ?? UTType(filenameExtension: url.pathExtension)
    return t?.conforms(to: format.type) == true
  }

  /// Formats at least one of the files can be converted to, in a stable order.
  static func formats(for urls: [URL]) -> [ConvertFormat] {
    ConvertFormat.allCases.filter { f in f.canWrite && urls.contains { canConvert($0, to: f) } }
  }

  static func isMergeable(_ url: URL) -> Bool { [.image, .pdf].contains(kind(of: url)) }
  static func mergeable(_ urls: [URL]) -> [URL] { urls.filter(isMergeable) }

  // MARK: Converting

  /// Converts one file and returns what was written: one file, or one per page for a PDF.
  /// Output names are `<name>.<ext>` inside `dir`, made unique so nothing is overwritten.
  /// `stripMetadata` leaves out camera, date and location info (EXIF/GPS/IPTC) from image results.
  static func convert(
    _ url: URL, to format: ConvertFormat, quality: Double, stripMetadata: Bool = false, into dir: URL
  ) throws -> [URL] {
    try convert(
      url, to: format, options: ConvertOptions(quality: quality, stripMetadata: stripMetadata), into: dir)
  }

  static func convert(
    _ url: URL, to format: ConvertFormat, options: ConvertOptions, into dir: URL
  ) throws -> [URL] {
    let quality = options.effectiveQuality
    let stripMetadata = options.stripMetadata
    let base = url.deletingPathExtension().lastPathComponent
    if format == .zip { return [try zipItem(url, into: dir)] }
    switch kind(of: url) {
    case .image:
      if format == .pdf {
        let doc = PDFDocument()
        try appendImage(url, to: doc, maxSide: options.compress?.maxSide)
        return [try write(doc, base: base, into: dir)]
      }
      let image = try loadImage(url, maxSide: options.compress?.maxSide)
      let out = unique(dir, base, format.ext)
      try encode(
        image, as: format, quality: quality, metadata: stripMetadata ? [:] : metadata(of: url),
        compress: options.compress, to: out)
      return [out]
    case .pdf:
      guard let doc = PDFDocument(url: url) else { throw ConvertError.unreadable }
      if doc.isLocked { throw ConvertError.locked }
      guard doc.pageCount > 0 else { throw ConvertError.empty }
      if format == .txt {
        let text = doc.string ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConvertError.empty }
        return [try writeText(text, base: base, into: dir)]
      }
      var outs: [URL] = []
      // Many pages go into their own folder, so they don't flood the destination.
      var target = dir
      if doc.pageCount > 1 {
        target = uniqueFolder(dir, "\(base) pages")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
      }
      for i in 0..<doc.pageCount {
        guard let page = doc.page(at: i) else { continue }
        let name = doc.pageCount == 1 ? base : "\(base) – page \(i + 1)"
        let out = unique(target, name, format.ext)
        try encode(try render(page, maxSide: options.compress?.maxSide), as: format, quality: quality, metadata: [:], compress: options.compress, to: out)
        outs.append(out)
      }
      return outs
    case .document: return [try convertDocument(url, to: format, into: dir)]
    case .audio, .video: return [try convertMedia(url, to: format, into: dir)]
    case .other: throw ConvertError.unreadable
    }
  }

  /// Joins images and PDFs, in the given order, into one PDF. Files that can't be read are skipped
  /// and reported in `skipped`.
  static func merge(_ urls: [URL], into dir: URL) throws -> (output: URL, skipped: [String]) {
    let doc = PDFDocument()
    var skipped: [String] = []
    for url in urls {
      do {
        switch kind(of: url) {
        case .image: try appendImage(url, to: doc)
        case .pdf:
          guard let src = PDFDocument(url: url) else { throw ConvertError.unreadable }
          if src.isLocked { throw ConvertError.locked }
          for i in 0..<src.pageCount { if let p = src.page(at: i)?.copy() as? PDFPage { doc.insert(p, at: doc.pageCount) } }
        default: continue
        }
      } catch { skipped.append(url.lastPathComponent) }
    }
    guard doc.pageCount > 0 else { throw ConvertError.empty }
    return (try write(doc, base: mergedName(urls), into: dir), skipped)
  }

  // MARK: Compress and clean, keeping the format

  /// The format a file already has, when it can be written again (so it can be compressed or cleaned).
  static func sameFormat(of url: URL) -> ConvertFormat? {
    switch kind(of: url) {
    case .pdf: return .pdf
    case .image: return [ConvertFormat.png, .jpeg, .heic, .tiff].first { $0.canWrite && sameType(url, $0) }
    default: return nil
    }
  }

  /// Rewrites a file in its own format: smaller (`compress`), without hidden data (`stripMetadata`), or both.
  /// Removing hidden data alone leaves the pixels untouched.
  static func optimize(
    _ url: URL, options: ConvertOptions, suffix: String, into dir: URL
  ) throws -> URL {
    guard let format = sameFormat(of: url) else { throw ConvertError.unreadable }
    let base = url.deletingPathExtension().lastPathComponent + suffix
    let ext = url.pathExtension.isEmpty ? format.ext : url.pathExtension
    let out = unique(dir, base, ext)

    if format == .pdf {
      guard let src = PDFDocument(url: url) else { throw ConvertError.unreadable }
      if src.isLocked { throw ConvertError.locked }
      var doc = src
      if options.stripMetadata {  // a fresh document carries none of the old title, author or keywords
        doc = PDFDocument()
        for i in 0..<src.pageCount { if let p = src.page(at: i)?.copy() as? PDFPage { doc.insert(p, at: doc.pageCount) } }
      }
      var writeOptions: [PDFDocumentWriteOption: Any] = [:]
      if options.compress != nil,
        let filter = QuartzFilter(url: URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter"))
      {
        writeOptions[PDFDocumentWriteOption(rawValue: "QuartzFilter")] = filter
      }
      guard doc.write(to: out, withOptions: writeOptions) else {
        throw ConvertError.writeFailed(String(localized: "disk full or folder not writable"))
      }
      return out
    }

    if options.compress == nil {
      try copyWithoutMetadata(url, as: format, to: out, quality: options.effectiveQuality)
    } else {
      let image = try loadImage(url, maxSide: options.compress?.maxSide)
      try encode(
        image, as: format, quality: options.effectiveQuality,
        metadata: options.stripMetadata ? [:] : metadata(of: url), compress: options.compress, to: out)
    }
    return out
  }

  /// Copies the image data as it is and writes no EXIF, GPS, XMP or IPTC (only the rotation is kept,
  /// so the picture still shows the right way up). Falls back to re-encoding if the format can't.
  private static func copyWithoutMetadata(_ url: URL, as format: ConvertFormat, to out: URL, quality: Double) throws {
    if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
      let dest = CGImageDestinationCreateWithURL(out as CFURL, format.type.identifier as CFString, 1, nil)
    {
      let md = CGImageMetadataCreateMutable()
      let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
      if let o = props?[kCGImagePropertyOrientation] as? Int, o != 1,
        let tag = CGImageMetadataTagCreate(
          kCGImageMetadataNamespaceTIFF, kCGImageMetadataPrefixTIFF, "Orientation" as CFString, .default, o as CFNumber)
      {
        CGImageMetadataSetTagWithPath(md, nil, "tiff:Orientation" as CFString, tag)
      }
      let opts: [CFString: Any] = [
        kCGImageDestinationMetadata: md, kCGImageMetadataShouldExcludeGPS: true,
        kCGImageMetadataShouldExcludeXMP: true,
      ]
      if CGImageDestinationCopyImageSource(dest, src, opts as CFDictionary, nil) { return }
      try? FileManager.default.removeItem(at: out)
    }
    try encode(try loadImage(url), as: format, quality: max(quality, 0.92), metadata: [:], to: out)
  }

  // MARK: Helpers

  /// "a + b" for two files, "a + 3 more" for more.
  static func mergedName(_ urls: [URL]) -> String {
    func short(_ u: URL) -> String { String(u.deletingPathExtension().lastPathComponent.prefix(40)) }
    guard let first = urls.first else { return String(localized: "Merged") }
    if urls.count == 1 { return short(first) }
    if urls.count == 2 { return "\(short(first)) + \(short(urls[1]))" }
    return String(localized: "\(short(first)) + \(urls.count - 1) more")
  }

  /// Camera, date, location and keyword info worth carrying over. Orientation and pixel size are
  /// left out because the pixels are already rotated and re-measured.
  static func metadata(of url: URL) -> [CFString: Any] {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
      let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
    else { return [:] }
    var out: [CFString: Any] = [:]
    for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary,
      kCGImagePropertyIPTCDictionary, kCGImagePropertyTIFFDictionary]
    {
      guard var d = props[key] as? [CFString: Any] else { continue }
      d[kCGImagePropertyTIFFOrientation] = nil
      d[kCGImagePropertyExifPixelXDimension] = nil
      d[kCGImagePropertyExifPixelYDimension] = nil
      if !d.isEmpty { out[key] = d }
    }
    return out
  }

  /// True if converting this file to an image format can carry metadata (so the choice matters).
  static func hasMetadata(_ url: URL) -> Bool {
    kind(of: url) == .image && !metadata(of: url).isEmpty
  }

  /// The image with its rotation applied, at full size.
  static func loadImage(_ url: URL, maxSide: Int? = nil) throws -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0 else {
      return try rasterizeVector(url, maxSide: maxSide)  // SVG and other drawn-by-AppKit images
    }
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
    let w = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
    let h = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,  // apply EXIF orientation
      kCGImageSourceThumbnailMaxPixelSize: min(max(w, h, 1), maxSide ?? Int.max),
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
      throw ConvertError.unreadable
    }
    return image
  }

  private static func hasAlpha(_ image: CGImage) -> Bool {
    switch image.alphaInfo {
    case .none, .noneSkipFirst, .noneSkipLast: return false
    default: return true
    }
  }

  private static func flattened(_ image: CGImage) throws -> CGImage {
    guard hasAlpha(image),
      let ctx = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return image }
    let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(rect)
    ctx.draw(image, in: rect)
    return ctx.makeImage() ?? image
  }

  private static func encode(
    _ image: CGImage, as format: ConvertFormat, quality: Double, metadata: [CFString: Any],
    compress: CompressLevel? = nil, to url: URL
  ) throws {
    // PNG is lossless, so it only gets smaller by using fewer colors.
    if format == .png, let level = compress {
      do { return try PNGQuantizer.write(image, colors: level.colors, to: url) } catch {}
    }
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, format.type.identifier as CFString, 1, nil) else {
      throw ConvertError.writeFailed(String(localized: "format not supported"))
    }
    var props: [CFString: Any] = metadata
    if format == .tiff, compress != nil {  // lossless LZW
      var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
      tiff[kCGImagePropertyTIFFCompression] = 5
      props[kCGImagePropertyTIFFDictionary] = tiff
    }
    if format.isLossy { props[kCGImageDestinationLossyCompressionQuality] = min(max(quality, 0.05), 1) }
    CGImageDestinationAddImage(dest, format.supportsAlpha ? image : try flattened(image), props as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
      try? FileManager.default.removeItem(at: url)
      throw ConvertError.writeFailed(String(localized: "disk full or folder not writable"))
    }
  }

  /// A PDF page as a bitmap, about 150 dpi and never more than 6000 px on a side.
  private static func render(_ page: PDFPage, maxSide: Int? = nil) throws -> CGImage {
    let box = page.bounds(for: .mediaBox)
    let scale = min(150.0 / 72.0, Double(min(6000, maxSide ?? 6000)) / max(box.width, box.height, 1))
    let size = NSSize(width: max(box.width * scale, 1), height: max(box.height * scale, 1))
    var rect = CGRect(origin: .zero, size: size)
    guard let cg = page.thumbnail(of: size, for: .mediaBox).cgImage(forProposedRect: &rect, context: nil, hints: nil)
    else { throw ConvertError.unreadable }
    return cg
  }

  private static func appendImage(_ url: URL, to doc: PDFDocument, maxSide: Int? = nil) throws {
    let image = try loadImage(url, maxSide: maxSide)
    // Page size: the image's own size, but no bigger than ~1000 pt so pages open at a sane size.
    let ratio = min(1, 1000 / CGFloat(max(image.width, image.height, 1)))
    let size = NSSize(width: CGFloat(image.width) * ratio, height: CGFloat(image.height) * ratio)
    guard let page = PDFPage(image: NSImage(cgImage: image, size: size)) else { throw ConvertError.unreadable }
    doc.insert(page, at: doc.pageCount)
  }

  static func write(_ doc: PDFDocument, base: String, into dir: URL) throws -> URL {
    let out = unique(dir, base, "pdf")
    guard doc.write(to: out) else {
      throw ConvertError.writeFailed(String(localized: "disk full or folder not writable"))
    }
    return out
  }

  static func uniqueFolder(_ dir: URL, _ name: String) -> URL {
    var url = dir.appendingPathComponent(name, isDirectory: true)
    var n = 2
    while FileManager.default.fileExists(atPath: url.path) {
      url = dir.appendingPathComponent("\(name) \(n)", isDirectory: true)
      n += 1
    }
    return url
  }

  /// `name.ext`, or `name 2.ext`, `name 3.ext`… when that already exists.
  static func unique(_ dir: URL, _ base: String, _ ext: String) -> URL {
    let fm = FileManager.default
    var url = dir.appendingPathComponent(base).appendingPathExtension(ext)
    var n = 2
    while fm.fileExists(atPath: url.path) {
      url = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
      n += 1
    }
    return url
  }
}
