import Foundation
import LocalAuthentication
import Security

/// Where the accounts are kept. Production uses the Keychain; tests use a file.
protocol VaultStorage {
  func load() throws -> Data?
  /// `interactive: false` must never show a system password prompt: it throws `VaultLocked` instead.
  func load(interactive: Bool) throws -> Data?
  func save(_ data: Data) throws
}

extension VaultStorage {
  func load(interactive: Bool) throws -> Data? { try load() }
}

/// The Keychain item exists but macOS wants the user's password before handing it over
/// (typical right after the app was reinstalled or updated).
struct VaultLocked: Error {}

struct VaultError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

/// All accounts live in one Keychain item, readable only on this Mac while it is unlocked.
struct KeychainVault: VaultStorage {
  var service = "com.irahuldutta.Kitbag.authenticator"
  var account = "vault"

  private var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
  }

  private func fail(_ status: OSStatus) -> VaultError {
    let text = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
    return VaultError(message: "Keychain: \(text)")
  }

  func load() throws -> Data? { try load(interactive: true) }

  func load(interactive: Bool) throws -> Data? {
    var q = query
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    if !interactive {
      let ctx = LAContext()
      ctx.interactionNotAllowed = true
      q[kSecUseAuthenticationContext as String] = ctx
    }
    var out: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &out)
    if status == errSecItemNotFound { return nil }
    if !interactive, status == errSecInteractionNotAllowed || status == errSecAuthFailed { throw VaultLocked() }
    guard status == errSecSuccess, let data = out as? Data else { throw fail(status) }
    return data
  }

  func save(_ data: Data) throws {
    var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var add = query
      add[kSecValueData as String] = data
      add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      add[kSecAttrLabel as String] = "Kitbag Authenticator"
      status = SecItemAdd(add as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw fail(status) }
  }
}

struct FileVault: VaultStorage {
  let url: URL
  func load() throws -> Data? { try? Data(contentsOf: url) }
  func save(_ data: Data) throws { try data.write(to: url, options: .atomic) }
}
