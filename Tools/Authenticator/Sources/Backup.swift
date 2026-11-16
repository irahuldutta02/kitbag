import Foundation

/// The backup file: readable JSON with every account's secret, plus the standard `otpauth://`
/// link for each, so the file can also be imported by other authenticator apps.
struct BackupFile: Codable {
  var app = "Kitbag Authenticator"
  var version = 1
  var exportedAt = Date()
  var entries: [BackupEntry] = []

  init(entries: [BackupEntry]) { self.entries = entries }

  /// Only the list is required, so hand-made files and other tools' exports still restore.
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    app = (try? c.decode(String.self, forKey: .app)) ?? app
    version = (try? c.decode(Int.self, forKey: .version)) ?? 1
    exportedAt = (try? c.decode(Date.self, forKey: .exportedAt)) ?? Date()
    entries = try c.decode([BackupEntry].self, forKey: .entries)
  }
}

struct BackupEntry: Codable {
  var id: UUID?
  var title: String
  var issuer: String?
  var secret: String
  var type: String?
  var algorithm: String?
  var digits: Int?
  var period: Int?
  var pinned: Bool?
  var createdAt: Date?
  var uri: String?

  init(_ e: AuthEntry) {
    id = e.id
    title = e.title
    issuer = e.issuer
    secret = e.secret
    type = e.kind.rawValue
    algorithm = e.algorithm.rawValue
    digits = e.digits
    period = e.period
    pinned = e.pinned
    createdAt = e.created
    uri = e.uri
  }

  /// nil if the secret isn't usable.
  func entry() -> AuthEntry? {
    var e = AuthEntry()
    e.id = id ?? UUID()
    e.title = title
    e.issuer = issuer ?? ""
    e.secret = Base32.normalize(secret)
    e.kind = type.flatMap { OTPKind(rawValue: $0.uppercased()) } ?? .totp
    e.algorithm = algorithm.flatMap { OTPAlgorithm(rawValue: $0.uppercased()) } ?? .sha1
    e.digits = digits.flatMap { (4...10).contains($0) ? $0 : nil } ?? (e.kind == .steam ? 5 : 6)
    e.period = period.flatMap { (1...300).contains($0) ? $0 : nil } ?? 30
    e.pinned = pinned ?? false
    e.created = createdAt ?? Date()
    if e.title.trimmingCharacters(in: .whitespaces).isEmpty { e.title = e.issuer.isEmpty ? "Account" : e.issuer }
    return e.secretData == nil ? nil : e
  }
}

struct RestoreSummary: Equatable {
  var added = 0
  var skipped = 0  // already in the app
  var invalid = 0
  /// False if the file wasn't a backup at all.
  var recognized = true
}

enum Backup {
  static func makeEncoder() -> JSONEncoder {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    e.dateEncodingStrategy = .iso8601
    return e
  }

  static func makeDecoder() -> JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
  }

  static func encode(_ entries: [AuthEntry]) throws -> Data {
    try makeEncoder().encode(BackupFile(entries: entries.map(BackupEntry.init)))
  }

  /// Accepts this app's backup, a bare list of accounts, or text containing `otpauth://` links.
  /// Returns the usable accounts and how many entries were unusable; nil if not recognized.
  static func decode(_ data: Data) -> (entries: [AuthEntry], invalid: Int)? {
    let d = makeDecoder()
    if let file = try? d.decode(BackupFile.self, from: data) { return convert(file.entries) }
    if let list = try? d.decode([BackupEntry].self, from: data) { return convert(list) }
    if let text = String(data: data, encoding: .utf8) {
      let found = OTPImport.parse(text)
      if !found.isEmpty { return (found, 0) }
    }
    return nil
  }

  private static func convert(_ list: [BackupEntry]) -> (entries: [AuthEntry], invalid: Int) {
    let converted = list.compactMap { $0.entry() }
    return (converted, list.count - converted.count)
  }
}
