import Charts
import SwiftUI

/// Settings page: start and stop recording CPU and memory, watch them on two live graphs, and copy
/// the log to share. Lives in the Settings window only (nothing in the menu bar popover).
public struct DiagnosticsPage: View {
  @ObservedObject private var diag = Diagnostics.shared
  @StateObject private var noteBox = UIBox<String?>(nil)
  private var note: String? { noteBox.value }

  public init() {}

  private static let clock: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .none
    f.timeStyle = .medium
    return f
  }()

  public var body: some View {
    Section("Performance diagnostics") {
      VStack(alignment: .leading, spacing: 10) {
        Text(
          "Records how much CPU and memory Kitbag uses, which parts are busy, and what the tools were doing. It is off until you start it and stops when you stop it or quit Kitbag."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 12) {
          Button {
            diag.isRecording ? diag.stop() : diag.start()
            noteBox.value = nil
          } label: {
            Label(
              diag.isRecording ? "Stop recording" : "Start recording",
              systemImage: diag.isRecording ? "stop.circle.fill" : "record.circle")
          }
          .buttonStyle(.borderedProminent)
          .tint(diag.isRecording ? KitbagUI.danger : Color.accentColor)
          .controlSize(.large)

          statusLabel
          Spacer(minLength: 0)
        }
      }
      .padding(.vertical, 4)

      if diag.startedAt != nil {
        LabeledContent("Started") { Text(Self.stamp(diag.startedAt)).monospacedDigit() }
        LabeledContent(diag.isRecording ? "Running for" : "Stopped") {
          if diag.isRecording {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
              Text(Self.duration(from: diag.startedAt, to: ctx.date)).monospacedDigit()
            }
          } else {
            Text("\(Self.stamp(diag.stoppedAt))  ·  lasted \(Self.duration(from: diag.startedAt, to: diag.stoppedAt))")
              .monospacedDigit()
          }
        }
      }
    }

    Section("CPU") {
      MetricChart(
        samples: diag.samples, unit: "%", kitbag: \.appCPU, helpers: \.helperCPU,
        recording: diag.isRecording, hint: "100% is one full core.")
    }

    Section("Memory") {
      MetricChart(
        samples: diag.samples, unit: " MB", kitbag: \.appMemoryMB, helpers: \.helperMemoryMB,
        recording: diag.isRecording, hint: "Memory footprint, as Activity Monitor counts it.")
    }

    Section("Log file") {
      if let path = diag.currentLogPath {
        LabeledContent("File") {
          Text(path).font(.caption).textSelection(.enabled).lineLimit(2)
            .multilineTextAlignment(.trailing)
        }
        LabeledContent("Size in folder") {
          Text(ByteCountFormatter.string(fromByteCount: diag.logSize, countStyle: .file))
        }
      } else {
        Text("No log yet. Start recording to create one.").foregroundStyle(.secondary)
      }
      HStack(spacing: 8) {
        Button("Copy log text") { copy(diag.copyLogText(), "Log text copied. Paste it into your message.") }
        Button("Copy log file") { copy(diag.copyLogFile(), "Log file copied. Paste it where files are accepted.") }
        Button("Show in Finder") { diag.revealInFinder() }
        Spacer(minLength: 0)
        Button("Delete old logs", role: .destructive) { diag.clearOldLogs() }
      }
      .disabled(false)
      if let note {
        Text(note).font(.caption).foregroundStyle(.secondary)
      }
      Text(
        "When CPU stays high, or memory jumps, a call-stack sample is saved next to the log, so a spike can be traced to the code that caused it."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
    .onAppear { diag.refreshSize() }
  }

  private var statusLabel: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(diag.isRecording ? KitbagUI.danger : Color.secondary.opacity(0.4))
        .frame(width: 8, height: 8)
      Text(diag.isRecording ? "Recording" : (diag.startedAt == nil ? "Off" : "Stopped"))
        .font(.callout.weight(.medium))
        .foregroundStyle(diag.isRecording ? Color.primary : Color.secondary)
    }
  }

  private func copy(_ ok: Bool, _ message: String) {
    noteBox.value = ok ? message : "There is no log to copy yet."
  }

  private static func stamp(_ d: Date?) -> String {
    guard let d else { return "-" }
    let day = DateFormatter()
    day.dateStyle = .medium
    day.timeStyle = .none
    return "\(day.string(from: d)), \(clock.string(from: d))"
  }

  private static func duration(from a: Date?, to b: Date?) -> String {
    guard let a, let b else { return "-" }
    let s = max(0, Int(b.timeIntervalSince(a)))
    return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
  }
}

/// A line graph over time: Kitbag itself, and the programs it started (ffmpeg and friends).
private struct MetricChart: View {
  let samples: [DiagnosticsSample]
  let unit: String
  let kitbag: KeyPath<DiagnosticsSample, Double>
  let helpers: KeyPath<DiagnosticsSample, Double>
  let recording: Bool
  let hint: String

  private var latest: DiagnosticsSample? { samples.last }
  private var peak: Double { samples.map { $0[keyPath: kitbag] }.max() ?? 0 }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 18) {
        stat("Now", latest.map { $0[keyPath: kitbag] }, color: .accentColor)
        stat("Peak", samples.isEmpty ? nil : peak, color: .secondary)
        stat("Helpers now", latest.map { $0[keyPath: helpers] }, color: .orange)
        Spacer(minLength: 0)
      }
      if samples.isEmpty {
        Text(recording ? "Waiting for the first sample…" : "Start recording to see this graph.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 130, alignment: .center)
      } else {
        Chart {
          ForEach(samples) { s in
            AreaMark(x: .value("Time", s.time), y: .value("Kitbag", s[keyPath: kitbag]), series: .value("Series", "Kitbag"))
              .foregroundStyle(Color.accentColor.opacity(0.16))
            LineMark(x: .value("Time", s.time), y: .value("Kitbag", s[keyPath: kitbag]), series: .value("Series", "Kitbag"))
              .foregroundStyle(Color.accentColor)
              .interpolationMethod(.monotone)
            LineMark(x: .value("Time", s.time), y: .value("Helpers", s[keyPath: helpers]), series: .value("Series", "Helpers"))
              .foregroundStyle(Color.orange)
              .interpolationMethod(.monotone)
          }
        }
        .chartYScale(domain: 0...max(10, ceil((samples.map { max($0[keyPath: kitbag], $0[keyPath: helpers]) }.max() ?? 0) * 1.2)))
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour().minute().second()) } }
        .chartYAxis { AxisMarks(position: .leading) { v in
          AxisGridLine()
          AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d))\(unit.trimmingCharacters(in: .whitespaces))") } }
        } }
        .frame(height: 170)
        HStack(spacing: 14) {
          legend("Kitbag", .accentColor)
          legend("Helpers (ffmpeg, commands)", .orange)
          Spacer(minLength: 0)
          Text(hint).font(.caption).foregroundStyle(.secondary)
        }
      }
    }
    .padding(.vertical, 4)
  }

  private func stat(_ title: String, _ value: Double?, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      Text(value.map { String(format: "%.0f", $0) + unit } ?? "-")
        .font(.title3.weight(.semibold)).monospacedDigit()
        .foregroundStyle(color == .secondary ? Color.primary : color)
    }
  }

  private func legend(_ text: String, _ color: Color) -> some View {
    HStack(spacing: 5) {
      Capsule().fill(color).frame(width: 14, height: 3)
      Text(text).font(.caption).foregroundStyle(.secondary)
    }
  }
}
