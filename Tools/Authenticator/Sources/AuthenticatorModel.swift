import AppKit
import Carbon.HIToolbox
import KitbagCore

/// The list of accounts: kept in the Keychain, searchable, with codes copied to the clipboard
/// in a way clipboard histories ignore.
@MainActor
final class AuthenticatorModel: ObservableObject {
  enum AddOutcome: Equatable { case added, duplicate, failed }

  @Published private(set) var entries: [AuthEntry] = []
  @Published private(set) var storageError: String?
  /// True while the accounts haven't been read from the Keychain yet. After a reinstall macOS asks for
  /// the Mac password on the first read, so that read waits until the user opens this tab and asks for it.
  @Published private(set) var locked = false
  /// The account whose code was just copied (for the "Copied" badge).
  @Published private(set) var copiedID: UUID?
  /// What the "Copied" badge says it copied: the next code rather than the current one.
  @Published private(set) var copiedNext = false
  /// The code that is on the clipboard, shown in the confirmation.
  @Published private(set) var copiedCode = ""
  @Published var clearAfterCopy: Bool { didSet { defaults.set(clearAfterCopy, forKey: Self.clearKey) } }
  @Published private(set) var lastBackup: Date?
  /// Accounts changed since the last backup.
  @Published private(set) var needsBackup: Bool

  /// The key combination that opens the Authenticator tab anywhere; `nil` when turned off.
  @Published private(set) var shortcut: KeyShortcut?
  /// False if another app already owns the shortcut.
  @Published private(set) var shortcutWorks = true

  static let defaultShortcut = KeyShortcut(
    keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey | optionKey), label: "A")
  private static let shortcutPrefix = "kitbag.auth.shortcut"
  private let hotKey = GlobalHotKey()
  private var hotKeyEnabled = false

  private static let clearKey = "kitbag.auth.clearAfterCopy"
  private static let backupKey = "kitbag.auth.lastBackup"
  private static let dirtyKey = "kitbag.auth.dirty"
  static let clipboardClearDelay: TimeInterval = 30
  static let copiedBadgeTime: TimeInterval = 1.6

  private let storage: VaultStorage
  private let defaults: UserDefaults
  private let pasteboard: NSPasteboard
  /// Only true once the vault was read successfully: never overwrite something we couldn't read.
  private var loaded = false
  /// Copy counts as they were when the tab was last opened. The list is sorted by these, so
  /// copying a code doesn't make the list jump; the new order shows the next time it opens.
  private var rankedCopies: [UUID: Int] = [:]
  var scanning = false

  init(storage: VaultStorage = KeychainVault(), defaults: UserDefaults = .standard, pasteboard: NSPasteboard = .general) {
    self.storage = storage
    self.defaults = defaults
    self.pasteboard = pasteboard
    clearAfterCopy = (defaults.object(forKey: Self.clearKey) as? Bool) ?? true
    lastBackup = defaults.object(forKey: Self.backupKey) as? Date
    needsBackup = defaults.bool(forKey: Self.dirtyKey)
    shortcut = KeyShortcut.load(from: defaults, prefix: Self.shortcutPrefix, default: Self.defaultShortcut)
  }

  /// `registerHotKey: false` skips the global shortcut (tests).
  func start(registerHotKey: Bool = true, readVault: Bool = true) {
    if registerHotKey {
      hotKeyEnabled = true
      hotKey.onPress = {
        NotificationCenter.default.post(name: .kitbagOpenTab, object: "authenticator")
      }
      registerShortcut()
    }
    // Reading the Keychain here would pop up a password prompt at launch (e.g. right after an update).
    if readVault { unlock(interactive: true) } else { locked = true }
  }

  /// Reads the accounts. With `interactive: false` it never shows a password prompt and just stays
  /// locked if macOS would ask for one; with `true` the system prompt may appear.
  func unlock(interactive: Bool) {
    guard !loaded else { return }
    do {
      if let data = try storage.load(interactive: interactive) {
        entries = try Backup.makeDecoder().decode([AuthEntry].self, from: data)
      }
      loaded = true
      locked = false
      storageError = nil
      refreshOrder()
    } catch is VaultLocked {
      locked = true
    } catch {
      loaded = false
      locked = true
      storageError = "Couldn't open your accounts. \(error.localizedDescription)"
    }
  }

  func stop() {
    hotKey.unregister()
    hotKeyEnabled = false
  }

  // MARK: Shortcut

  private func registerShortcut() {
    guard let s = shortcut else {
      hotKey.unregister()
      shortcutWorks = true
      return
    }
    shortcutWorks = hotKey.register(keyCode: s.keyCode, modifiers: s.modifiers)
  }

  /// Switches to a new shortcut (or turns it off with `nil`). If another app already owns it,
  /// the old one stays and this returns false.
  @discardableResult
  func setShortcut(_ new: KeyShortcut?) -> Bool {
    if hotKeyEnabled, let new {
      guard hotKey.register(keyCode: new.keyCode, modifiers: new.modifiers) else {
        if let old = shortcut { hotKey.register(keyCode: old.keyCode, modifiers: old.modifiers) }
        return false
      }
    } else if hotKeyEnabled {
      hotKey.unregister()
    }
    shortcut = new
    shortcutWorks = true
    KeyShortcut.save(new, to: defaults, prefix: Self.shortcutPrefix)
    return true
  }

  /// While a new shortcut is being typed, the current one must not fire.
  func pauseHotKey(_ pause: Bool) {
    guard hotKeyEnabled else { return }
    if pause { hotKey.unregister() } else { registerShortcut() }
  }

  // MARK: Reading

  /// Pinned first, then by name. The search looks at the service and the title.
  func filtered(_ query: String) -> [AuthEntry] {
    let q = query.trimmingCharacters(in: .whitespaces)
    let list = q.isEmpty ? entries : entries.filter {
      $0.title.localizedCaseInsensitiveContains(q) || $0.issuer.localizedCaseInsensitiveContains(q)
    }
    return list.sorted {
      if $0.pinned != $1.pinned { return $0.pinned }
      let a = rankedCopies[$0.id] ?? 0, b = rankedCopies[$1.id] ?? 0
      if a != b { return a > b }
      let order = $0.primary.localizedCaseInsensitiveCompare($1.primary)
      return order == .orderedSame
        ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending : order == .orderedAscending
    }
  }

  /// Applies the latest copy counts to the order. Called when the tab opens.
  func refreshOrder() {
    rankedCopies = Dictionary(entries.map { ($0.id, $0.copies) }, uniquingKeysWith: { a, _ in a })
    objectWillChange.send()
  }

  func entry(_ id: UUID) -> AuthEntry? { entries.first { $0.id == id } }

  // MARK: Changing

  @discardableResult
  func add(_ e: AuthEntry) -> AddOutcome {
    importEntries([e]).added == 1 ? .added : (loaded ? .duplicate : .failed)
  }

  /// Adds what isn't there yet (same secret = same account) in one save.
  func importEntries(_ list: [AuthEntry]) -> (added: Int, skipped: Int) {
    guard loaded else { return (0, list.count) }
    var next = entries
    var added = 0
    for var e in list where e.isValid {
      if next.contains(where: { $0.sameAccount(as: e) }) { continue }
      e.secret = Base32.normalize(e.secret)
      if next.contains(where: { $0.id == e.id }) { e.id = UUID() }
      next.append(e)
      added += 1
    }
    if added > 0, !commit(next) { return (0, list.count) }
    return (added, list.count - added)
  }

  @discardableResult
  func update(_ e: AuthEntry) -> Bool {
    guard let i = entries.firstIndex(where: { $0.id == e.id }) else { return false }
    var next = entries
    next[i] = e
    next[i].secret = Base32.normalize(e.secret)
    return commit(next)
  }

  func delete(_ id: UUID) { commit(entries.filter { $0.id != id }) }
  func removeAll() { commit([]) }

  func togglePin(_ id: UUID) {
    guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
    var next = entries
    next[i].pinned.toggle()
    commit(next)
  }

  /// Saves first, and only then shows the change, so the screen never claims more than is stored.
  @discardableResult
  private func commit(_ next: [AuthEntry]) -> Bool {
    guard loaded else {
      storageError = storageError ?? "Your accounts aren't available, so nothing was changed."
      return false
    }
    do {
      try storage.save(try Backup.makeEncoder().encode(next))
    } catch {
      storageError = "Couldn't save. \(error.localizedDescription)"
      return false
    }
    entries = next
    storageError = nil
    needsBackup = true
    defaults.set(true, forKey: Self.dirtyKey)
    return true
  }

  // MARK: Copying

  func copyCode(_ e: AuthEntry, at date: Date = Date()) { put(e.code(at: date), for: e, next: false) }

  /// The code that takes over when the current one runs out, for pasting just after it changes.
  func copyNextCode(_ e: AuthEntry, at date: Date = Date()) { put(e.nextCode(at: date), for: e, next: true) }

  private func put(_ code: String, for e: AuthEntry, next: Bool) {
    pasteboard.clearContents()
    pasteboard.setString(code, forType: .string)
    // The marker clipboard histories (including Kitbag's own) use to skip passwords.
    pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
    let change = pasteboard.changeCount
    countCopy(e.id)
    copiedID = e.id
    copiedNext = next
    copiedCode = code
    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)  // a light tap on a trackpad
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.copiedBadgeTime) { [weak self] in
      if self?.copiedID == e.id { self?.copiedID = nil }
    }
    if clearAfterCopy {
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.clipboardClearDelay) { [weak self] in
        guard let pb = self?.pasteboard, pb.changeCount == change else { return }  // something else was copied since
        pb.clearContents()
      }
    }
  }

  /// Counts a copy and saves it quietly: it doesn't re-sort the list or count as a change to back up.
  private func countCopy(_ id: UUID) {
    guard loaded, let i = entries.firstIndex(where: { $0.id == id }) else { return }
    var next = entries
    next[i].copies += 1
    guard let data = try? Backup.makeEncoder().encode(next), (try? storage.save(data)) != nil else { return }
    entries = next
  }

  // MARK: Backup

  func exportBackup() throws -> Data { try Backup.encode(entries) }

  func markBackedUp(at date: Date = Date()) {
    lastBackup = date
    needsBackup = false
    defaults.set(date, forKey: Self.backupKey)
    defaults.set(false, forKey: Self.dirtyKey)
  }

  /// Merges a backup into the current accounts; nothing is removed or replaced.
  func restore(from data: Data) -> RestoreSummary {
    guard let (list, invalid) = Backup.decode(data) else { return RestoreSummary(recognized: false) }
    let r = importEntries(list)
    return RestoreSummary(added: r.added, skipped: r.skipped, invalid: invalid)
  }
}
