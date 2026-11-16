import KitbagCore
import SwiftUI

/// Two-factor codes (TOTP and Steam Guard) in the menu bar. Accounts are kept in the Keychain.
@MainActor
public final class AuthenticatorTool: KitbagTool {
  public static let descriptor = ToolDescriptor(
    id: "authenticator", name: "Authenticator", symbol: "lock.shield.fill", make: { AuthenticatorTool() })

  private var model: AuthenticatorModel?
  public init() {}

  public func start() throws {
    let m = AuthenticatorModel()
    m.start()
    model = m
  }

  public func stop() {
    EntryEditor.close()
    model = nil
  }

  public func makeMenuView() -> AnyView {
    guard let model else { return AnyView(EmptyView()) }
    return AnyView(AuthenticatorView(model: model))
  }

  public func makeSettingsView() -> AnyView? {
    guard let model else { return nil }
    return AnyView(AuthenticatorSettingsView(model: model))
  }
}
