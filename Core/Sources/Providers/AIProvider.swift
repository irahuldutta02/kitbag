import Foundation
import SwiftUI

/// The AI command line tools Kitbag can talk to.
public enum AIProviderID: String, CaseIterable, Identifiable, Sendable {
  case codex, claude, antigravity

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .codex: return "Codex"
    case .claude: return "Claude"
    case .antigravity: return "Antigravity"
    }
  }

  public var binaryName: String {
    switch self {
    case .codex: return "codex"
    case .claude: return "claude"
    case .antigravity: return "agy"
    }
  }

  public var symbol: String {
    switch self {
    case .codex: return "chevron.left.forwardslash.chevron.right"
    case .claude: return "sparkle"
    case .antigravity: return "arrow.up.forward.circle.fill"
    }
  }

  public var accent: Color {
    switch self {
    case .codex: return .green
    case .claude: return .orange
    case .antigravity: return .blue
    }
  }

  public var installCommand: String? {
    switch self {
    case .claude: return "curl -fsSL https://claude.ai/install.sh | bash"
    case .antigravity: return "curl -fsSL https://antigravity.google/cli/install.sh | bash"
    case .codex: return nil  // Homebrew or npm
    }
  }

  /// Folders searched for the binary (GUI apps start with a bare PATH).
  public static func searchDirs(home: String = NSHomeDirectory()) -> [String] {
    var dirs = [
      home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", home + "/.claude/local",
      home + "/.codex/packages/standalone/current/bin", home + "/.npm-global/bin",
      home + "/.bun/bin",
    ]
    let nvm = home + "/.nvm/versions/node"
    if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm) {
      dirs += versions.sorted(by: >).map { nvm + "/" + $0 + "/bin" }
    }
    return dirs
  }
}

/// What Kitbag knows about one provider right now.
public struct ProviderState: Equatable, Sendable {
  public var installed = false
  public var binaryPath: String?
  public var version: String?
  public var authenticated = false
  public var authSummary = "Not installed"
  public var accountDetail: String?
  public var busyAction: String?
  public var error: String?

  public init() {}
}

/// The result of reading a provider's sign-in status.
public struct AuthParse: Equatable, Sendable {
  public var authenticated: Bool
  public var summary: String
  public var detail: String?

  public init(authenticated: Bool, summary: String, detail: String? = nil) {
    self.authenticated = authenticated
    self.summary = summary
    self.detail = detail
  }
}
