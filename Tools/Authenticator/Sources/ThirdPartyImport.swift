import CommonCrypto
import CryptoKit
import Foundation

/// Reading the export files of other authenticator apps.
///
/// - Proton Authenticator: JSON `{version, entries:[{id, content:{uri, entry_type, name}, note}]}`, or when
///   password-protected `{version, salt, content}` (Argon2id → AES-256-GCM, see `Proton`).
/// - 2FAS: JSON `{schemaVersion, services:[…]}`, or `servicesEncrypted` as `data:salt:iv`
///   (PBKDF2-SHA256 → AES-256-GCM, see `TwoFAS`).
/// - Google Authenticator only exports QR codes (`otpauth-migration://`), which `OTPImport` reads.
enum ThirdPartyImport {
  enum Failure: Error, Equatable {
    /// The file is a different kind of file.
    case notRecognized
    case needsPassword
    case wrongPassword
    case unsupported(String)
  }

  struct Result {
    var entries: [AuthEntry]
    /// Entries in the file that can't be used here (counter-based codes, damaged entries).
    var unusable: Int
  }

  // MARK: Proton Authenticator

  enum Proton {
    static let aad = Data("proton.authenticator.export.v1".utf8)

    static func parse(_ data: Data, password: String?) throws -> Result {
      guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        throw Failure.notRecognized
      }
      if root["entries"] == nil, root["salt"] != nil, root["content"] != nil {
        guard let password, !password.isEmpty else { throw Failure.needsPassword }
        return try parse(try decrypt(root, password: password), password: nil)
      }
      guard let list = root["entries"] as? [[String: Any]] else { throw Failure.notRecognized }
      if let v = root["version"] as? Int, v != 1 { throw Failure.unsupported("export version \(v)") }
      var out: [AuthEntry] = []
      var bad = 0
      for item in list {
        guard let content = item["content"] as? [String: Any], let uri = content["uri"] as? String,
          let e = entry(uri: uri, type: content["entry_type"] as? String, name: content["name"] as? String)
        else { bad += 1; continue }
        out.append(e)
      }
      return Result(entries: out, unusable: bad)
    }

    private static func entry(uri: String, type: String?, name: String?) -> AuthEntry? {
      let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.lowercased().hasPrefix("steam://") || type == "Steam" {
        // steam://SECRET, optionally with ?name=…
        var rest = trimmed.replacingOccurrences(of: "steam://", with: "", options: [.caseInsensitive, .anchored])
        var fallback = name
        if let q = rest.firstIndex(of: "?") {
          if let n = URLComponents(string: "x://x" + rest[q...])?.queryItems?.first(where: { $0.name == "name" })?.value {
            fallback = fallback ?? n
          }
          rest = String(rest[..<q])
        }
        guard Base32.decode(rest) != nil else { return nil }
        var e = AuthEntry()
        e.kind = .steam
        e.digits = 5
        e.period = 30
        e.algorithm = .sha1
        e.secret = Base32.normalize(rest)
        let n = (fallback ?? "").trimmingCharacters(in: .whitespaces)
        e.title = n.isEmpty ? "Steam" : n
        e.issuer = "Steam"
        return e
      }
      guard var e = OTPImport.entry(trimmed) else { return nil }
      if e.title == "Account" || e.title.isEmpty, let name, !name.isEmpty { e.title = name }
      return e
    }

    /// `{version:1, salt, content}`; the key is Argon2id(password, salt; m=19 MiB, t=2, p=1), and content is
    /// base64 of `nonce(12) ‖ ciphertext ‖ tag(16)` with AAD `proton.authenticator.export.v1`.
    private static func decrypt(_ root: [String: Any], password: String) throws -> Data {
      if let v = root["version"] as? Int, v != 1 { throw Failure.unsupported("export version \(v)") }
      guard let saltText = root["salt"] as? String, let salt = Data(base64Encoded: saltText), salt.count == 16,
        let contentText = root["content"] as? String, let combined = Data(base64Encoded: contentText),
        combined.count > 28
      else { throw Failure.notRecognized }
      guard
        let keyBytes = Argon2id.hash(
          password: Array(password.utf8), salt: Array(salt), memoryKiB: 19 * 1024, iterations: 2)
      else { throw Failure.notRecognized }
      do {
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: SymmetricKey(data: keyBytes), authenticating: aad)
      } catch {
        throw Failure.wrongPassword
      }
    }
  }

  // MARK: 2FAS

  enum TwoFAS {
    static func parse(_ data: Data, password: String?) throws -> Result {
      guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        let schema = root["schemaVersion"] as? Int
      else { throw Failure.notRecognized }
      if schema > 4 { throw Failure.unsupported("backup version \(schema)") }
      let services: [[String: Any]]
      if let sealed = root["servicesEncrypted"] as? String {
        guard let password, !password.isEmpty else { throw Failure.needsPassword }
        services = try decrypt(sealed, password: password)
      } else if let plain = root["services"] as? [[String: Any]] {
        services = plain
      } else {
        throw Failure.notRecognized
      }
      var out: [AuthEntry] = []
      var bad = 0
      for s in services {
        if let e = entry(s) { out.append(e) } else { bad += 1 }
      }
      return Result(entries: out, unusable: bad)
    }

    /// `base64(ciphertext ‖ tag) : base64(salt) : base64(iv)`; key = PBKDF2-HMAC-SHA256(password, salt, 10000).
    private static func decrypt(_ sealed: String, password: String) throws -> [[String: Any]] {
      let parts = sealed.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
      guard parts.count >= 3, let body = Data(base64Encoded: parts[0]), let salt = Data(base64Encoded: parts[1]),
        let iv = Data(base64Encoded: parts[2]), iv.count == 12, body.count > 16
      else { throw Failure.notRecognized }
      var key = [UInt8](repeating: 0, count: 32)
      let status = key.withUnsafeMutableBufferPointer { out in
        salt.withUnsafeBytes { s in
          CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2), password, password.utf8.count,
            s.bindMemory(to: UInt8.self).baseAddress, salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 10_000, out.baseAddress, 32)
        }
      }
      guard status == kCCSuccess else { throw Failure.notRecognized }
      let plain: Data
      do {
        let box = try AES.GCM.SealedBox(combined: iv + body)
        plain = try AES.GCM.open(box, using: SymmetricKey(data: key))
      } catch {
        throw Failure.wrongPassword
      }
      guard let list = (try? JSONSerialization.jsonObject(with: plain)) as? [[String: Any]] else {
        throw Failure.notRecognized
      }
      return list
    }

    private static func entry(_ s: [String: Any]) -> AuthEntry? {
      let name = (s["name"] as? String) ?? ""
      guard let otp = s["otp"] as? [String: Any] else { return nil }
      let secretText = (s["secret"] as? String) ?? ""
      func text(_ key: String) -> String { ((otp[key] as? String) ?? "").trimmingCharacters(in: .whitespaces) }
      let issuer = text("issuer").isEmpty ? name : text("issuer")
      var account = text("account")
      if account.isEmpty {
        // The label is often "Issuer:account".
        account = text("label")
        if account.hasPrefix(issuer + ":") { account = String(account.dropFirst(issuer.count + 1)) }
      }
      var e = AuthEntry()
      e.secret = Base32.normalize(secretText)
      guard e.secretData != nil else { return nil }
      e.issuer = issuer
      e.title = account.trimmingCharacters(in: .whitespaces).isEmpty ? (name.isEmpty ? "Account" : name) : account
      switch (otp["tokenType"] as? String)?.uppercased() {
      case "STEAM":
        e.kind = .steam
        e.digits = 5
        e.period = 30
      case "TOTP":
        if let d = otp["digits"] as? Int { guard (4...10).contains(d) else { return nil }; e.digits = d }
        if let p = otp["period"] as? Int { guard (1...300).contains(p) else { return nil }; e.period = p }
        if let a = otp["algorithm"] as? String {
          guard let alg = OTPAlgorithm(rawValue: a.uppercased().replacingOccurrences(of: "-", with: ""))
          else { return nil }
          e.algorithm = alg
        }
      default:
        return nil  // HOTP and anything else
      }
      return e
    }
  }

  /// Reads an export with the reader for the app it came from; the file is judged by its contents, not its name.
  static func parse(_ data: Data, as source: ImportSource, password: String?) throws -> Result {
    switch source {
    case .proton: return try Proton.parse(data, password: password)
    case .twoFAS: return try TwoFAS.parse(data, password: password)
    case .google:
      let text = String(decoding: data, as: UTF8.self)
      let found = OTPImport.parse(text)
      if found.isEmpty { throw Failure.notRecognized }
      return Result(entries: found, unusable: 0)
    }
  }
}

enum ImportSource: String, CaseIterable, Identifiable {
  case proton, twoFAS, google
  var id: String { rawValue }

  var name: String {
    switch self {
    case .proton: return "Proton Authenticator"
    case .twoFAS: return "2FAS Auth"
    case .google: return "Google Authenticator"
    }
  }

  var symbol: String {
    switch self {
    case .proton: return "shield.lefthalf.filled"
    case .twoFAS: return "2.circle.fill"
    case .google: return "g.circle.fill"
    }
  }

  /// Shown under the button: how to get the file out of the other app.
  var howTo: String {
    switch self {
    case .proton:
      return "In Proton Authenticator open Settings ▸ Export and choose a plain-text file or one protected with a password."
    case .twoFAS:
      return "In 2FAS open Settings ▸ 2FAS Backup ▸ Export to file (a .2fas file, with or without a password)."
    case .google:
      return "In Google Authenticator tap ⋮ ▸ Transfer accounts ▸ Export accounts. Scan the QR code(s) it shows with this Mac."
    }
  }
}
