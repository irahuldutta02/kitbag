import Foundation

/// Turns what a QR code or a pasted link says into accounts: `otpauth://` links, and the
/// `otpauth-migration://` export of Google Authenticator (which holds many accounts at once).
enum OTPImport {
  static func parse(_ text: String) -> [AuthEntry] {
    text.split(whereSeparator: \.isNewline).flatMap { line -> [AuthEntry] in
      let s = line.trimmingCharacters(in: .whitespaces)
      if s.hasPrefix("otpauth-migration://") { return migration(s) }
      if s.hasPrefix("otpauth://") { return entry(s).map { [$0] } ?? [] }
      return []
    }
  }

  static func entry(_ link: String) -> AuthEntry? {
    guard
      let c = URLComponents(string: link)
        ?? URLComponents(string: link.replacingOccurrences(of: " ", with: "%20")),
      c.scheme == "otpauth"
    else { return nil }
    let kind: OTPKind
    switch c.host?.lowercased() {
    case "totp": kind = .totp
    case "steam": kind = .steam
    default: return nil  // counter-based (HOTP) codes aren't supported
    }
    var q: [String: String] = [:]
    for item in c.queryItems ?? [] { q[item.name.lowercased()] = item.value ?? "" }
    guard let rawSecret = q["secret"], Base32.decode(rawSecret) != nil else { return nil }

    var label = c.path
    if label.hasPrefix("/") { label.removeFirst() }
    var prefix: String?
    if let named = q["issuer"], !named.isEmpty, label.hasPrefix(named + ":") {
      // The issuer itself may contain a colon, so trust it over splitting the label.
      prefix = named
      label = String(label.dropFirst(named.count + 1))
    } else if let i = label.firstIndex(of: ":") {
      prefix = String(label[..<i]).trimmingCharacters(in: .whitespaces)
      label = String(label[label.index(after: i)...])
    }
    label = label.trimmingCharacters(in: .whitespaces)
    let issuer = [q["issuer"], prefix].compactMap { $0 }.first { !$0.isEmpty } ?? ""

    var e = AuthEntry()
    e.kind = kind
    e.secret = Base32.normalize(rawSecret)
    e.issuer = issuer
    e.title = label.isEmpty ? issuer : label
    if e.title.isEmpty { e.title = "Account" }
    if kind == .steam {
      e.digits = 5
      e.period = 30
      return e
    }
    if let a = q["algorithm"] {
      guard let alg = OTPAlgorithm(rawValue: a.uppercased().replacingOccurrences(of: "-", with: ""))
      else { return nil }
      e.algorithm = alg
    }
    if let d = q["digits"].flatMap(Int.init), (6...8).contains(d) { e.digits = d }
    if let p = q["period"].flatMap(Int.init), (1...300).contains(p) { e.period = p }
    return e
  }

  // MARK: Google Authenticator export (a small protobuf)

  static func migration(_ link: String) -> [AuthEntry] {
    guard let c = URLComponents(string: link),
      var b64 = c.queryItems?.first(where: { $0.name == "data" })?.value
    else { return [] }
    b64 = b64.replacingOccurrences(of: " ", with: "+").replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    while b64.count % 4 != 0 { b64 += "=" }
    guard let data = Data(base64Encoded: b64) else { return [] }
    var reader = ProtoReader(data)
    var out: [AuthEntry] = []
    while let (field, wire) = reader.nextTag() {
      if field == 1, wire == 2, let sub = reader.lengthDelimited() {
        if let e = migrationAccount(sub) { out.append(e) }
      } else if !reader.skip(wire) {
        break
      }
    }
    return out
  }

  private static func migrationAccount(_ data: Data) -> AuthEntry? {
    var r = ProtoReader(data)
    var secret = Data()
    var name = "", issuer = ""
    var algorithm = 1, digits = 1, type = 2
    while let (field, wire) = r.nextTag() {
      switch (field, wire) {
      case (1, 2): secret = r.lengthDelimited() ?? Data()
      case (2, 2): name = r.lengthDelimited().map { String(decoding: $0, as: UTF8.self) } ?? ""
      case (3, 2): issuer = r.lengthDelimited().map { String(decoding: $0, as: UTF8.self) } ?? ""
      case (4, 0): algorithm = Int(r.varint() ?? 1)
      case (5, 0): digits = Int(r.varint() ?? 1)
      case (6, 0): type = Int(r.varint() ?? 2)
      default: if !r.skip(wire) { return nil }
      }
    }
    guard !secret.isEmpty, type != 1 else { return nil }  // 1 = counter-based
    var e = AuthEntry()
    switch algorithm {
    case 0, 1: e.algorithm = .sha1
    case 2: e.algorithm = .sha256
    case 3: e.algorithm = .sha512
    default: return nil  // MD5
    }
    e.digits = digits == 2 ? 8 : 6
    e.secret = Base32.encode(secret)
    if let i = name.firstIndex(of: ":") {
      if issuer.isEmpty { issuer = String(name[..<i]).trimmingCharacters(in: .whitespaces) }
      name = String(name[name.index(after: i)...]).trimmingCharacters(in: .whitespaces)
    }
    e.issuer = issuer
    e.title = name.isEmpty ? (issuer.isEmpty ? "Account" : issuer) : name
    return e
  }
}

/// Just enough of Protocol Buffers to read the export.
struct ProtoReader {
  private let bytes: [UInt8]
  private var pos = 0
  init(_ data: Data) { bytes = Array(data) }

  mutating func varint() -> UInt64? {
    var result: UInt64 = 0
    var shift: UInt64 = 0
    while pos < bytes.count, shift < 64 {
      let b = bytes[pos]
      pos += 1
      result |= UInt64(b & 0x7F) << shift
      if b & 0x80 == 0 { return result }
      shift += 7
    }
    return nil
  }

  mutating func nextTag() -> (field: Int, wire: Int)? {
    guard pos < bytes.count, let t = varint() else { return nil }
    return (Int(t >> 3), Int(t & 7))
  }

  mutating func lengthDelimited() -> Data? {
    guard let n = varint(), n <= UInt64(bytes.count - pos) else { return nil }
    defer { pos += Int(n) }
    return Data(bytes[pos..<pos + Int(n)])
  }

  mutating func skip(_ wire: Int) -> Bool {
    switch wire {
    case 0: return varint() != nil
    case 1: pos += 8
    case 2: return lengthDelimited() != nil
    case 5: pos += 4
    default: return false
    }
    return pos <= bytes.count
  }
}
