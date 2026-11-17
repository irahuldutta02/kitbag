import AppKit
import Foundation
import KitbagCore

struct ShelfItem: Codable, Identifiable, Equatable {
  let id: UUID
  var bookmark: Data  // reference only; file contents are never stored
  var name: String
}

enum TransferMode: String { case copy, move }

/// What was asked for, before the destination is known.
enum ConvertRequest: Equatable {
  case format(ConvertFormat)
  case mergePDF
  case compress  // same format, smaller
  case cleanOnly  // same format, same pixels, no hidden data
}

/// What happens to the shelf once a conversion is done.
enum AfterConvert: String, CaseIterable, Identifiable {
  case keep  // the shelf stays exactly as it was
  case replace  // converted originals leave the shelf; the new files take their place
  case remove  // converted originals leave the shelf; nothing is added

  var id: String { rawValue }
}

/// What a request would do with the files on the shelf, for the summary line.
struct ConvertPlan: Equatable {
  var convert = 0
  var alreadyThatFormat = 0
  var unsupported = 0
  var missing = 0
  /// Whether any converted file carries camera/location info the person can choose to remove.
  var hasMetadata = false
}

/// One file's size before and after, worked out by really converting it to a scratch folder.
struct EstimateRow: Identifiable, Equatable {
  let id: UUID
  let name: String
  let before: Int64
  var after: Int64?
  var failed = false
}

enum SaveDestination {
  case original  // next to each original file
  case folder(URL)
  case replace  // the original goes to the Trash and the new file takes its place
}

/// How far along a conversion is.
struct ConvertProgress: Equatable {
  var done: Int
  var total: Int
  var title: String
}

@MainActor
final class ShelfModel: ObservableObject {
  static let maxItems = 100
  private static let storageKey = "fileshelf.items"
  private static let modeKey = "fileshelf.mode"
  private static let clearKey = "fileshelf.clearAfterDrop"
  private static let qualityKey = "fileshelf.convertQuality"
  private static let afterKey = "fileshelf.afterConvert"
  private static let stripKey = "fileshelf.stripMetadata"
  private static let levelKey = "fileshelf.compressLevel"

  @Published private(set) var items: [ShelfItem] = []
  @Published private(set) var missing: Set<UUID> = []
  @Published var message: String?
  /// Other tools' "send with…" destinations (for example Blip), offered under the shelf.
  @Published var senders: [FileSender] = []
  @Published var targetedSender: String?
  @Published var dropTargeted = false
  /// Quick switch: what happens when the stack is dropped into a folder.
  @Published var mode: TransferMode {
    didSet { defaults.set(mode.rawValue, forKey: Self.modeKey) }
  }
  /// Setting: empty the shelf after a successful copy-drop (a move always empties it).
  @Published var clearAfterDrop: Bool {
    didSet { defaults.set(clearAfterDrop, forKey: Self.clearKey) }
  }

  /// Formats the files on the shelf can be converted to (empty when nothing there is convertible).
  @Published private(set) var convertFormats: [ConvertFormat] = []
  @Published private(set) var canMerge = false
  @Published private(set) var converting: ConvertProgress?
  /// Setting: quality for JPG and HEIC, 0.05...1.
  @Published var convertQuality: Double {
    didSet { defaults.set(convertQuality, forKey: Self.qualityKey) }
  }
  /// Setting: what happens to the shelf after converting.
  @Published var afterConvert: AfterConvert {
    didSet { defaults.set(afterConvert.rawValue, forKey: Self.afterKey) }
  }
  /// Remove camera, date and location info from converted images. Remembered from the last time.
  @Published var stripMetadata: Bool {
    didSet {
      defaults.set(stripMetadata, forKey: Self.stripKey)
      if pendingConvert != nil { startEstimate() }  // the size changes with it
    }
  }
  /// Whether any file on the shelf can be compressed or cleaned in its own format.
  @Published private(set) var canOptimize = false
  /// Compress while converting (the Compress box in the confirm step).
  @Published var compressEnabled = false {
    didSet { if pendingConvert != nil { startEstimate() } }
  }
  /// Remove hidden data when compressing or cleaning in the file's own format (the Remove data box).
  @Published var cleanEnabled = false {
    didSet { if pendingConvert != nil { startEstimate() } }
  }
  @Published var compressLevel: CompressLevel {
    didSet {
      defaults.set(compressLevel.rawValue, forKey: Self.levelKey)
      if pendingConvert != nil { startEstimate() }
    }
  }
  /// Before/after sizes for the pending request.
  @Published private(set) var estimateRows: [EstimateRow] = []
  @Published private(set) var estimating = false
  /// Whether the shelf shows its list of files (to remove one) instead of only the stack.
  @Published var listExpanded = false
  private var estimateTask: Task<Void, Never>?
  /// A conversion waiting for the person to say where to save it.
  @Published private(set) var pendingConvert: ConvertRequest?
  private var convertTask: Task<Void, Never>?

  private struct Access {
    let url: URL
    let scoped: Bool
  }
  private var open: [UUID: Access] = [:]
  private let defaults: UserDefaults
  private let fm = FileManager.default

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    mode = defaults.string(forKey: Self.modeKey).flatMap(TransferMode.init) ?? .copy
    clearAfterDrop = defaults.bool(forKey: Self.clearKey)
    afterConvert = defaults.string(forKey: Self.afterKey).flatMap(AfterConvert.init) ?? .keep
    stripMetadata = defaults.bool(forKey: Self.stripKey)
    compressLevel = defaults.string(forKey: Self.levelKey).flatMap(CompressLevel.init) ?? .medium
    convertQuality = defaults.object(forKey: Self.qualityKey) as? Double ?? 0.85
    Task.detached { Self.cleanOldPastes() }
    if let data = defaults.data(forKey: Self.storageKey),
      let saved = try? JSONDecoder().decode([ShelfItem].self, from: data)
    {
      items = saved
    }
  }

  // MARK: Items

  func add(_ urls: [URL]) {
    refresh()  // so a restored file isn't added twice
    message = nil
    // A web link dropped on the shelf becomes a small link file, so it can be sent like any file.
    let urls = urls.compactMap { $0.isFileURL ? $0 : Self.writeLink($0) }
    for url in urls where url.isFileURL {
      guard items.count < Self.maxItems else {
        message = String(localized: "The shelf is full (\(Self.maxItems) items).")
        break
      }
      let path = url.standardizedFileURL.path
      if open.values.contains(where: { $0.url.standardizedFileURL.path == path }) { continue }
      do {
        let item = ShelfItem(
          id: UUID(), bookmark: try Self.makeBookmark(url), name: url.lastPathComponent)
        items.append(item)
        open[item.id] = Access(url: url, scoped: url.startAccessingSecurityScopedResource())
      } catch {
        message = String(
          localized: "Couldn't add “\(url.lastPathComponent)”: \(error.localizedDescription)")
      }
    }
    save()
    if !urls.isEmpty, !items.isEmpty { senders.forEach { $0.prepare?() } }
  }

  /// Sends the whole shelf, or just `urls` when given. After the whole shelf was sent, it is cleared.
  func send(with sender: FileSender, urls: [URL]? = nil) {
    let files = urls ?? items.compactMap { url(for: $0.id) }
    guard !files.isEmpty else { return }
    Task {
      let result = await sender.send(files)
      message = result.message
      if result.success, urls == nil { clear() }
    }
  }

  func remove(_ id: UUID) {
    stopAccess(id)
    items.removeAll { $0.id == id }
    missing.remove(id)
    save()
    if items.isEmpty { senders.forEach { $0.release?() } }
  }

  func clear() {
    for id in Array(open.keys) { stopAccess(id) }
    items.removeAll()
    missing.removeAll()
    save()
    senders.forEach { $0.release?() }
  }

  func shutdown() {
    convertTask?.cancel()
    for id in Array(open.keys) { stopAccess(id) }
  }

  /// Re-resolves every bookmark: picks up moved files, flags deleted ones.
  func refresh() {
    message = nil
    var gone = Set<UUID>()
    for i in items.indices {
      if let url = resolve(at: i) {
        if items[i].name != url.lastPathComponent { items[i].name = url.lastPathComponent }
      } else {
        gone.insert(items[i].id)
      }
    }
    missing = gone
    save()
  }

  /// Small system icon from the already-resolved path; never touches the file system state.
  func icon(for id: UUID, size: CGFloat = 24) -> NSImage {
    let i =
      open[id].map { NSWorkspace.shared.icon(forFile: $0.url.path) }
      ?? NSWorkspace.shared.icon(for: .data)
    i.size = NSSize(width: size, height: size)
    return i
  }

  /// Size on disk of an item, if it can be found.
  func fileSize(for id: UUID) -> Int64? {
    url(forOpen: id).map { Self.fileSize($0) }
  }

  /// Lets the person add files or folders with the standard open panel.
  func addFromPicker() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true
    panel.prompt = String(localized: "Add")
    NSApp.activate(ignoringOtherApps: true)
    // Not modal: the pop-up may close behind the panel, and the shelf carries on regardless.
    panel.begin { [weak self] response in
      MainActor.assumeIsolated {
        guard response == .OK, let self else { return }
        self.add(panel.urls)
      }
    }
  }

  /// The resolved URL of an item already in use (no bookmark work); nil until the shelf has resolved it.
  func url(forOpen id: UUID) -> URL? { open[id]?.url }

  func url(for id: UUID) -> URL? {
    items.firstIndex { $0.id == id }.flatMap { resolve(at: $0) }
  }

  private func resolve(at i: Int) -> URL? {
    let item = items[i]
    if let a = open[item.id] {
      if fm.fileExists(atPath: a.url.path) { return a.url }
      stopAccess(item.id)  // moved or deleted: fall through to bookmark
    }
    var stale = false
    guard let url = Self.resolveBookmark(item.bookmark, stale: &stale) else { return nil }
    let scoped = url.startAccessingSecurityScopedResource()
    guard fm.fileExists(atPath: url.path) else {
      if scoped { url.stopAccessingSecurityScopedResource() }
      return nil
    }
    open[item.id] = Access(url: url, scoped: scoped)
    if stale, let fresh = try? Self.makeBookmark(url) { items[i].bookmark = fresh }
    return url
  }

  private func stopAccess(_ id: UUID) {
    if let a = open.removeValue(forKey: id), a.scoped {
      a.url.stopAccessingSecurityScopedResource()
    }
  }

  private func save() {
    defaults.set(try? JSONEncoder().encode(items), forKey: Self.storageKey)
    updateConvertOptions()
  }

  private static func makeBookmark(_ url: URL) throws -> Data {
    // Unsandboxed runs (tests) may reject security scope; plain bookmarks still work there.
    if let d = try? url.bookmarkData(options: .withSecurityScope) { return d }
    return try url.bookmarkData()
  }

  private static func resolveBookmark(_ data: Data, stale: inout Bool) -> URL? {
    if let u = try? URL(
      resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
      bookmarkDataIsStale: &stale)
    {
      return u
    }
    return try? URL(
      resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
  }
}

// MARK: Converting

extension ShelfModel {
  private var shelfFiles: [(id: UUID, url: URL)] {
    items.compactMap { item in url(forOpen: item.id).map { (item.id, $0) } }
  }

  func updateConvertOptions() {
    let files = shelfFiles.map(\.url)
    convertFormats = Converter.formats(for: files)
    canMerge = Converter.mergeable(files).count >= 2
    canOptimize = files.contains { Converter.sameFormat(of: $0) != nil }
    // Files were added or removed while a request is waiting: drop it if it no longer fits,
    // otherwise measure again.
    switch pendingConvert {
    case .format(let f)? where !convertFormats.contains(f): cancelRequest()
    case .mergePDF? where !canMerge: cancelRequest()
    case .compress? where !canOptimize, .cleanOnly? where !canOptimize: cancelRequest()
    case nil: break
    default: if converting == nil { startEstimate() }
    }
  }

  func cancelConvert() { convertTask?.cancel() }

  /// What the pending request does for compression and hidden data.
  func options(for request: ConvertRequest) -> ConvertOptions {
    var o = ConvertOptions(quality: convertQuality)
    switch request {
    case .compress, .cleanOnly:  // both boxes are shown for either; they start from what was tapped
      o.compress = compressEnabled ? compressLevel : nil
      o.stripMetadata = cleanEnabled
    case .format: o.compress = compressEnabled ? compressLevel : nil; o.stripMetadata = stripMetadata
    case .mergePDF: break
    }
    return o
  }

  /// A summary of what the pending request will do.
  func plan(for request: ConvertRequest) -> ConvertPlan {
    let files = shelfFiles.map(\.url)
    var plan = ConvertPlan(missing: items.count - files.count)
    for url in files {
      let kind = Converter.kind(of: url)
      switch request {
      case .format(let f):
        if Converter.canConvert(url, to: f) {
          plan.convert += 1
          if f.isImage && kind == .image { plan.hasMetadata = true }
        } else if kind == .other { plan.unsupported += 1 } else { plan.alreadyThatFormat += 1 }
      case .mergePDF:
        if Converter.isMergeable(url) { plan.convert += 1 } else { plan.unsupported += 1 }
      case .compress, .cleanOnly:
        if Converter.sameFormat(of: url) != nil {
          plan.convert += 1
          if kind == .image { plan.hasMetadata = true }
        } else { plan.unsupported += 1 }
      }
    }
    return plan
  }

  /// Step 1: a format (or Compress, or Remove data) was tapped. The row now asks where to save.
  func requestConvert(_ request: ConvertRequest) {
    guard converting == nil else { return }
    message = nil
    compressEnabled = request == .compress
    cleanEnabled = request == .cleanOnly
    pendingConvert = request
    startEstimate()
  }

  func cancelRequest() {
    pendingConvert = nil
    estimateTask?.cancel()
    estimating = false
    estimateRows = []
  }

  nonisolated static func fileSize(_ url: URL) -> Int64 {
    let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
    guard values?.isDirectory == true else { return Int64(values?.fileSize ?? 0) }
    // A folder is the sum of what is inside it.
    let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
    return files?.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }
      .reduce(0) { $0 + Int64($1) } ?? 0
  }

  /// Which files a request applies to.
  private func jobs(for request: ConvertRequest) -> [(id: UUID, url: URL)] {
    shelfFiles.filter { f in
      switch request {
      case .format(let fmt): return Converter.canConvert(f.url, to: fmt)
      case .mergePDF: return Converter.isMergeable(f.url)
      case .compress, .cleanOnly: return Converter.sameFormat(of: f.url) != nil
      }
    }
  }

  /// The one place a file is processed, for the real run and for the size estimate.
  nonisolated static func process(
    _ request: ConvertRequest, _ url: URL, _ options: ConvertOptions, into dir: URL, suffix: String
  ) throws -> [URL] {
    switch request {
    case .format(let f): return try Converter.convert(url, to: f, options: options, into: dir)
    case .compress, .cleanOnly:
      let tag = options.compress != nil ? "compressed" : "clean"
      return [try Converter.optimize(url, options: options, suffix: suffix.isEmpty ? "" : suffix + tag, into: dir)]
    case .mergePDF: return []
    }
  }

  /// Really converts each file into a scratch folder to learn the true size, then deletes it.
  func startEstimate() {
    estimateTask?.cancel()
    guard let request = pendingConvert else { return }
    let options = options(for: request)
    var rows: [EstimateRow] = []
    var work: [(id: UUID, urls: [URL])] = []
    if request == .mergePDF {
      let parts = jobs(for: request)
      rows = [EstimateRow(
        id: UUID(), name: String(localized: "Combined PDF"),
        before: parts.map { Self.fileSize($0.url) }.reduce(0, +))]
      work = [(rows[0].id, parts.map(\.url))]
    } else {
      for file in jobs(for: request) {
        rows.append(EstimateRow(id: file.id, name: file.url.lastPathComponent, before: Self.fileSize(file.url)))
        work.append((file.id, [file.url]))
      }
    }
    estimateRows = rows
    estimating = !rows.isEmpty
    estimateTask = Task { [weak self] in
      for item in work {
        if Task.isCancelled { return }
        let after: Int64? = await Task.detached {
          let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("kitbag-estimate-\(UUID().uuidString)", isDirectory: true)
          try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
          defer { try? FileManager.default.removeItem(at: tmp) }
          do {
            let outs = request == .mergePDF
              ? [try Converter.merge(item.urls, into: tmp).output]
              : try Self.process(request, item.urls[0], options, into: tmp, suffix: " ")
            return outs.map(Self.fileSize).reduce(0, +)
          } catch { return nil }
        }.value
        if Task.isCancelled { return }
        guard let self else { return }
        if let i = self.estimateRows.firstIndex(where: { $0.id == item.id }) {
          self.estimateRows[i].after = after
          self.estimateRows[i].failed = after == nil
        }
      }
      self?.estimating = false
    }
  }

  /// Step 2a/2b/2c: run the pending request, saving next to the originals, in a chosen folder, or
  /// over the originals (which go to the Trash).
  func runPending(saveTo destination: SaveDestination) {
    guard let request = pendingConvert, converting == nil else { return }
    if (request == .compress || request == .cleanOnly) && !compressEnabled && !cleanEnabled { return }
    if case .replace = destination {
      guard Shell.confirm(
        String(localized: "Replace the originals?"),
        String(localized: "The old files go to the Trash, so you can put them back."),
        action: String(localized: "Replace"))
      else { return }
    }
    let options = options(for: request)
    cancelRequest()
    if request == .mergePDF { mergeToPDF(destination: destination) } else { run(request, options, destination) }
  }

  /// Step 2b: pick a folder first.
  func chooseFolderAndRun() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = String(localized: "Save Here")
    panel.message = String(localized: "Choose where to save the files")
    if let last = defaults.string(forKey: "fileshelf.lastSaveFolder") {
      panel.directoryURL = URL(fileURLWithPath: last)
    }
    NSApp.activate(ignoringOtherApps: true)
    // Not modal: the pop-up may close behind the panel, and the shelf carries on regardless.
    panel.begin { [weak self] response in
      MainActor.assumeIsolated {
        guard response == .OK, let url = panel.url, let self else { return }  // cancelled: nothing changes
        self.defaults.set(url.path, forKey: "fileshelf.lastSaveFolder")
        self.runPending(saveTo: .folder(url))
      }
    }
  }

  private struct JobResult {
    var outputs: [URL] = []
    var before: Int64 = 0
    var after: Int64 = 0
    var noGain = false
  }

  private func run(_ request: ConvertRequest, _ options: ConvertOptions, _ destination: SaveDestination) {
    let files = shelfFiles
    let jobs = jobs(for: request)
    guard !jobs.isEmpty else {
      message = String(localized: "Nothing on the shelf fits.")
      return
    }
    message = nil
    let title: String
    switch request {
    case .format(let f): title = f.label
    case .compress, .cleanOnly:
      title = options.compress != nil ? String(localized: "smaller files") : String(localized: "clean files")
    case .mergePDF: title = "PDF"
    }
    converting = ConvertProgress(done: 0, total: jobs.count, title: title)
    convertTask = Task { [weak self] in
      var saved: [URL] = []
      var failed: [String] = []
      var done: [UUID] = []
      var before: Int64 = 0
      var after: Int64 = 0
      var noGain = 0
      for (n, job) in jobs.enumerated() {
        if Task.isCancelled { break }
        let result = await Task.detached { () -> Result<JobResult, Error> in
          Result { try Self.runJob(request, job.url, options, destination) }
        }.value
        switch result {
        case .success(let r):
          if r.noGain { noGain += 1 } else {
            saved += r.outputs
            done.append(job.id)
            before += r.before
            after += r.after
          }
        case .failure(let e):
          failed.append("“\(job.url.lastPathComponent)” \(e.localizedDescription)")
        }
        self?.converting?.done = n + 1
      }
      self?.finish(
        request: request, options: options, destination: destination, saved: saved, sources: done, failed: failed,
        skipped: files.count - jobs.count, noGain: noGain, savedBytes: before - after,
        cancelled: Task.isCancelled)
    }
  }

  /// One file, off the main thread.
  private nonisolated static func runJob(
    _ request: ConvertRequest, _ url: URL, _ options: ConvertOptions, _ destination: SaveDestination
  ) throws -> JobResult {
    let fm = FileManager.default
    var dir: URL
    var suffix = " "  // " compressed", " clean": the name differs from the original
    var scratch: URL?
    switch destination {
    case .replace:
      let tmp = fm.temporaryDirectory.appendingPathComponent("kitbag-\(UUID().uuidString)", isDirectory: true)
      try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
      scratch = tmp
      dir = tmp
      suffix = ""
    default:
      dir = try outputFolder(for: url, destination)
    }
    defer { if let scratch { try? fm.removeItem(at: scratch) } }

    var outs = try process(request, url, options, into: dir, suffix: suffix)
    let before = fileSize(url)
    let after = outs.map(fileSize).reduce(0, +)
    // Compressing must never make a file bigger: leave it as it is.
    if request == .compress || request == .cleanOnly, options.compress != nil, !options.stripMetadata,
      after >= before
    {
      outs.forEach { try? fm.removeItem(at: $0) }
      return JobResult(before: before, after: before, noGain: true)
    }
    if case .replace = destination {
      outs = try outs.map { try replaceOriginal(url, with: $0) }
    }
    return JobResult(outputs: outs, before: before, after: after)
  }

  /// The original goes to the Trash (so it can be put back) and the new file takes its path.
  private nonisolated static func replaceOriginal(_ original: URL, with new: URL) throws -> URL {
    let fm = FileManager.default
    var trashed: NSURL?
    try fm.trashItem(at: original, resultingItemURL: &trashed)
    do {
      try fm.moveItem(at: new, to: original)
    } catch {
      if let t = trashed as URL? { try? fm.moveItem(at: t, to: original) }  // put the original back
      throw error
    }
    return original
  }

  /// Joins the images and PDFs on the shelf, in shelf order, into one PDF.
  private func mergeToPDF(destination: SaveDestination) {
    let files = jobs(for: .mergePDF)
    guard files.count >= 2 else { return }
    message = nil
    converting = ConvertProgress(done: 0, total: 1, title: "PDF")
    convertTask = Task { [weak self] in
      let result = await Task.detached { () -> Result<(URL, [String]), Error> in
        Result {
          let m = try Converter.merge(
            files.map(\.url), into: try Self.outputFolder(for: files[0].url, destination))
          return (m.output, m.skipped)
        }
      }.value
      guard let self else { return }
      switch result {
      case .success(let (out, skipped)):
        self.finish(
          request: .mergePDF, options: ConvertOptions(), destination: destination, saved: [out],
          sources: files.filter { !skipped.contains($0.url.lastPathComponent) }.map(\.id),
          failed: skipped.map { "“\($0)” " + String(localized: "can't be read") }, skipped: 0,
          noGain: 0, savedBytes: 0, cancelled: false)
      case .failure(let e):
        self.converting = nil
        self.message = String(localized: "Couldn't merge: the files \(e.localizedDescription).")
      }
    }
  }

  private func finish(
    request: ConvertRequest, options: ConvertOptions, destination: SaveDestination, saved: [URL], sources: [UUID],
    failed: [String], skipped: Int, noGain: Int, savedBytes: Int64, cancelled: Bool
  ) {
    converting = nil
    let n = sources.count
    var lines: [String] = []
    if n > 0 {
      let files = n == 1 ? String(localized: "1 file") : String(localized: "\(n) files")
      var head: String
      switch request {
      case .format(let f): head = String(localized: "Converted \(files) to \(f.label)")
      case .mergePDF: head = String(localized: "Combined \(files) into one PDF")
      case .compress, .cleanOnly:
        switch (options.compress != nil, options.stripMetadata) {
        case (true, true): head = String(localized: "Compressed \(files) and removed hidden data")
        case (true, false): head = String(localized: "Compressed \(files)")
        default: head = String(localized: "Removed hidden data from \(files)")
        }
        if options.compress != nil, savedBytes > 0 {
          head += " · " + String(localized: "saved \(ShelfFormat.bytes(savedBytes))")
        }
      }
      lines.append((cancelled ? String(localized: "Cancelled. ") : "") + head + ".")
      if case .replace = destination {
        // The files at these paths are new, so the shelf must point at them.
        sources.forEach { remove($0) }
        add(saved)
      } else {
        switch afterConvert {
        case .keep: NSWorkspace.shared.activateFileViewerSelecting(saved)
        case .remove:
          sources.forEach { remove($0) }
          NSWorkspace.shared.activateFileViewerSelecting(saved)
        case .replace:
          sources.forEach { remove($0) }
          add(saved)  // the new files are on the shelf, ready to drag out
        }
      }
    } else if cancelled {
      lines.append(String(localized: "Cancelled."))
    }
    if noGain > 0 {
      lines.append(noGain == 1
        ? String(localized: "1 file was already as small as it can get.")
        : String(localized: "\(noGain) files were already as small as they can get."))
    }
    if skipped > 0 { lines.append(String(localized: "\(skipped) skipped.")) }
    lines.append(contentsOf: failed.map { String(localized: "Couldn't convert \($0).") })
    message = lines.isEmpty ? nil : lines.joined(separator: "\n")
  }

  /// The folder a converted file is written to.
  nonisolated static func outputFolder(for source: URL, _ destination: SaveDestination) throws -> URL {
    let fm = FileManager.default
    switch destination {
    case .original, .replace:
      let parent = source.deletingLastPathComponent()
      guard fm.isWritableFile(atPath: parent.path) else {
        throw ConvertError.writeFailed(String(localized: "its folder is read-only"))
      }
      return parent
    case .folder(let url):
      try fm.createDirectory(at: url, withIntermediateDirectories: true)
      return url
    }
  }
}

// MARK: Pasting text, links and images

extension ShelfModel {
  /// Puts whatever is on the clipboard on the shelf: copied files stay files; an image becomes a PNG;
  /// a web link becomes a link file; any other text becomes a text file. Blip then sends them like files.
  func pasteFromClipboard() {
    let pb = NSPasteboard.general
    message = nil
    if let files = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
      !files.isEmpty
    {
      add(files)
      return
    }
    if let url = Self.pastedImage(pb) {
      add([url])
      return
    }
    if let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
      if let link = Self.webLink(text), let file = Self.writeLink(link) { add([file]) }
      else if let file = Self.writeText(text) { add([file]) }
      else { message = String(localized: "Couldn't save the pasted text.") }
      return
    }
    if let url = (pb.readObjects(forClasses: [NSURL.self]) as? [URL])?.first, let file = Self.writeLink(url) {
      add([file])
      return
    }
    message = String(localized: "Nothing to paste. Copy a file, image, link or text first.")
  }

  /// Pasted items are written here, each in its own folder so names stay clean.
  nonisolated static var pastedRoot: URL { PastedItems.root }

  private nonisolated static func newFile(_ name: String) -> URL? {
    let dir = pastedRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
    guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else {
      return nil
    }
    return dir.appendingPathComponent(name)
  }

  /// A short, file-name-safe label from text.
  private nonisolated static func label(_ text: String, max: Int = 32) -> String {
    let bad = CharacterSet(charactersIn: "/:\\\n\r\t")
    let cleaned = text.components(separatedBy: bad).joined(separator: " ")
      .trimmingCharacters(in: .whitespaces)
    return String(cleaned.prefix(max)).trimmingCharacters(in: .whitespaces)
  }

  private static func pastedImage(_ pb: NSPasteboard) -> URL? {
    var png = pb.data(forType: .png)
    if png == nil, let image = NSImage(pasteboard: pb), let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff)
    {
      png = rep.representation(using: .png, properties: [:])
    }
    guard let png, let file = newFile(String(localized: "Pasted image") + ".png") else { return nil }
    return (try? png.write(to: file)) != nil ? file : nil
  }

  /// The text as a web link, only if the whole text is one.
  private nonisolated static func webLink(_ text: String) -> URL? {
    guard !text.contains(where: \.isWhitespace), let url = URL(string: text),
      let scheme = url.scheme?.lowercased(), ["http", "https", "ftp", "mailto"].contains(scheme)
    else { return nil }
    return url
  }

  /// A `.webloc` file, which opens the link when double-clicked.
  nonisolated static func writeLink(_ url: URL) -> URL? {
    let host = url.host ?? url.absoluteString
    guard let file = newFile(label(String(localized: "Link") + " – " + host) + ".webloc") else { return nil }
    let plist: [String: Any] = ["URL": url.absoluteString]
    guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0),
      (try? data.write(to: file)) != nil
    else { return nil }
    return file
  }

  nonisolated static func writeText(_ text: String) -> URL? {
    let name = label(text).isEmpty ? String(localized: "Pasted text") : label(text)
    guard let file = newFile(name + ".txt"), (try? text.write(to: file, atomically: true, encoding: .utf8)) != nil
    else { return nil }
    return file
  }

  /// Pasted items older than a week are deleted.
  nonisolated static func cleanOldPastes() {
    let fm = FileManager.default
    guard let dirs = try? fm.contentsOfDirectory(at: pastedRoot, includingPropertiesForKeys: [.contentModificationDateKey])
    else { return }
    let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
    for d in dirs {
      if let date = (try? d.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
        date < cutoff
      {
        try? fm.removeItem(at: d)
      }
    }
  }
}
