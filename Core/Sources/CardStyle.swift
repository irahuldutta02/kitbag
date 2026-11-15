import SwiftUI

/// Liquid Glass where macOS has it, a soft material fill before that. How see-through it is comes
/// from the "Liquid Glass" slider in Settings.
private struct GlassBackground<S: InsettableShape>: ViewModifier {
  let shape: S
  let interactive: Bool
  @ObservedObject private var style = GlassStyle.shared

  func body(content: Content) -> some View {
    let t = style.transparency
    if #available(macOS 26.0, *) {
      let glass: Glass = t > 0.7 ? .clear : .regular
      content
        .background(Color.black.opacity((1 - t) * 0.4), in: shape)  // darkens toward solid
        .glassEffect(glass, in: shape)  // static glass: the interactive variant shimmers on hover
    } else {
      content.background(.regularMaterial.opacity(1 - t * 0.7), in: shape)
    }
  }
}

/// Press feedback shared by every tappable control: a quick dim, nothing moves.
public struct PressableStyle: ButtonStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.7 : 1)  // plain press feedback, no bounce
  }
}

extension View {
  /// Glass (or material) behind this view, in the given shape.
  public func glass<S: InsettableShape>(_ shape: S, interactive: Bool = false) -> some View {
    modifier(GlassBackground(shape: shape, interactive: interactive))
  }

  /// Rounded glass container shared by all tools.
  public func card() -> some View {
    padding(10).glass(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  public func pressable() -> some View { buttonStyle(PressableStyle()) }
}
