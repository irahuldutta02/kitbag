import KitbagCore
import SwiftUI

struct SpeedTestView: View {
  @ObservedObject var model: SpeedTestModel

  var body: some View {
    VStack(spacing: 10) {
      HStack(spacing: 8) {
        Tile(
          title: "Download", symbol: "arrow.down.circle.fill", tint: .green,
          value: model.phase == .download ? model.live : model.download, unit: "Mbps",
          active: model.phase == .download)
        Tile(
          title: "Upload", symbol: "arrow.up.circle.fill", tint: .orange,
          value: model.phase == .upload ? model.live : model.upload, unit: "Mbps",
          active: model.phase == .upload)
      }
      HStack {
        Label("Latency", systemImage: "timer").font(.subheadline)
        Spacer()
        Text(model.ping.map { String(format: "%.0f ms", $0) } ?? "–")
          .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
      }
      .card()

      Button {
        model.isRunning ? model.cancel() : model.start()
      } label: {
        Label(
          model.isRunning ? "Stop" : (model.phase == .idle ? "Start Test" : "Test Again"),
          systemImage: model.isRunning ? "stop.fill" : "play.fill"
        )
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)

      Text(status).font(.caption).foregroundStyle(model.phase == .failed ? .red : .secondary)
    }
  }

  private var status: LocalizedStringKey {
    switch model.phase {
    case .idle:
      return "Measures against Cloudflare's speed test servers. Runs only when you start it."
    case .ping: return "Measuring latency…"
    case .download: return "Measuring download…"
    case .upload: return "Measuring upload…"
    case .done: return "Done. Results are approximate."
    case .failed: return "Couldn't reach the speed test server."
    }
  }
}

private struct Tile: View {
  let title: LocalizedStringKey
  let symbol: String
  let tint: Color
  let value: Double?
  let unit: LocalizedStringKey
  let active: Bool

  var body: some View {
    VStack(spacing: 2) {
      Label(title, systemImage: symbol).font(.caption.bold()).foregroundStyle(tint, .primary)
      Text(value.map { $0 < 100 ? String(format: "%.1f", $0) : String(format: "%.0f", $0) } ?? "–")
        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
      Text(unit).font(.caption2).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .card()
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint, lineWidth: active ? 1.5 : 0))
    .accessibilityElement(children: .combine)
  }
}
