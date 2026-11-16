import Foundation

/// A version such as "1.10.2" or "v1.2.0-beta". Numbers compare as numbers (1.10 is newer than 1.9),
/// missing parts count as zero (1.2 equals 1.2.0), and a "-beta" style suffix ranks below the plain release.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
  public let parts: [Int]
  public let suffix: String

  public init?(_ text: String) {
    var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.lowercased().hasPrefix("v") { t.removeFirst() }
    if let plus = t.firstIndex(of: "+") { t = String(t[..<plus]) }  // build metadata doesn't count
    let halves = t.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    guard let main = halves.first, !main.isEmpty else { return nil }
    let numbers = main.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
    guard numbers.allSatisfy({ $0 != nil }) else { return nil }
    parts = numbers.compactMap { $0 }
    suffix = halves.count > 1 ? String(halves[1]) : ""
  }

  public var description: String {
    parts.map(String.init).joined(separator: ".") + (suffix.isEmpty ? "" : "-" + suffix)
  }

  private func padded(_ n: Int) -> [Int] { parts + Array(repeating: 0, count: max(0, n - parts.count)) }

  public static func == (a: AppVersion, b: AppVersion) -> Bool {
    let n = max(a.parts.count, b.parts.count)
    return a.padded(n) == b.padded(n) && a.suffix == b.suffix
  }

  public static func < (a: AppVersion, b: AppVersion) -> Bool {
    let n = max(a.parts.count, b.parts.count)
    let x = a.padded(n), y = b.padded(n)
    if x != y { return x.lexicographicallyPrecedes(y) }
    if a.suffix == b.suffix { return false }
    if a.suffix.isEmpty { return false }  // the release is newer than its beta
    if b.suffix.isEmpty { return true }
    return a.suffix < b.suffix
  }
}
