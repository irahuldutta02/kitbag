import CryptoKit
import Foundation

public enum Checksum {
  /// SHA-256 of a file, read in pieces so a large download never sits in memory.
  public static func sha256(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  public static func isSHA256(_ s: String) -> Bool {
    s.count == 64 && s.allSatisfy { $0.isHexDigit }
  }

  /// Reads a `.sha256` file: "<64 hex characters>  <file name>" (or just the hash).
  public static func parse(_ text: String) -> String? {
    text.split(whereSeparator: { $0.isWhitespace }).map(String.init).first(where: isSHA256)?.lowercased()
  }
}
