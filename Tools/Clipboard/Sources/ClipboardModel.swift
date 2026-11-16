import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ImageIO
import KitbagCore

/// Watches the clipboard, remembers what was copied (newest first, pinned on top, no repeats),
/// and pastes an item back into the app in front.
@MainActor
final class ClipboardModel: ObservableObject {
  static let limits = [50, 100, 200, 500, 1000]

  @Published private(set) var items: [ClipItem] = []
  /// While paused nothing new is saved; the history stays usable.
  @Published var paused: Bool { didSet { defaults.set(paused, forKey: Self.pausedKey) } }
  /// How many unpinned items to keep.
  @Published var limit: Int {
    didSet {
      defaults.set(limit, forKey: Self.limitKey)
      trim()
      save()
    }
  }
  /// False if another app already owns the shortcut.
  @Published private(set) var shortcutWorks = true
  /// The key combination that opens the pop-up anywhere.
  @Published private(set) var shortcut: ClipShortcut
  private var hotKeyEnabled = false

  private static let pausedKey = "kitbag.clipboard.paused"
  private static let limitKey = "kitbag.clipboard.limit"

  let dir: URL
  private let defaults: UserDefaults
  private let pasteboard: NSPasteboard
  private var lastChange = 0
  private(set) var timer: Timer?
  private let hotKey = GlobalHotKey()
  private lazy var popup = ClipboardPopup(model: self)
  private let guide = AccessibilityGuide()
  private let io = DispatchQueue(label: "kitbag.clipboard.io", qos: .utility)
  private let thumbs = NSCache<NSUUID, NSImage>()

  nonisolated static var defaultDir: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Kitbag/Clipboard", isDirectory: true)
  }

  init(dir: URL = ClipboardModel.defaultDir, defaults: UserDefaults = .standard, pasteboard: NSPasteboard = .general) {
    self.dir = dir
    self.defaults = defaults
    self.pasteboard = pasteboard
    paused = defaults.bool(forKey: Self.pausedKey)
    limit = (defaults.object(forKey: Self.limitKey) as? Int) ?? 200
    shortcut = ClipShortcut.load(defaults)
  }

  // MARK: Lifecycle

  /// `shortcut: false` skips the global shortcut (tests).
  func start(shortcut: Bool = true) {
    // The history can hold private text, so only this user may read the folder.
    try? FileManager.default.createDirectory(
      at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    load()
    lastChange = pasteboard.changeCount  // what is already there was copied before we were watching
    let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.poll() }
    }
    t.tolerance = 0.1
    RunLoop.main.add(t, forMode: .common)
    timer = t
    if shortcut {
      hotKeyEnabled = true
      hotKey.onPress = { [weak self] in self?.popup.toggle() }
      registerHotKey()
    }
  }

  private func registerHotKey() {
    shortcutWorks = hotKey.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
  }

  /// Switches to a new shortcut. If another app already owns it, the old one stays and this returns false.
  @discardableResult
  func setShortcut(_ new: ClipShortcut) -> Bool {
    let old = shortcut
    guard hotKeyEnabled else {
      shortcut = new
      new.save(defaults)
      return true
    }
    if hotKey.register(keyCode: new.keyCode, modifiers: new.modifiers) {
      shortcut = new
      shortcutWorks = true
      new.save(defaults)
      return true
    }
    hotKey.register(keyCode: old.keyCode, modifiers: old.modifiers)
    return false
  }

  /// While a new shortcut is being typed, the current one must not fire.
  func pauseHotKey(_ pause: Bool) {
    guard hotKeyEnabled else { return }
    if pause { hotKey.unregister() } else { registerHotKey() }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    hotKey.unregister()
    popup.close()
    guide.close()
    flush()
  }

  /// Checks the pasteboard once. The system has no "clipboard changed" event, so this runs on a timer.
  func poll() {
    let change = pasteboard.changeCount
    guard change != lastChange else { return }
    lastChange = change
    guard !paused, let capture = ClipPasteboard.read(pasteboard) else { return }
    add(capture, app: NSWorkspace.shared.frontmostApplication?.localizedName)
  }

  // MARK: History

  /// Adds a copy. Copying the same thing again moves the old entry to the top instead of adding a second one.
  func add(_ capture: ClipCapture, app: String? = nil, date: Date = Date()) {
    let hash = capture.hash
    if let i = items.firstIndex(where: { $0.hash == hash }) {
      items[i].date = date
      if let app { items[i].app = app }
    } else {
      var item = ClipItem(
        id: UUID(), kind: capture.kind,
        text: String(capture.text.prefix(ClipPasteboard.indexedTextLimit)), hash: hash, date: date)
      item.app = app
      item.detail = capture.detail
      if !capture.payload.isEmpty {
        let data = try? PropertyListSerialization.data(fromPropertyList: capture.payload, format: .binary, options: 0)
        guard let data, (try? data.write(to: payloadURL(item.id), options: .atomic)) != nil else { return }
        item.hasPayload = true
      }
      items.append(item)
    }
    sort()
    trim()
    save()
  }

  func delete(_ id: UUID) {
    guard let i = items.firstIndex(where: { $0.id == id }) else { return }
    removePayload(items.remove(at: i))
    save()
  }

  func togglePin(_ id: UUID) {
    guard let i = items.firstIndex(where: { $0.id == id }) else { return }
    items[i].pinned.toggle()
    sort()
    trim()
    save()
  }

  /// Clears the history. `keepPinned: false` removes everything.
  func clear(keepPinned: Bool) {
    for item in items where !(keepPinned && item.pinned) { removePayload(item) }
    items = keepPinned ? items.filter(\.pinned) : []
    save()
  }

  func filtered(_ query: String) -> [ClipItem] {
    let q = query.trimmingCharacters(in: .whitespaces)
    return q.isEmpty ? items : items.filter { $0.text.localizedCaseInsensitiveContains(q) }
  }

  private func sort() {
    items.sort { ($0.pinned ? 1 : 0, $0.date) > ($1.pinned ? 1 : 0, $1.date) }
  }

  /// Drops the oldest unpinned items beyond the limit (they sit at the end).
  private func trim() {
    var extra = items.filter { !$0.pinned }.count - limit
    while extra > 0, let last = items.last, !last.pinned {
      removePayload(items.removeLast())
      extra -= 1
    }
  }

  // MARK: Using an item

  /// Puts the item on the clipboard (and moves it to the top of the history).
  func copy(_ item: ClipItem, plainText: Bool = false) {
    ClipPasteboard.write(item, payload: payload(item), plainText: plainText, to: pasteboard)
    lastChange = pasteboard.changeCount  // our own write is not a new copy
    if let i = items.firstIndex(where: { $0.id == item.id }) {
      items[i].date = Date()
      sort()
      save()
    }
  }

  /// Copies the item and presses ⌘V in the app in front. Without Accessibility access the item
  /// stays on the clipboard and the permission guide opens.
  func paste(_ item: ClipItem, plainText: Bool = false) {
    copy(item, plainText: plainText)
    guard AXIsProcessTrusted() else {
      guide.begin(onGranted: {})
      return
    }
    // Give keyboard focus a moment to return to the app after the pop-up closes.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
      let src = CGEventSource(stateID: .combinedSessionState)
      for down in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
        e?.flags = .maskCommand
        e?.post(tap: .cghidEventTap)
      }
    }
  }

  func showPopup() { popup.show() }

  // MARK: Storage

  private var indexURL: URL { dir.appendingPathComponent("history.json") }
  private func payloadURL(_ id: UUID) -> URL { dir.appendingPathComponent("\(id.uuidString).clip") }

  func payload(_ item: ClipItem) -> [String: Data]? {
    guard item.hasPayload, let data = try? Data(contentsOf: payloadURL(item.id)) else { return nil }
    return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Data]
  }

  private func removePayload(_ item: ClipItem) {
    thumbs.removeObject(forKey: item.id as NSUUID)
    if item.hasPayload { try? FileManager.default.removeItem(at: payloadURL(item.id)) }
  }

  private func load() {
    guard let data = try? Data(contentsOf: indexURL),
      let saved = try? JSONDecoder().decode([ClipItem].self, from: data)
    else { return }
    items = saved
    sort()
  }

  private func save() {
    guard let data = try? JSONEncoder().encode(items) else { return }
    let url = indexURL
    io.async {
      try? data.write(to: url, options: .atomic)
      try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
  }

  /// Waits for pending writes.
  func flush() { io.sync {} }

  /// A small preview of an image item, decoded off the main thread and cached.
  func thumbnail(_ item: ClipItem) async -> NSImage? {
    if let hit = thumbs.object(forKey: item.id as NSUUID) { return hit }
    guard item.kind == .image, item.hasPayload else { return nil }
    let url = payloadURL(item.id)
    let cg: CGImage? = await Task.detached(priority: .userInitiated) {
      guard let data = try? Data(contentsOf: url),
        let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Data],
        let raw = dict.values.first, let src = CGImageSourceCreateWithData(raw as CFData, nil)
      else { return nil }
      let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 160,
      ]
      return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }.value
    guard let cg else { return nil }
    let image = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
    thumbs.setObject(image, forKey: item.id as NSUUID)
    return image
  }
}
