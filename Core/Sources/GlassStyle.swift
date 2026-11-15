import SwiftUI

/// How see-through the Liquid Glass surfaces are, for the Kitbag window and the menu popup.
/// 0 is solid and frosted, 1 is nearly clear. Saved between launches.
@MainActor
public final class GlassStyle: ObservableObject {
  public static let shared = GlassStyle()
  private static let key = "kitbag.glassTransparency"

  @Published public var transparency: Double {
    didSet { UserDefaults.standard.set(transparency, forKey: Self.key) }
  }

  private init() {
    transparency = (UserDefaults.standard.object(forKey: Self.key) as? Double) ?? 0.4
  }
}
