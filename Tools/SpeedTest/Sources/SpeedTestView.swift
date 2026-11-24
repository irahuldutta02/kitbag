import AppKit
import KitbagCore
import SwiftUI

struct SpeedTestView: View {
  @ObservedObject var model: SpeedTestModel
  @StateObject private var copied = UIBox(false)

  var body: some View {
    VStack(spacing: 10) {
      // Phase stepper while running or done
      PhaseStepper(phase: model.phase)  // always shown, so nothing jumps when a test starts

      HStack(spacing: 8) {
        SpeedTile(
          title: "Download",
          symbol: "arrow.down.circle.fill",
          tint: KitbagUI.success,
          value: model.phase == .download
            ? (model.live > 0 ? model.live : nil) : model.download,
          unit: "Mbps",
          active: model.phase == .download
        )
        SpeedTile(
          title: "Upload",
          symbol: "arrow.up.circle.fill",
          tint: .orange,
          value: model.phase == .upload
            ? (model.live > 0 ? model.live : nil) : model.upload,
          unit: "Mbps",
          active: model.phase == .upload
        )
      }

      HStack(spacing: 8) {
        Image(systemName: "timer")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.blue)
        Text("Latency").font(.callout.weight(.medium))
        Spacer()
        if model.phase == .ping {
          ProgressView().controlSize(.mini)
        }
        Text(model.ping.map { String(format: "%.0f ms", $0) } ?? "–")
          .font(.callout.weight(.semibold).monospacedDigit())
          .foregroundStyle(model.ping != nil ? .primary : .secondary)
          .contentTransition(.numericText())
      }
      .card(
        padding: 11,
        borderColor: model.phase == .ping ? .blue : nil,
        borderWidth: 1.5
      )

      HStack(spacing: 8) {
        Button {
          model.isRunning ? model.cancel() : model.start()
        } label: {
          Label(
            model.isRunning ? "Stop" : (model.phase == .idle ? "Start Speed Test" : "Test Again"),
            systemImage: model.isRunning ? "stop.fill" : "play.fill"
          )
          .font(.callout.weight(.semibold))
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(model.isRunning ? KitbagUI.danger : Color.accentColor)
        .controlSize(.large)

        Button {
          copySummary()
        } label: {
          Image(systemName: copied.value ? "checkmark" : "doc.on.doc")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(copied.value ? KitbagUI.success : .primary)
            .frame(width: 28)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(model.phase != .done)
        .help("Copy results")
        .accessibilityLabel("Copy speed test results")
      }

      HStack(spacing: 5) {
        if model.phase == .failed {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(KitbagUI.danger)
        }
        Text(status)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .foregroundStyle(model.phase == .failed ? KitbagUI.danger : .secondary)
      }
      .font(.caption)
      .frame(maxWidth: .infinity, minHeight: 16)
    }
  }

  private func copySummary() {
    let down = model.download.map { String(format: "%.1f Mbps", $0) } ?? "–"
    let up = model.upload.map { String(format: "%.1f Mbps", $0) } ?? "–"
    let ping = model.ping.map { String(format: "%.0f ms", $0) } ?? "–"
    let text = "Download: \(down) · Upload: \(up) · Latency: \(ping)"
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    withAnimation { copied.value = true }
    Task {
      try? await Task.sleep(nanoseconds: 1_500_000_000)
      withAnimation { copied.value = false }
    }
  }

  private var status: LocalizedStringKey {
    switch model.phase {
    case .idle: return "Cloudflare servers · runs only when started"
    case .ping: return "Measuring latency…"
    case .download: return "Measuring download speed…"
    case .upload: return "Measuring upload speed…"
    case .done: return "Test complete · approximate throughput"
    case .failed: return "Couldn't reach Cloudflare's speed test servers."
    }
  }
}

private struct PhaseStepper: View {
  let phase: SpeedTestModel.Phase

  private func state(for step: Int) -> Int {
    switch phase {
    case .ping: return step == 0 ? 1 : 0
    case .download: return step == 0 ? 2 : (step == 1 ? 1 : 0)
    case .upload: return step < 2 ? 2 : 1
    case .done: return 2
    default: return 0
    }
  }

  var body: some View {
    HStack(spacing: 6) {
      step("Ping", index: 0, tint: .blue)
      connector(done: state(for: 0) == 2)
      step("Download", index: 1, tint: KitbagUI.success)
      connector(done: state(for: 1) == 2)
      step("Upload", index: 2, tint: .orange)
    }
    .padding(.horizontal, 4)
  }

  private func step(_ title: LocalizedStringKey, index: Int, tint: Color) -> some View {
    let s = state(for: index)
    return HStack(spacing: 4) {
      if s == 2 {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 10.5))
          .foregroundStyle(tint)
      } else if s == 1 {
        StatusDot(color: tint, active: true, size: 5.5)
      } else {
        Circle()
          .fill(Color.secondary.opacity(0.3))
          .frame(width: 6, height: 6)
      }
      Text(title)
        .font(.caption2.weight(s == 1 ? .semibold : .medium))
        .foregroundStyle(s == 0 ? .secondary : .primary)
        .lineLimit(1)
        .fixedSize()
    }
  }

  private func connector(done: Bool) -> some View {
    Rectangle()
      .fill(done ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2))
      .frame(height: 1)
  }
}

private struct SpeedTile: View {
  let title: LocalizedStringKey
  let symbol: String
  let tint: Color
  let value: Double?
  let unit: LocalizedStringKey
  let active: Bool

  var body: some View {
    VStack(spacing: 4) {
      HStack(spacing: 4) {
        Image(systemName: symbol).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(tint)
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      }
      Group {
        if let value {
          Text(value < 100 ? String(format: "%.1f", value) : String(format: "%.0f", value))
            .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
            .contentTransition(.numericText())
        } else if active {
          ProgressView().controlSize(.small).frame(height: 34)
        } else {
          Text("–")
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .foregroundStyle(.tertiary)
        }
      }
      .frame(height: 34)
      Text(unit).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .card(
      padding: 12,
      borderColor: active ? tint : nil,
      borderWidth: 1.5
    )
    .animation(.easeOut(duration: 0.16), value: active)
    .accessibilityElement(children: .combine)
  }
}
