import KitbagCore
import SwiftUI

/// The "Apps" tab: Kitbag's own small apps. Clicking one opens it as a pinned popup window.
@MainActor
public final class AppLauncherTool: KitbagTool {
  public static let descriptor = ToolDescriptor(
    id: "launcher", name: "Apps", symbol: "square.grid.2x2", defaultEnabled: true,
    make: { AppLauncherTool() })

  public init() {}
  public func start() throws {}
  public func stop() {}

  public func makeMenuView() -> AnyView { AnyView(AppLauncherView()) }
}

private struct LauncherApp: Identifiable {
  let id: String
  let name: LocalizedStringKey
  let symbol: String
  let tint: Color
}

/// Home-screen style grid: a big rounded icon with its name underneath.
private struct AppLauncherView: View {
  private let apps = [
    LauncherApp(id: "dictation", name: "Dictation", symbol: "mic.fill", tint: .red),
    LauncherApp(id: "calculator", name: "Calculator", symbol: "plus.forwardslash.minus", tint: .brown),
    LauncherApp(id: "speedtest", name: "Speed Test", symbol: "arrow.up.arrow.down", tint: .orange),
    LauncherApp(
      id: "videoplayer", name: "Video Player", symbol: "play.rectangle.fill",
      tint: Color(red: 0.96, green: 0.35, blue: 0.24)),
    LauncherApp(id: "mirror", name: "Mirror", symbol: "person.crop.square", tint: .yellow),
  ]
  private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

  var body: some View {
    LazyVGrid(columns: columns, spacing: 10) {
      ForEach(apps) { app in
        Button {
          NotificationCenter.default.post(name: .kitbagOpenPopup, object: app.id)
        } label: {
          VStack(spacing: 6) {
            Image(systemName: app.symbol)
              .font(.system(size: 23, weight: .medium))
              .foregroundStyle(.white)
              .frame(width: 54, height: 54)
              .background(
                LinearGradient(
                  colors: [app.tint.opacity(0.95), app.tint.opacity(0.7)], startPoint: .top,
                  endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
              )
              .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                  .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75)
              )
              .shadow(color: app.tint.opacity(0.35), radius: 5, y: 2)
            Text(app.name)
              .font(.caption.weight(.medium))
              .lineLimit(1)
              .minimumScaleFactor(0.85)
              .foregroundStyle(.primary)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
          .contentShape(Rectangle())
          .hoverHighlight(cornerRadius: 12)
        }
        .buttonStyle(PressableStyle())
      }
    }
    .padding(.vertical, 4)
    .card(padding: 10)
  }
}
