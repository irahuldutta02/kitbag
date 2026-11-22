import Foundation
import Testing

@testable import VideoPlayer

@Suite(.serialized)
final class VideoPlayerTests {
  private func makeDefaults() -> UserDefaults {
    UserDefaults(suiteName: "kitbag.videoplayer.tests.\(UUID().uuidString)")!
  }

  // MARK: - Path Expansion

  @Test func expandPathHandlesCommonUserInputs() {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    #expect(VideoMediaEngine.expandPath("~") == home)
    #expect(VideoMediaEngine.expandPath("~/Movies") == "\(home)/Movies")
    #expect(VideoMediaEngine.expandPath("\"~/Movies\"") == "\(home)/Movies")
    #expect(VideoMediaEngine.expandPath("'~/Movies'") == "\(home)/Movies")
    #expect(VideoMediaEngine.expandPath("/tmp/My\\ Video\\ File.mkv") == "/tmp/My Video File.mkv")
    #expect(VideoMediaEngine.expandPath("file:///tmp/hello%20world.mp4") == "/tmp/hello world.mp4")
    #expect(VideoMediaEngine.expandPath("", fallback: "~/Downloads") == "\(home)/Downloads")
  }

  // MARK: - Directory Listing

  @Test func listDirectoryFiltersAndSortsFoldersBeforeVideos() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("kitbag-vp-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Season 2"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Season 10"), withIntermediateDirectories: true)
    try Data("a".utf8).write(to: root.appendingPathComponent("Episode 10.mkv"))
    try Data("ab".utf8).write(to: root.appendingPathComponent("Episode 2.mp4"))
    try Data("txt".utf8).write(to: root.appendingPathComponent("notes.txt"))
    try Data("hidden".utf8).write(to: root.appendingPathComponent(".secret.mp4"))

    let listing = try VideoMediaEngine.listDirectory(root.path)
    #expect(listing.file == nil)
    #expect(listing.entries.map(\.name) == ["Season 2", "Season 10", "Episode 2.mp4", "Episode 10.mkv"])
    #expect(listing.entries.map(\.type) == ["dir", "dir", "video", "video"])
    #expect(listing.entries[2].ext == "MP4")
    #expect(listing.entries[3].ext == "MKV")

    // Passing a file path selects it and lists its containing folder
    let fileListing = try VideoMediaEngine.listDirectory(root.appendingPathComponent("Episode 2.mp4").path)
    #expect(fileListing.dir == listing.dir)
    #expect(fileListing.file == root.appendingPathComponent("Episode 2.mp4").standardizedFileURL.path)
  }

  // MARK: - Probe JSON & Sibling Subtitles

  @Test func parseProbeJSONExtractsTracksAndSiblingSubtitles() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("kitbag-probe-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let videoFile = dir.appendingPathComponent("Movie.mkv")
    try Data().write(to: videoFile)
    try Data().write(to: dir.appendingPathComponent("Movie.en.srt"))
    try Data().write(to: dir.appendingPathComponent("Other.srt"))

    let sampleJSON = """
    {
      "format": { "duration": "3725.5" },
      "streams": [
        { "codec_type": "video", "codec_name": "hevc", "pix_fmt": "yuv420p10le", "width": 3840, "height": 2160 },
        { "codec_type": "audio", "codec_name": "eac3", "channels": 6, "tags": { "language": "eng", "title": "English 5.1" }, "disposition": { "default": 1 } },
        { "codec_type": "audio", "codec_name": "aac", "channels": 2, "tags": { "language": "jpn" }, "disposition": { "default": 0 } },
        { "codec_type": "subtitle", "codec_name": "subrip", "tags": { "language": "eng", "title": "Full" }, "disposition": { "default": 1 } }
      ]
    }
    """

    let result = try VideoMediaEngine.parseProbeJSON(Data(sampleJSON.utf8), filePath: videoFile.path)
    #expect(result.duration == 3725.5)
    #expect(result.video?.codec == "hevc")
    #expect(result.video?.width == 3840)
    #expect(result.video?.height == 2160)
    #expect(result.audio.count == 2)
    #expect(result.audio[0].id == 1)
    #expect(result.audio[0].isDefault == true)
    #expect(result.audio[1].id == 2)
    #expect(result.audio[1].lang == "jpn")
    #expect(result.subs.count == 1)
    #expect(result.subs[0].codec == "subrip")
    #expect(result.external.map(\.name) == ["Movie.en.srt"])
  }

  // MARK: - FFmpeg Stream Arguments

  @Test func streamArgsCopyOnlyWhenH264AtZeroOriginalQuality() {
    let h264Probe = ProbeResult(
      duration: 600,
      video: VideoTrackInfo(codec: "h264", pixFmt: "yuv420p", width: 1920, height: 1080),
      audio: [], subs: [], external: [])

    let copyArgs = VideoMediaEngine.buildStreamArguments(
      file: "/tmp/a.mp4", audioTrackID: 2, seekTime: 0, quality: .orig, probe: h264Probe,
      hardwareAcceleration: true)
    #expect(copyArgs.contains("copy"))
    #expect(copyArgs.contains("0:a:1?"))
    #expect(!copyArgs.contains("h264_videotoolbox"))

    // Seeking forces transcode for frame accuracy
    let seekArgs = VideoMediaEngine.buildStreamArguments(
      file: "/tmp/a.mp4", audioTrackID: 1, seekTime: 45, quality: .orig, probe: h264Probe,
      hardwareAcceleration: true)
    #expect(!seekArgs.contains("copy"))
    #expect(seekArgs.contains("h264_videotoolbox"))
    #expect(seekArgs.contains("-allow_sw"))

    // Upscale includes scale filter and bitrate
    let upscaleArgs = VideoMediaEngine.buildStreamArguments(
      file: "/tmp/a.mp4", audioTrackID: 1, seekTime: 0, quality: .p2160, probe: h264Probe,
      hardwareAcceleration: true)
    #expect(upscaleArgs.contains("-vf"))
    #expect(upscaleArgs.contains("40M"))

    // Software fallback when hardware acceleration is off
    let swArgs = VideoMediaEngine.buildStreamArguments(
      file: "/tmp/a.mp4", audioTrackID: 1, seekTime: 10, quality: .orig, probe: h264Probe,
      hardwareAcceleration: false)
    #expect(swArgs.contains("libx264"))
    #expect(!swArgs.contains("h264_videotoolbox"))
  }

  // MARK: - Settings Persistence & Sync

  @MainActor
  @Test func settingsPersistAndBumpVersionOnPatch() {
    let defaults = makeDefaults()
    let s1 = VideoPlayerSettings(defaults: defaults)
    let v0 = s1.configVersion

    s1.browserBundleID = "com.google.Chrome"
    s1.defaultQuality = .p1080
    s1.skipSeconds = 15
    s1.port = 8088
    s1.theme = .light
    s1.recordProgress(path: "/tmp/demo.mkv", position: 120, duration: 600)

    #expect(s1.configVersion > v0)
    #expect(s1.recents.count == 1)
    #expect(s1.recents[0].canResume == true)

    let s2 = VideoPlayerSettings(defaults: defaults)
    #expect(s2.browserBundleID == "com.google.Chrome")
    #expect(s2.defaultQuality == .p1080)
    #expect(s2.skipSeconds == 15)
    #expect(s2.port == 8088)
    #expect(s2.theme == .light)
    #expect(s2.recents.count == 1)
    #expect(s2.recents[0].position == 120)

    // Patch from web UI updates settings & bumps configVersion
    let vBeforePatch = s2.configVersion
    s2.apply(patch: WebConfigPatch(glassStyle: "tinted", glassBlur: 44, backgroundPreset: "aurora"))
    #expect(s2.glassStyle == .tinted)
    #expect(s2.glassBlur == 44)
    #expect(s2.backgroundPreset == .aurora)
    #expect(s2.configVersion == vBeforePatch + 1)
  }

  // MARK: - End-to-End Local HTTP Server

  private final class MockDelegate: LocalVideoServerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    var config = VideoPlayerConfigSnapshot(
      configVersion: 1,
      defaultFolder: "/tmp",
      defaultQuality: "orig",
      defaultSpeed: 1.0,
      skipSeconds: 10,
      preferredAudioLanguage: "default",
      subtitleBehavior: "auto",
      rememberPosition: true,
      hardwareAcceleration: true,
      theme: "dark",
      glassStyle: "clear",
      glassTransparency: 42,
      glassBlur: 28,
      backgroundDimming: 42,
      backgroundPreset: "aurora",
      customBackgroundPath: "",
      subtitleSize: "medium",
      subtitleStyle: "pill",
      port: 0,
      serverMode: "alwaysOn",
      customFFmpegPath: ""
    )
    var recents: [RecentVideo] = []
    var latestStats: ServerStats = .stopped

    func serverConfigSnapshot() -> VideoPlayerConfigSnapshot {
      lock.lock(); defer { lock.unlock() }; return config
    }

    func serverApplyConfigPatch(_ patch: WebConfigPatch) -> VideoPlayerConfigSnapshot {
      lock.lock(); defer { lock.unlock() }
      if let b = patch.glassBlur { config.glassBlur = b }
      if let t = patch.theme { config.theme = t }
      config.configVersion += 1
      return config
    }

    func serverRecents() -> [RecentVideo] {
      lock.lock(); defer { lock.unlock() }; return recents
    }

    func serverRecordProgress(path: String, position: Double, duration: Double) {
      lock.lock()
      recents = [RecentVideo(path: path, name: URL(fileURLWithPath: path).lastPathComponent, position: position, duration: duration)]
      lock.unlock()
    }

    func serverPickFile(kind: String) async -> String? { nil }
    func serverStatsChanged(_ stats: ServerStats) {
      lock.lock(); latestStats = stats; lock.unlock()
    }
    func serverDidAutoStop() {}
  }

  @Test func localHTTPServerServesUIAndEndpoints() async throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("kitbag-srv-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data("vid".utf8).write(to: dir.appendingPathComponent("Sample.mp4"))

    let delegate = MockDelegate()
    let server = LocalHTTPServer(engine: VideoMediaEngine(), delegate: delegate)
    let port = try await server.start(port: 0)
    defer { server.stop() }
    #expect(port > 0)

    let base = "http://127.0.0.1:\(port)"
    let session = URLSession(configuration: .ephemeral)

    // 1. HTML index
    let (htmlData, htmlRes) = try await session.data(from: URL(string: "\(base)/")!)
    let htmlHTTP = try #require(htmlRes as? HTTPURLResponse)
    #expect(htmlHTTP.statusCode == 200)
    #expect(String(decoding: htmlData, as: UTF8.self).contains("Kitbag Video Player"))

    // 2. Favicon SVG
    let (svgData, svgRes) = try await session.data(from: URL(string: "\(base)/assets/favicon.svg")!)
    #expect((svgRes as? HTTPURLResponse)?.statusCode == 200)
    #expect(String(decoding: svgData, as: UTF8.self).contains("<svg"))

    // 3. GET & POST /api/config
    let (cfgData, _) = try await session.data(from: URL(string: "\(base)/api/config")!)
    let cfg = try JSONDecoder().decode(VideoPlayerConfigSnapshot.self, from: cfgData)
    #expect(cfg.configVersion == 1)
    #expect(cfg.theme == "dark")

    var postReq = URLRequest(url: URL(string: "\(base)/api/config")!)
    postReq.httpMethod = "POST"
    postReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
    postReq.httpBody = Data(#"{"theme":"light","glassBlur":40}"#.utf8)
    let (postData, postRes) = try await session.data(for: postReq)
    #expect((postRes as? HTTPURLResponse)?.statusCode == 200)
    let updatedCfg = try JSONDecoder().decode(VideoPlayerConfigSnapshot.self, from: postData)
    #expect(updatedCfg.theme == "light")
    #expect(updatedCfg.glassBlur == 40)
    #expect(updatedCfg.configVersion == 2)

    // 4. Directory listing
    let encodedDir = dir.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
    let (lsData, lsRes) = try await session.data(from: URL(string: "\(base)/api/ls?dir=\(encodedDir)")!)
    #expect((lsRes as? HTTPURLResponse)?.statusCode == 200)
    let listing = try JSONDecoder().decode(DirectoryListing.self, from: lsData)
    #expect(listing.entries.map(\.name) == ["Sample.mp4"])

    // 5. Ping & Bye client tracking
    let (pingData, _) = try await session.data(from: URL(string: "\(base)/api/ping?id=tab1")!)
    #expect(String(decoding: pingData, as: UTF8.self).contains("\"configVersion\":2"))
    #expect(delegate.latestStats.clientCount == 1)

    let (_, byeRes) = try await session.data(from: URL(string: "\(base)/api/bye?id=tab1")!)
    #expect((byeRes as? HTTPURLResponse)?.statusCode == 204)
    #expect(delegate.latestStats.clientCount == 0)

    // 6. Progress sync + Recents
    var progReq = URLRequest(url: URL(string: "\(base)/api/progress")!)
    progReq.httpMethod = "POST"
    progReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
    progReq.httpBody = Data(#"{"path":"/tmp/Sample.mp4","position":95,"duration":300}"#.utf8)
    let (_, progRes) = try await session.data(for: progReq)
    #expect((progRes as? HTTPURLResponse)?.statusCode == 200)

    let (recData, _) = try await session.data(from: URL(string: "\(base)/api/recents")!)
    let recents = try JSONDecoder().decode([RecentVideo].self, from: recData)
    #expect(recents.count == 1)
    #expect(recents[0].position == 95)

    // 7. Invalid video stream rejected with 400
    let (_, badStreamRes) = try await session.data(from: URL(string: "\(base)/stream?file=/etc/hosts")!)
    #expect((badStreamRes as? HTTPURLResponse)?.statusCode == 400)

    // 8. Unknown route returns 404
    let (_, notFoundRes) = try await session.data(from: URL(string: "\(base)/nope")!)
    #expect((notFoundRes as? HTTPURLResponse)?.statusCode == 404)
  }

  @Test func liveFFmpegProbeStreamAndSubtitles() async throws {
    let status = VideoMediaEngine.checkFFmpeg()
    guard let ffmpeg = status.ffmpegPath, status.isReady else { return }

    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("kitbag-ff-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let srtURL = dir.appendingPathComponent("test.srt")
    try "1\n00:00:00,000 --> 00:00:01,000\nHello Kitbag Cinema\n".write(
      to: srtURL, atomically: true, encoding: .utf8)
    let mkvURL = dir.appendingPathComponent("clip.mkv")

    // Generate a 1-second synthetic H.264 + AAC + SRT MKV clip
    let gen = Process()
    gen.executableURL = URL(fileURLWithPath: ffmpeg)
    gen.arguments = [
      "-nostdin", "-y", "-v", "error",
      "-f", "lavfi", "-i", "color=c=blue:s=320x180:d=1",
      "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
      "-i", srtURL.path,
      "-c:v", "libx264", "-pix_fmt", "yuv420p",
      "-c:a", "aac",
      "-c:s", "srt",
      mkvURL.path,
    ]
    gen.standardInput = FileHandle.nullDevice
    gen.standardOutput = FileHandle.nullDevice
    gen.standardError = FileHandle.nullDevice
    try gen.run()
    gen.waitUntilExit()
    #expect(gen.terminationStatus == 0)

    let delegate = MockDelegate()
    let server = LocalHTTPServer(engine: VideoMediaEngine(), delegate: delegate)
    let port = try await server.start(port: 0)
    defer { server.stop() }

    let base = "http://127.0.0.1:\(port)"
    let session = URLSession(configuration: .ephemeral)
    let encodedFile = mkvURL.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!

    // 1. Live /api/probe
    let (probeData, probeRes) = try await session.data(
      from: URL(string: "\(base)/api/probe?file=\(encodedFile)")!)
    #expect((probeRes as? HTTPURLResponse)?.statusCode == 200)
    let probed = try JSONDecoder().decode(ProbeResult.self, from: probeData)
    #expect(probed.duration >= 0.8)
    #expect(probed.video?.codec == "h264")
    #expect(probed.audio.count == 1)
    #expect(probed.subs.count == 1)

    // 2. Live /subs embedded WebVTT conversion
    let (subData, subRes) = try await session.data(
      from: URL(string: "\(base)/subs?file=\(encodedFile)&sid=1")!)
    #expect((subRes as? HTTPURLResponse)?.statusCode == 200)
    let vtt = String(decoding: subData, as: UTF8.self)
    #expect(vtt.contains("WEBVTT"))
    #expect(vtt.contains("Hello Kitbag Cinema"))

    // 3. Live /stream direct-copy fragmented MP4
    let (copyData, copyRes) = try await session.data(
      from: URL(string: "\(base)/stream?file=\(encodedFile)&aid=1&q=orig&t=0")!)
    let copyHTTP = try #require(copyRes as? HTTPURLResponse)
    #expect(copyHTTP.statusCode == 200)
    #expect(copyHTTP.value(forHTTPHeaderField: "Content-Type") == "video/mp4")
    #expect(copyData.count > 1000)
    #expect(copyData.range(of: Data("ftyp".utf8)) != nil)
    #expect(copyData.range(of: Data("moov".utf8)) != nil)

    // 4. Live /stream transcoded + filtered seek
    let (transData, transRes) = try await session.data(
      from: URL(string: "\(base)/stream?file=\(encodedFile)&aid=1&q=enhance&t=0.2")!)
    let transHTTP = try #require(transRes as? HTTPURLResponse)
    #expect(transHTTP.statusCode == 200)
    #expect(transData.count > 1000)
    #expect(transData.range(of: Data("ftyp".utf8)) != nil)
  }
}
