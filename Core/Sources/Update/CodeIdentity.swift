import Foundation
import Security

/// Checks that a downloaded app really is signed by whoever signed the copy that is running now.
///
/// A signing certificate gives an app a stable identity; macOS also ties Accessibility, Screen
/// Recording and Keychain permissions to it. An ad-hoc signed app has no stable identity (its identity
/// is the hash of its own contents), so there is nothing to compare, and every update resets those permissions.
public enum CodeIdentity {
  /// The app's "designated requirement" written out, e.g. `identifier "x" and certificate leaf = H"…"`.
  public static func requirement(of app: URL) -> String? {
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return nil }
    var req: SecRequirement?
    guard SecCodeCopyDesignatedRequirement(code, [], &req) == errSecSuccess, let req else { return nil }
    var text: CFString?
    guard SecRequirementCopyString(req, [], &text) == errSecSuccess else { return nil }
    return text as String?
  }

  /// True if the requirement names a certificate, so a different signer would fail it.
  public static func isPinned(_ requirement: String?) -> Bool {
    guard let r = requirement else { return false }
    return r.contains("certificate leaf") || r.contains("anchor apple") || r.contains("certificate root")
  }

  /// Throws if the app's signature is broken, or (when `requirement` is given) is by someone else.
  public static func verify(_ app: URL, requirement: String?) throws {
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else {
      throw UpdateError.badSignature("The app couldn't be read.")
    }
    var req: SecRequirement?
    if let requirement {
      guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess else {
        throw UpdateError.badSignature("This copy of Kitbag's identity couldn't be read.")
      }
    }
    var error: Unmanaged<CFError>?
    let flags = SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode))
    let status = SecStaticCodeCheckValidityWithErrors(code, flags, req, &error)
    guard status == errSecSuccess else {
      let why = (error?.takeRetainedValue()).map { CFErrorCopyDescription($0) as String } ?? "error \(status)"
      throw UpdateError.badSignature(why)
    }
  }
}
