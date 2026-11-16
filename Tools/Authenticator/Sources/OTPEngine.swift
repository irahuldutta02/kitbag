import CryptoKit
import Foundation

enum OTPAlgorithm: String, Codable, CaseIterable, Identifiable {
  case sha1 = "SHA1", sha256 = "SHA256", sha512 = "SHA512"
  var id: String { rawValue }
}

enum OTPKind: String, Codable, CaseIterable, Identifiable {
  case totp = "TOTP", steam = "STEAM"
  var id: String { rawValue }
}

/// RFC 4648 Base32, the format authenticator secrets are written in.
enum Base32 {
  private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

  /// Upper case, without the spaces, dashes and padding people copy along with a secret.
  static func normalize(_ s: String) -> String {
    String(s.uppercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "=" })
  }

  static func decode(_ s: String) -> Data? {
    let clean = normalize(s)
    guard !clean.isEmpty else { return nil }
    var out = Data()
    var bits = 0
    var value = 0
    for ch in clean {
      guard let i = alphabet.firstIndex(of: ch) else { return nil }
      value = (value << 5) | i
      bits += 5
      if bits >= 8 {
        bits -= 8
        out.append(UInt8((value >> bits) & 0xFF))
        value &= (1 << bits) - 1
      }
    }
    return out.isEmpty ? nil : out
  }

  static func encode(_ data: Data) -> String {
    var out = ""
    var bits = 0
    var value = 0
    for byte in data {
      value = (value << 8) | Int(byte)
      bits += 8
      while bits >= 5 {
        bits -= 5
        out.append(alphabet[(value >> bits) & 31])
        value &= (1 << bits) - 1
      }
    }
    if bits > 0 { out.append(alphabet[(value << (5 - bits)) & 31]) }
    return out
  }
}

/// One-time codes: TOTP (RFC 6238) and Steam Guard.
enum OTP {
  static let steamAlphabet = Array("23456789BCDFGHJKMNPQRTVWXY")

  static func code(
    secret: Data, algorithm: OTPAlgorithm, digits: Int, period: Int, kind: OTPKind, at date: Date
  ) -> String {
    let step = max(period, 1)
    let counter = UInt64(max(0, (date.timeIntervalSince1970 / Double(step)).rounded(.down)))
    let mac = hmac(secret, counter, algorithm)
    let o = Int(mac[mac.count - 1] & 0x0F)
    var bin =
      (UInt64(mac[o] & 0x7F) << 24) | (UInt64(mac[o + 1]) << 16) | (UInt64(mac[o + 2]) << 8)
      | UInt64(mac[o + 3])
    if kind == .steam {
      var s = ""
      for _ in 0..<5 {
        s.append(steamAlphabet[Int(bin % 26)])
        bin /= 26
      }
      return s
    }
    let n = min(max(digits, 4), 10)
    var mod: UInt64 = 1
    for _ in 0..<n { mod *= 10 }
    let text = String(bin % mod)
    return String(repeating: "0", count: n - text.count) + text
  }

  private static func hmac(_ key: Data, _ counter: UInt64, _ algorithm: OTPAlgorithm) -> [UInt8] {
    var c = counter.bigEndian
    let message = withUnsafeBytes(of: &c) { Data($0) }
    let k = SymmetricKey(data: key)
    switch algorithm {
    case .sha1: return Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: k))
    case .sha256: return Array(HMAC<SHA256>.authenticationCode(for: message, using: k))
    case .sha512: return Array(HMAC<SHA512>.authenticationCode(for: message, using: k))
    }
  }

  /// Seconds until the current code changes.
  static func remaining(period: Int, at date: Date) -> Double {
    let p = Double(max(period, 1))
    return p - date.timeIntervalSince1970.truncatingRemainder(dividingBy: p)
  }

  /// "123456" -> "123 456", "12345678" -> "1234 5678"; Steam codes stay whole.
  static func grouped(_ code: String, kind: OTPKind) -> String {
    guard kind == .totp, code.count >= 6 else { return code }
    let split = code.count == 8 ? 4 : 3
    return code.prefix(split) + " " + code.dropFirst(split)
  }
}
