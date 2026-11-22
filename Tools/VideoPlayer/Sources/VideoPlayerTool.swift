import KitbagCore
import SwiftUI

/// Local browser video player: plays MKV/MP4/MOV/HEVC files in your chosen browser with
/// audio track selection, subtitles, hardware transcoding, and live-synced Liquid Glass styling.
@MainActor
public final class VideoPlayerTool: KitbagTool {
  public static let descriptor = ToolDescriptor(
    id: "videoplayer",
    name: "Video Player",
    symbol: "play.rectangle.fill",
    make: { VideoPlayerTool() }
  )

  private var model: VideoPlayerModel?
  public init() {}

  public func start() throws {
    let m = VideoPlayerModel()
    m.start()
    model = m
  }

  public func stop() {
    model?.stop()
    model = nil
  }

  public func menuVisibilityChanged(_ visible: Bool) {
    if visible { model?.refresh() }
  }

  public func makeMenuView() -> AnyView {
    guard let model else { return AnyView(EmptyView()) }
    return AnyView(VideoPlayerMenuView(model: model))
  }

  public func makeSettingsView() -> AnyView? {
    guard let model else { return nil }
    return AnyView(VideoPlayerSettingsView(model: model, settings: model.settings))
  }
}
