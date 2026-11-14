import KitbagCore
import SwiftUI

@MainActor
public final class AudioTool: KitbagTool {
  public static let descriptor = ToolDescriptor(
    id: "audio", name: "Audio", symbol: "speaker.wave.2.fill", make: { AudioTool() })

  private var model: AudioModel?
  public init() {}

  public func start() throws { model = AudioModel() }

  public func stop() {
    model?.setActive(false)
    model = nil
  }

  /// Polls only while the tab is showing; leaving it clears everything.
  public func menuVisibilityChanged(_ visible: Bool) { model?.setActive(visible) }

  public func makeMenuView() -> AnyView {
    guard let model else { return AnyView(EmptyView()) }
    return AnyView(AudioView(model: model))
  }
}
