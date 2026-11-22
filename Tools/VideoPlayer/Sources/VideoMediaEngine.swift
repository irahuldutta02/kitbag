import AppKit
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Media Types

public struct DirectoryEntry: Codable, Equatable, Sendable {
  public let name: String
  public let type: String  // "dir" | "video"
  public let path: String
  public let size: Int64?
  public let ext: String?
}

public struct DirectoryListing: Codable, Equatable, Sendable {
  public let dir: String
  public let file: String?
  public let parent: String
  public let entries: [DirectoryEntry]
}

public struct VideoTrackInfo: Codable, Equatable, Sendable {
  public let codec: String
  public let pixFmt: String?
  public let width: Int?
  public let height: Int?

  enum CodingKeys: String, CodingKey {
    case codec
    case pixFmt = "pix_fmt"
    case width
    case height
  }
}

public struct MediaTrackInfo: Codable, Equatable, Sendable {
  public let id: Int
  public let lang: String
  public let title: String
  public let codec: String
  public let channels: Int?
  public let isDefault: Bool

  enum CodingKeys: String, CodingKey {
    case id, lang, title, codec, channels
    case isDefault = "default"
  }
}

public struct ExternalSubtitle: Codable, Equatable, Sendable {
  public let name: String
  public let path: String
}

public struct ProbeResult: Codable, Equatable, Sendable {
  public let duration: Double
  public let video: VideoTrackInfo?
  public let audio: [MediaTrackInfo]
  public let subs: [MediaTrackInfo]
  public let external: [ExternalSubtitle]
}

public struct FFmpegStatus: Equatable, Sendable {
  public let ffmpegPath: String?
  public let ffprobePath: String?
  public let version: String?

  public var isReady: Bool { ffmpegPath != nil && ffprobePath != nil }
}

public enum MediaEngineError: LocalizedError {
  case notFound(String)
  case invalidFile(String)
  case ffmpegMissing
  case probeFailed(String)
  case subtitleConversionFailed(String)

  public var errorDescription: String? {
    switch self {
    case .notFound(let msg): return msg
    case .invalidFile(let msg): return msg
    case .ffmpegMissing: return "FFmpeg isn't installed. Install it from Kitbag Settings (brew install ffmpeg)."
    case .probeFailed(let msg): return msg
    case .subtitleConversionFailed(let msg): return msg
    }
  }
}

// MARK: - Media Engine

public final class VideoMediaEngine: @unchecked Sendable {
  public static let videoExtensions: Set<String> = [
    ".mkv", ".mp4", ".m4v", ".mov", ".avi", ".webm", ".ts", ".flv", ".wmv", ".mpg", ".mpeg",
  ]
  public static let imageExtensions: Set<String> = [
    ".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif", ".gif", ".tiff", ".tif", ".bmp",
  ]
  public static let subtitleExtensions: Set<String> = [
    ".srt", ".ass", ".ssa", ".vtt", ".sub",
  ]

  private let lock = NSLock()
  private var probeCache: [String: ProbeResult] = [:]
  private var wallpaperKey: String?

  public init() {}

  // MARK: - FFmpeg / FFprobe Discovery

  public static func resolveBinaries(customFFmpegPath: String = "") -> (ffmpeg: String?, ffprobe: String?) {
    let fm = FileManager.default
    var candidates: [String] = []
    let trimmed = customFFmpegPath.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
      let expanded = expandPath(trimmed)
      var isDir: ObjCBool = false
      if fm.fileExists(atPath: expanded, isDirectory: &isDir) {
        if isDir.boolValue {
          candidates.append((expanded as NSString).appendingPathComponent("ffmpeg"))
        } else {
          candidates.append(expanded)
        }
      }
    }
    candidates.append(contentsOf: [
      "/opt/homebrew/bin/ffmpeg",
      "/usr/local/bin/ffmpeg",
      "/usr/bin/ffmpeg",
    ])
    if let envPath = ProcessInfo.processInfo.environment["PATH"] {
      for dir in envPath.split(separator: ":") {
        candidates.append("\(dir)/ffmpeg")
      }
    }

    let ffmpeg = candidates.first(where: { fm.isExecutableFile(atPath: $0) })

    var probeCandidates: [String] = []
    if let ffmpeg {
      let sibling = ((ffmpeg as NSString).deletingLastPathComponent as NSString)
        .appendingPathComponent("ffprobe")
      probeCandidates.append(sibling)
    }
    probeCandidates.append(contentsOf: [
      "/opt/homebrew/bin/ffprobe",
      "/usr/local/bin/ffprobe",
      "/usr/bin/ffprobe",
    ])
    if let envPath = ProcessInfo.processInfo.environment["PATH"] {
      for dir in envPath.split(separator: ":") {
        probeCandidates.append("\(dir)/ffprobe")
      }
    }
    let ffprobe = probeCandidates.first(where: { fm.isExecutableFile(atPath: $0) })
    return (ffmpeg, ffprobe)
  }

  public static func checkFFmpeg(customFFmpegPath: String = "") -> FFmpegStatus {
    let (ffmpeg, ffprobe) = resolveBinaries(customFFmpegPath: customFFmpegPath)
    guard let ffmpeg else { return FFmpegStatus(ffmpegPath: nil, ffprobePath: ffprobe, version: nil) }
    let version = readFFmpegVersion(at: ffmpeg)
    return FFmpegStatus(ffmpegPath: ffmpeg, ffprobePath: ffprobe, version: version)
  }

  private static func readFFmpegVersion(at path: String) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = ["-version"]
    p.standardInput = FileHandle.nullDevice
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do {
      try p.run()
      p.waitUntilExit()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let firstLine = String(decoding: data, as: UTF8.self).split(separator: "\n").first.map(String.init)
      // e.g. "ffmpeg version 7.1 Copyright ..." -> "7.1"
      if let line = firstLine {
        let parts = line.split(separator: " ")
        if parts.count >= 3, parts[0] == "ffmpeg", parts[1] == "version" {
          return String(parts[2])
        }
        return line
      }
    } catch {}
    return nil
  }

  // MARK: - Path Normalization

  /// Accepts pasted paths: quotes, file:// URLs, backslash-escaped spaces, `~`, and trailing slashes.
  public static func expandPath(_ raw: String?, fallback: String? = nil) -> String {
    var p = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if p.lowercased().hasPrefix("file://"), let url = URL(string: p) {
      p = url.path
    }
    if p.count >= 2,
      (p.hasPrefix("\"") && p.hasSuffix("\"")) || (p.hasPrefix("'") && p.hasSuffix("'"))
    {
      p = String(p.dropFirst().dropLast())
    }
    // Unescape backslash-escaped characters (e.g. "My\ Movies")
    if p.contains("\\") {
      var out = ""
      var iter = p.makeIterator()
      while let c = iter.next() {
        if c == "\\", let next = iter.next() {
          out.append(next)
        } else {
          out.append(c)
        }
      }
      p = out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if p.isEmpty {
      if let fallback, !fallback.isEmpty {
        return expandPath(fallback, fallback: nil)
      }
      return home
    }
    if p == "~" { return home }
    if p.hasPrefix("~/") {
      p = (home as NSString).appendingPathComponent(String(p.dropFirst(2)))
    }
    let resolved = URL(fileURLWithPath: p).standardizedFileURL.path
    return resolved
  }

  public static func isVideoPath(_ path: String) -> Bool {
    let ext = "." + URL(fileURLWithPath: path).pathExtension.lowercased()
    return videoExtensions.contains(ext)
  }

  public static func isImagePath(_ path: String) -> Bool {
    let ext = "." + URL(fileURLWithPath: path).pathExtension.lowercased()
    return imageExtensions.contains(ext)
  }

  public static func isSubtitlePath(_ path: String) -> Bool {
    let ext = "." + URL(fileURLWithPath: path).pathExtension.lowercased()
    return subtitleExtensions.contains(ext)
  }

  // MARK: - Directory Browsing

  public static func listDirectory(_ rawPath: String?, fallback: String = "~/Movies") throws
    -> DirectoryListing
  {
    let fm = FileManager.default
    var target = expandPath(rawPath, fallback: fallback)
    var isDir: ObjCBool = false

    if !fm.fileExists(atPath: target, isDirectory: &isDir) {
      // If the default folder doesn't exist yet (e.g. fresh Mac), fall back to home if rawPath was nil
      if rawPath == nil || rawPath?.isEmpty == true {
        let home = fm.homeDirectoryForCurrentUser.path
        target = home
        isDir = true
      } else {
        throw MediaEngineError.notFound("Folder not found: \(target)")
      }
    }

    var selectedFile: String?
    var dir = target
    if !isDir.boolValue {
      selectedFile = target
      dir = URL(fileURLWithPath: target).deletingLastPathComponent().path
    }

    let dirURL = URL(fileURLWithPath: dir, isDirectory: true)
    let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .isHiddenKey]
    let contents = try fm.contentsOfDirectory(
      at: dirURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])

    var entries: [DirectoryEntry] = []
    entries.reserveCapacity(contents.count)

    for url in contents {
      let name = url.lastPathComponent
      if name.hasPrefix(".") { continue }
      let vals = try? url.resourceValues(forKeys: Set(keys))
      if vals?.isDirectory == true {
        entries.append(DirectoryEntry(name: name, type: "dir", path: url.path, size: nil, ext: nil))
      } else {
        let ext = "." + url.pathExtension.lowercased()
        if videoExtensions.contains(ext) {
          let size = Int64(vals?.fileSize ?? 0)
          entries.append(
            DirectoryEntry(
              name: name, type: "video", path: url.path, size: size,
              ext: url.pathExtension.uppercased()))
        }
      }
    }

    entries.sort { a, b in
      if a.type != b.type { return a.type == "dir" }
      return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    let parent = dir == "/" ? "/" : URL(fileURLWithPath: dir).deletingLastPathComponent().path
    return DirectoryListing(dir: dir, file: selectedFile, parent: parent, entries: entries)
  }

  // MARK: - Probing via ffprobe

  public func probe(file: String, customFFmpegPath: String = "") throws -> ProbeResult {
    let fm = FileManager.default
    guard fm.fileExists(atPath: file) else {
      throw MediaEngineError.notFound("File not found: \(file)")
    }
    let attrs = try? fm.attributesOfItem(atPath: file)
    let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    let cacheKey = "\(file):\(Int64(mtime * 1000))"

    lock.lock()
    if let cached = probeCache[cacheKey] {
      lock.unlock()
      return cached
    }
    lock.unlock()

    guard let ffprobe = Self.resolveBinaries(customFFmpegPath: customFFmpegPath).ffprobe else {
      throw MediaEngineError.ffmpegMissing
    }

    let p = Process()
    p.executableURL = URL(fileURLWithPath: ffprobe)
    p.arguments = ["-v", "error", "-print_format", "json", "-show_streams", "-show_format", file]
    p.standardInput = FileHandle.nullDevice
    let outPipe = Pipe()
    let errPipe = Pipe()
    p.standardOutput = outPipe
    p.standardError = errPipe

    do {
      try p.run()
    } catch {
      throw MediaEngineError.probeFailed("Failed to launch ffprobe: \(error.localizedDescription)")
    }

    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()

    guard p.terminationStatus == 0 else {
      let msg = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
      throw MediaEngineError.probeFailed(msg.isEmpty ? "ffprobe could not read this file." : msg)
    }

    let parsed = try Self.parseProbeJSON(outData, filePath: file)
    lock.lock()
    if probeCache.count > 128 { probeCache.removeAll() }
    probeCache[cacheKey] = parsed
    lock.unlock()
    return parsed
  }

  private struct FFProbeResponse: Decodable {
    struct Stream: Decodable {
      let codec_type: String?
      let codec_name: String?
      let pix_fmt: String?
      let width: Int?
      let height: Int?
      let channels: Int?
      let tags: [String: String]?
      let disposition: [String: Int]?
    }
    struct Format: Decodable {
      let duration: String?
    }
    let streams: [Stream]?
    let format: Format?
  }

  public static func parseProbeJSON(_ data: Data, filePath: String) throws -> ProbeResult {
    let decoded = try JSONDecoder().decode(FFProbeResponse.self, from: data)
    let streams = decoded.streams ?? []

    var audioCount = 0
    var subCount = 0
    var audio: [MediaTrackInfo] = []
    var subs: [MediaTrackInfo] = []
    var videoInfo: VideoTrackInfo?

    for s in streams {
      switch s.codec_type {
      case "video":
        if videoInfo == nil {
          videoInfo = VideoTrackInfo(
            codec: s.codec_name ?? "unknown",
            pixFmt: s.pix_fmt,
            width: s.width,
            height: s.height
          )
        }
      case "audio":
        audioCount += 1
        let tags = s.tags ?? [:]
        audio.append(
          MediaTrackInfo(
            id: audioCount,
            lang: tags["language"] ?? tags["LANGUAGE"] ?? "und",
            title: tags["title"] ?? tags["TITLE"] ?? "",
            codec: s.codec_name ?? "audio",
            channels: s.channels,
            isDefault: (s.disposition?["default"] ?? 0) != 0
          ))
      case "subtitle":
        subCount += 1
        let tags = s.tags ?? [:]
        subs.append(
          MediaTrackInfo(
            id: subCount,
            lang: tags["language"] ?? tags["LANGUAGE"] ?? "und",
            title: tags["title"] ?? tags["TITLE"] ?? "",
            codec: s.codec_name ?? "sub",
            channels: nil,
            isDefault: (s.disposition?["default"] ?? 0) != 0
          ))
      default:
        break
      }
    }

    // Sibling external subtitle files sharing the same basename prefix
    let fileURL = URL(fileURLWithPath: filePath)
    let dirURL = fileURL.deletingLastPathComponent()
    let base = fileURL.deletingPathExtension().lastPathComponent
    var external: [ExternalSubtitle] = []
    if let siblings = try? FileManager.default.contentsOfDirectory(
      at: dirURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    {
      for sib in siblings {
        let name = sib.lastPathComponent
        let ext = "." + sib.pathExtension.lowercased()
        if subtitleExtensions.contains(ext) && name.hasPrefix(base) {
          external.append(ExternalSubtitle(name: name, path: sib.path))
        }
      }
      external.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    let duration = Double(decoded.format?.duration ?? "") ?? 0
    return ProbeResult(duration: duration, video: videoInfo, audio: audio, subs: subs, external: external)
  }

  // MARK: - FFmpeg Stream Arguments

  public static func buildStreamArguments(
    file: String,
    audioTrackID: Int,
    seekTime: Double,
    quality: VideoQuality,
    probe: ProbeResult,
    hardwareAcceleration: Bool,
    copyHEVC: Bool = false
  ) -> [String] {
    let sharp = "unsharp=5:5:0.7:5:5:0.0"
    let vf: String?
    let bitrate: String
    switch quality {
    case .orig:
      vf = nil
      bitrate = "8M"
    case .enhance:
      vf = "hqdn3d=1.5:1.5:6:6,\(sharp)"
      bitrate = "12M"
    case .p1080:
      vf = "scale=-2:'max(ih,1080)':flags=lanczos,\(sharp)"
      bitrate = "14M"
    case .p1440:
      vf = "scale=-2:'max(ih,1440)':flags=lanczos,\(sharp)"
      bitrate = "22M"
    case .p2160:
      vf = "scale=-2:'max(ih,2160)':flags=lanczos,\(sharp)"
      bitrate = "40M"
    }

    let aid = max(1, audioTrackID)
    let t = max(0, seekTime)
    let copyH264 = t == 0 && probe.video?.codec == "h264" && probe.video?.pixFmt == "yuv420p"
    // The browser reported it can decode HEVC itself: remux instead of re-encoding (≈0 CPU).
    // Seeks land on a keyframe the client already snapped to via /api/keyframe.
    let copyHEVCStream = copyHEVC && probe.video?.codec == "hevc"
    let canCopy = vf == nil && (copyH264 || copyHEVCStream)

    var args: [String] = ["-nostdin", "-v", "error"]
    // Copied video can only start on a keyframe; don't trim the audio to `t` or it starts seconds late.
    if canCopy && t > 0 { args += ["-noaccurate_seek"] }
    // Hardware decode roughly halves CPU for HEVC/H.264 sources (falls back to software on its own).
    if hardwareAcceleration && !canCopy { args += ["-hwaccel", "videotoolbox"] }
    args += [
      "-ss", String(format: "%.3f", t),
      "-i", file,
      "-map", "0:v:0",
      "-map", "0:a:\(aid - 1)?",
    ]

    if canCopy {
      args += ["-c:v", "copy"]
      if copyHEVCStream { args += ["-tag:v", "hvc1", "-avoid_negative_ts", "make_zero"] }
    } else {
      if let vf {
        args += ["-vf", vf]
      }
      if hardwareAcceleration {
        args += ["-c:v", "h264_videotoolbox", "-allow_sw", "1", "-b:v", bitrate, "-pix_fmt", "yuv420p"]
      } else {
        args += ["-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p"]
      }
    }

    args += [
      "-c:a", "aac", "-b:a", "192k", "-ac", "2", "-sn",
      "-movflags", "frag_keyframe+empty_moov+default_base_moof",
      "-f", "mp4", "pipe:1",
    ]
    return args
  }

  // MARK: - Subtitles to WebVTT

  public func extractSubtitlesVTT(
    file: String?,
    subtitleID: Int?,
    externalPath: String?,
    customFFmpegPath: String = ""
  ) throws -> Data {
    guard let ffmpeg = Self.resolveBinaries(customFFmpegPath: customFFmpegPath).ffmpeg else {
      throw MediaEngineError.ffmpegMissing
    }
    let args: [String]
    if let ext = externalPath, !ext.isEmpty {
      guard FileManager.default.fileExists(atPath: ext) else {
        throw MediaEngineError.notFound("Subtitle file not found.")
      }
      args = ["-nostdin", "-v", "error", "-i", ext, "-f", "webvtt", "pipe:1"]
    } else if let file, !file.isEmpty {
      let sid = max(1, subtitleID ?? 1)
      args = ["-nostdin", "-v", "error", "-i", file, "-map", "0:s:\(sid - 1)", "-f", "webvtt", "pipe:1"]
    } else {
      throw MediaEngineError.invalidFile("Missing subtitle source.")
    }

    let p = Process()
    p.executableURL = URL(fileURLWithPath: ffmpeg)
    p.arguments = args
    p.standardInput = FileHandle.nullDevice
    let outPipe = Pipe()
    let errPipe = Pipe()
    p.standardOutput = outPipe
    p.standardError = errPipe

    do {
      try p.run()
    } catch {
      throw MediaEngineError.subtitleConversionFailed("Failed to run ffmpeg for subtitles.")
    }

    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    _ = errPipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()

    guard p.terminationStatus == 0, !outData.isEmpty else {
      throw MediaEngineError.subtitleConversionFailed(
        "Cannot convert this subtitle track (image-based subs like PGS/VobSub aren't supported).")
    }
    return outData
  }

  // MARK: - Wallpaper & Custom Background Image

  private var cacheDirectory: URL {
    let base =
      FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent("Kitbag/VideoPlayer", isDirectory: true)
  }

  // MARK: - Thumbnails

  private let thumbQueue: OperationQueue = {
    let q = OperationQueue()
    q.maxConcurrentOperationCount = 1
    q.qualityOfService = .utility
    return q
  }()

  /// Returns a small JPEG frame for a video, cached on disk. Blocks; call off the main thread.
  public func thumbnailJPEG(file: String, customFFmpegPath: String = "") -> Data? {
    let path = Self.expandPath(file)
    guard Self.isVideoPath(path), FileManager.default.fileExists(atPath: path) else { return nil }
    let attrs = try? FileManager.default.attributesOfItem(atPath: path)
    let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    let digest = Insecure.MD5.hash(data: Data("\(path):\(Int64(mtime)):\(size)".utf8))
      .prefix(8).map { String(format: "%02x", $0) }.joined()
    let dir = cacheDirectory.appendingPathComponent("thumbs", isDirectory: true)
    let dst = dir.appendingPathComponent("\(digest).jpg")
    if let cached = try? Data(contentsOf: dst), !cached.isEmpty { return cached }
    guard let ffmpeg = Self.resolveBinaries(customFFmpegPath: customFFmpegPath).ffmpeg else {
      return nil
    }
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    var result: Data?
    let sem = DispatchSemaphore(value: 0)
    thumbQueue.addOperation {
      defer { sem.signal() }
      for seek in ["60", "10", "0"] {
        let tmp = dir.appendingPathComponent("\(digest)-\(UUID().uuidString).jpg")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.arguments = [
          "-v", "error", "-y", "-hwaccel", "videotoolbox", "-ss", seek, "-i", path, "-frames:v", "1",
          "-vf", "scale=360:-2", "-q:v", "5", tmp.path,
        ]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.qualityOfService = .background
        do { try p.run() } catch { return }
        p.waitUntilExit()
        if let d = try? Data(contentsOf: tmp), !d.isEmpty {
          try? FileManager.default.moveItem(at: tmp, to: dst)
          result = d
          return
        }
        try? FileManager.default.removeItem(at: tmp)
      }
    }
    sem.wait()
    return result
  }

  /// Where a stream-copy seek to `time` really lands. ffmpeg picks its own (cued) keyframe, which can be
  /// several seconds before `time`, so ask ffmpeg itself instead of guessing from the packet list.
  public func keyframeTime(file: String, time: Double, customFFmpegPath: String = "") -> Double {
    let path = Self.expandPath(file)
    let bins = Self.resolveBinaries(customFFmpegPath: customFFmpegPath)
    guard time > 0, Self.isVideoPath(path), let ffmpeg = bins.ffmpeg, let ffprobe = bins.ffprobe else { return 0 }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("kb-kf-\(UUID().uuidString).mkv")
    defer { try? FileManager.default.removeItem(at: tmp) }

    func run(_ exe: String, _ args: [String], capture: Bool = false) -> Data? {
      let p = Process()
      p.executableURL = URL(fileURLWithPath: exe)
      p.arguments = args
      let out = Pipe()
      p.standardOutput = capture ? out : FileHandle.nullDevice
      p.standardError = FileHandle.nullDevice
      p.standardInput = FileHandle.nullDevice
      do { try p.run() } catch { return nil }
      let data = capture ? out.fileHandleForReading.readDataToEndOfFile() : nil
      p.waitUntilExit()
      return p.terminationStatus == 0 ? (data ?? Data()) : nil
    }

    guard run(ffmpeg, ["-nostdin", "-v", "error", "-y", "-noaccurate_seek", "-ss", String(format: "%.3f", time),
      "-i", path, "-map", "0:v:0", "-c:v", "copy", "-frames:v", "1", "-an", "-sn", "-copyts", "-f", "matroska", tmp.path]) != nil,
      let data = run(ffprobe, ["-v", "error", "-select_streams", "v:0", "-show_entries", "packet=pts_time",
        "-of", "csv=p=0", tmp.path], capture: true)
    else { return time }
    let pts = String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { Double($0) }
    return pts.min() ?? time
  }

  private let frameQueue: OperationQueue = {
    let q = OperationQueue()
    q.maxConcurrentOperationCount = 3
    q.qualityOfService = .userInitiated
    return q
  }()

  /// Returns a small JPEG frame at `time` (rounded to 5s buckets), cached on disk. Blocks; call off the main thread.
  public func frameJPEG(file: String, time: Double, customFFmpegPath: String = "") -> Data? {
    let path = Self.expandPath(file)
    guard Self.isVideoPath(path), FileManager.default.fileExists(atPath: path) else { return nil }
    let bucket = max(0, Int((time / 5).rounded())) * 5
    let attrs = try? FileManager.default.attributesOfItem(atPath: path)
    let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    let digest = Insecure.MD5.hash(data: Data("\(path):\(Int64(mtime)):\(size)".utf8))
      .prefix(8).map { String(format: "%02x", $0) }.joined()
    let dir = cacheDirectory.appendingPathComponent("frames", isDirectory: true)
    let dst = dir.appendingPathComponent("\(digest)-\(bucket).jpg")
    if let cached = try? Data(contentsOf: dst), !cached.isEmpty { return cached }
    guard let ffmpeg = Self.resolveBinaries(customFFmpegPath: customFFmpegPath).ffmpeg else { return nil }
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    var result: Data?
    let sem = DispatchSemaphore(value: 0)
    frameQueue.addOperation {
      defer { sem.signal() }
      let tmp = dir.appendingPathComponent("\(digest)-\(bucket)-\(UUID().uuidString).jpg")
      let p = Process()
      p.executableURL = URL(fileURLWithPath: ffmpeg)
      p.arguments = [
        "-nostdin", "-v", "error", "-y", "-ss", String(bucket), "-i", path, "-map", "0:v:0",
        "-frames:v", "1", "-vf", "scale=320:-2", "-q:v", "5", tmp.path,
      ]
      p.standardOutput = FileHandle.nullDevice
      p.standardError = FileHandle.nullDevice
      do { try p.run() } catch { return }
      p.waitUntilExit()
      if let d = try? Data(contentsOf: tmp), !d.isEmpty {
        try? FileManager.default.moveItem(at: tmp, to: dst)
        result = d
      } else {
        try? FileManager.default.removeItem(at: tmp)
      }
    }
    sem.wait()
    return result
  }

  public func desktopWallpaperJPEG() -> Data? {
    let cacheFile = cacheDirectory.appendingPathComponent("wallpaper.jpg")
    let sourceURL: URL? = {
      if Thread.isMainThread {
        return MainActor.assumeIsolated {
          (NSScreen.main ?? NSScreen.screens.first).flatMap {
            NSWorkspace.shared.desktopImageURL(for: $0)
          }
        }
      } else {
        return DispatchQueue.main.sync {
          (NSScreen.main ?? NSScreen.screens.first).flatMap {
            NSWorkspace.shared.desktopImageURL(for: $0)
          }
        }
      }
    }()

    guard let src = sourceURL, FileManager.default.fileExists(atPath: src.path) else {
      return try? Data(contentsOf: cacheFile)
    }

    let attrs = try? FileManager.default.attributesOfItem(atPath: src.path)
    let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    let key = "\(src.path):\(Int64(mtime))"

    lock.lock()
    let same = (wallpaperKey == key)
    lock.unlock()

    if same, let cached = try? Data(contentsOf: cacheFile) {
      return cached
    }

    if let jpeg = renderJPEG(from: src, maxDimension: 2560, quality: 0.82) {
      try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
      try? jpeg.write(to: cacheFile, options: .atomic)
      lock.lock()
      wallpaperKey = key
      lock.unlock()
      return jpeg
    }
    return try? Data(contentsOf: cacheFile)
  }

  public func customBackgroundJPEG(path: String) -> Data? {
    let expanded = Self.expandPath(path)
    guard Self.isImagePath(expanded), FileManager.default.fileExists(atPath: expanded) else {
      return nil
    }
    let attrs = try? FileManager.default.attributesOfItem(atPath: expanded)
    let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    let hashInput = Data("\(expanded):\(Int64(mtime))".utf8)
    let digest = Insecure.MD5.hash(data: hashInput).prefix(6).map { String(format: "%02x", $0) }
      .joined()
    let dst = cacheDirectory.appendingPathComponent("bg-\(digest).jpg")
    if let cached = try? Data(contentsOf: dst) {
      return cached
    }
    guard let jpeg = renderJPEG(from: URL(fileURLWithPath: expanded), maxDimension: 2560, quality: 0.84)
    else { return nil }
    try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    try? jpeg.write(to: dst, options: .atomic)
    return jpeg
  }

  private func renderJPEG(from url: URL, maxDimension: Int, quality: CGFloat) -> Data? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxDimension,
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else {
      return nil
    }
    let mutable = NSMutableData()
    guard
      let dest = CGImageDestinationCreateWithData(
        mutable, UTType.jpeg.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(
      dest, cgImage, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return mutable as Data
  }
}
