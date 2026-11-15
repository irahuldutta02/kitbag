import AppKit
import Foundation
import KitbagCore

struct ShelfItem: Codable, Identifiable, Equatable {
  let id: UUID
  var bookmark: Data  // reference only; file contents are never stored
  var name: String
}

enum TransferMode: String { case copy, move }

@MainActor
final class ShelfModel: ObservableObject {
  static let maxItems = 100
  private static let storageKey = "fileshelf.items"
  private static let modeKey = "fileshelf.mode"
  private static let clearKey = "fileshelf.clearAfterDrop"

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
