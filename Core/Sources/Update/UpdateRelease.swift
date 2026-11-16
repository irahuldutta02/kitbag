import Foundation

/// What the updater needs to know about a published release.
public struct UpdateRelease: Equatable, Sendable {
  public let version: AppVersion
  public let tag: String
  public let name: String
  /// The release notes, as written on GitHub (Markdown).
  public let notes: String
  public let pageURL: URL
  public let dmgURL: URL
  public let dmgName: String
  public let size: Int?
  /// A small file next to the download holding its SHA-256.
  public let checksumURL: URL?
  /// The SHA-256 GitHub itself computed for the download, if it reports one.
  public let digest: String?
  public let published: Date?

  public var versionText: String { version.description }
}

public enum UpdateError: LocalizedError, Equatable {
  case notConfigured
  case noReleases
  case rateLimited
  case network(String)
  case badRelease(String)
  case untrustedURL(String)
  case checksumMissing
  case checksumMismatch
  case badDiskImage(String)
  case wrongApp(String)
  case notNewer
  case badSignature(String)
  case cannotInstall(String)

  public var errorDescription: String? {
    switch self {
    case .notConfigured: return "Updates aren't set up for this copy of Kitbag."
    case .noReleases: return "No release has been published yet."
    case .rateLimited: return "GitHub is limiting requests right now. Try again in a little while."
    case .network(let m): return "Couldn't reach GitHub. \(m)"
    case .badRelease(let m): return "The latest release can't be used: \(m)"
    case .untrustedURL(let u): return "The update points to a place Kitbag doesn't trust (\(u))."
    case .checksumMissing: return "The release has no checksum to check the download against, so it was not installed."
    case .checksumMismatch: return "The download is damaged or has been tampered with, so it was not installed."
    case .badDiskImage(let m): return "Couldn't open the downloaded disk image. \(m)"
    case .wrongApp(let m): return "The download isn't the Kitbag app. \(m)"
    case .notNewer: return "The download isn't newer than the version you have."
    case .badSignature(let m): return "The download's signature doesn't match this copy of Kitbag, so it was not installed. \(m)"
    case .cannotInstall(let m): return m
    }
  }
}

/// Reads GitHub's "latest release" answer.
public enum ReleaseParser {
  private struct Raw: Decodable {
    struct Asset: Decodable {
      let name: String
      let browser_download_url: String
      let size: Int?
      let digest: String?
    }
    let tag_name: String
    let name: String?
    let body: String?
    let html_url: String
    let published_at: String?
    let assets: [Asset]
  }

  public static func parse(_ data: Data) throws -> UpdateRelease {
    let raw: Raw
    do { raw = try JSONDecoder().decode(Raw.self, from: data) } catch {
      throw UpdateError.badRelease("it isn't in the expected format.")
    }
    guard let version = AppVersion(raw.tag_name) else {
      throw UpdateError.badRelease("“\(raw.tag_name)” isn't a version number.")
    }
    guard let dmg = raw.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }),
      let dmgURL = URL(string: dmg.browser_download_url), let page = URL(string: raw.html_url)
    else { throw UpdateError.badRelease("it has no downloadable disk image.") }

    let wanted = [".sha256", ".sha256sum"].map { dmg.name.lowercased() + $0 }
    let sums = raw.assets.first { wanted.contains($0.name.lowercased()) }
    var digest: String?
    if let d = dmg.digest, d.lowercased().hasPrefix("sha256:") {
      let hex = String(d.dropFirst(7)).lowercased()
      if Checksum.isSHA256(hex) { digest = hex }
    }
    return UpdateRelease(
      version: version, tag: raw.tag_name, name: raw.name ?? raw.tag_name, notes: raw.body ?? "",
      pageURL: page, dmgURL: dmgURL, dmgName: dmg.name, size: dmg.size,
      checksumURL: sums.flatMap { URL(string: $0.browser_download_url) }, digest: digest,
      published: raw.published_at.flatMap { ISO8601DateFormatter().date(from: $0) })
  }
}

/// Only GitHub's own hosts, over https, are ever contacted.
public enum UpdateTrust {
  public static func isTrusted(_ url: URL) -> Bool {
    guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
    return host == "github.com" || host == "api.github.com" || host.hasSuffix(".githubusercontent.com")
  }

  /// "owner/name", nothing else: it becomes part of a URL.
  public static func isValidRepo(_ repo: String) -> Bool {
    repo.range(of: #"^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
  }

  /// A version made safe for use in a file name.
  public static func safeName(_ s: String) -> String {
    String(s.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" })
  }
}
