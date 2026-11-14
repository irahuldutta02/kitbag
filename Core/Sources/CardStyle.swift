import SwiftUI

/// Liquid Glass where macOS has it, a soft material fill before that.
private struct GlassBackground<S: InsettableShape>: ViewModifier {
  let shape: S
  let interactive: Bool

  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
    } else {
      content.background(.quaternary.opacity(0.6), in: shape)
    }
  }
}

/// Springy press feedback shared by every tappable control.
public struct PressableStyle: ButtonStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.95 : 1)
      .opacity(configuration.isPressed ? 0.85 : 1)
      .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
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
