import Foundation

/// One account. The title is the name you gave it (often the login), the issuer is the service.
struct AuthEntry: Codable, Identifiable, Equatable {
  var id = UUID()
  var title = ""
  var issuer = ""
  /// Normalized Base32 secret.
  var secret = ""
  var digits = 6
  var period = 30
  var algorithm = OTPAlgorithm.sha1
  var kind = OTPKind.totp
  var pinned = false
  var created = Date()
  /// How many times the code was copied; the most used accounts are listed first.
  var copies = 0

  enum CodingKeys: String, CodingKey {
    case id, title, issuer, secret, digits, period, algorithm, kind = "type", pinned, created, copies
  }

  var secretData: Data? { Base32.decode(secret) }
  var isValid: Bool { secretData != nil && !title.trimmingCharacters(in: .whitespaces).isEmpty }

  /// The big line in lists: the service if known, otherwise the title.
  var primary: String { issuer.isEmpty ? title : issuer }
  /// The small line: the account, when it adds something.
  var secondary: String? { issuer.isEmpty || title.caseInsensitiveCompare(issuer) == .orderedSame ? nil : title }

  func code(at date: Date = Date()) -> String {
    guard let data = secretData else { return "" }
    return OTP.code(secret: data, algorithm: algorithm, digits: digits, period: period, kind: kind, at: date)
  }

  func remaining(at date: Date = Date()) -> Double { OTP.remaining(period: period, at: date) }

  /// The code that takes over when the current one runs out.
  func nextCode(at date: Date = Date()) -> String { code(at: date.addingTimeInterval(remaining(at: date) + 0.5)) }

  /// The standard link other authenticator apps understand.
  var uri: String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: ":/?#[]@!$&'()*+,;=")
    func esc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
    let label = issuer.isEmpty ? esc(title) : esc(issuer) + ":" + esc(title)
    var q = "secret=\(secret)"
    if !issuer.isEmpty { q += "&issuer=\(esc(issuer))" }
    if kind == .totp {
      q += "&algorithm=\(algorithm.rawValue)&digits=\(digits)&period=\(period)"
    }
    return "otpauth://\(kind == .steam ? "steam" : "totp")/\(label)?\(q)"
  }

  func sameAccount(as other: AuthEntry) -> Bool {
    Base32.normalize(secret) == Base32.normalize(other.secret)
  }
}

extension AuthEntry {
  /// Tolerant of missing fields, so older vaults and other tools' files still load.
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init()
    id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
    title = try c.decode(String.self, forKey: .title)
    issuer = (try? c.decode(String.self, forKey: .issuer)) ?? ""
    secret = Base32.normalize(try c.decode(String.self, forKey: .secret))
    digits = (try? c.decode(Int.self, forKey: .digits)) ?? 6
    period = (try? c.decode(Int.self, forKey: .period)) ?? 30
    algorithm = (try? c.decode(OTPAlgorithm.self, forKey: .algorithm)) ?? .sha1
    kind = (try? c.decode(OTPKind.self, forKey: .kind)) ?? .totp
    pinned = (try? c.decode(Bool.self, forKey: .pinned)) ?? false
    created = (try? c.decode(Date.self, forKey: .created)) ?? Date()
    copies = (try? c.decode(Int.self, forKey: .copies)) ?? 0
  }
}
