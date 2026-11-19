import AppKit
import Charts
import KitbagCore
import SwiftUI

/// The dashboard window, opened from the menu tab and the settings page.
@MainActor
enum DictationDashboard {
  private static var window: NSWindow?

  static func show() {
    if window == nil {
      let w = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 700),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered, defer: false)
      w.title = String(localized: "Dictation Dashboard")
      w.titlebarAppearsTransparent = true
      w.isMovableByWindowBackground = true
      w.contentViewController = NSHostingController(rootView: DashboardView())
      w.isReleasedWhenClosed = false
      w.center()
      window = w
    }
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
}

@MainActor private final class DashboardState: ObservableObject {
  enum Range: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "7 days"
    case month = "30 days"
    case all = "All time"
    var id: String { rawValue }
    var days: Int? { self == .today ? 1 : self == .week ? 7 : self == .month ? 30 : nil }
  }
  enum Metric: String, CaseIterable, Identifiable {
    case minutes = "Minutes"
    case words = "Words"
    case cost = "Cost"
    var id: String { rawValue }
  }
  @Published var range = Range.week
  @Published var metric = Metric.minutes
}

struct DashboardView: View {
  @ObservedObject private var stats = DictationStats.shared
  @StateObject private var state = DashboardState()
  @Environment(\.colorScheme) private var scheme

  private var start: Date? {
    guard let d = state.range.days else { return nil }
    return Calendar.current.date(
      byAdding: .day, value: -(d - 1), to: Calendar.current.startOfDay(for: Date()))
  }
  private var inRange: [DictationSession] { stats.sessions(since: start) }
  private var summary: DictationSummary { DictationSummary(inRange) }

  private var cardFill: Color {
    scheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.038)
  }
  private var cardBorder: Color {
    scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .center) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Dictation Dashboard").font(.title2.weight(.semibold))
            Text("\(summary.sessions) sessions in \(state.range.rawValue.lowercased())")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Picker("Range", selection: $state.range) {
            ForEach(DashboardState.Range.allCases) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .frame(width: 330)
        }

        if stats.sessions.isEmpty {
          VStack(spacing: 10) {
            Image(systemName: "waveform.badge.mic")
              .font(.system(size: 34, weight: .light))
              .foregroundStyle(.tertiary)
            Text("No dictations yet")
              .font(.headline)
            Text("Use your dictation shortcut in any app and your activity will appear here.")
              .font(.callout)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity, minHeight: 240)
          .background(cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .strokeBorder(cardBorder, lineWidth: 0.5)
          )
        } else {
          cards
          chart
          recent
        }
        footer
      }
      .padding(.horizontal, 24)
      .padding(.top, 14)
      .padding(.bottom, 24)
    }
    .frame(minWidth: 700, minHeight: 560)
  }

  // MARK: Numbers

  private var cards: some View {
    let s = summary
    return LazyVGrid(
      columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12
    ) {
      card(
        "Speaking Time", Self.duration(s.speakSeconds), "\(s.sessions) dictations", "mic.fill", .red
      )
      card(
        "Words", s.words.formatted(), "\(Int(s.wordsPerMinute.rounded())) words/min",
        "text.alignleft", .blue)
      card(
        "Time Saved", Self.duration(s.minutesSaved * 60), "vs typing at 40 wpm",
        "clock.badge.checkmark", KitbagUI.success)
      card(
        "Tokens", Self.compact(s.tokens),
        "\(Self.compact(s.inputTokens)) in · \(Self.compact(s.outputTokens)) out", "number",
        .purple)
      card(
        "Estimated Cost", Self.money(s.cost), "\(Self.money(s.costPerDictation)) per dictation",
        "dollarsign.circle.fill", .orange)
      card("Today", Self.duration(todaySeconds), "\(todayWords) words", "sun.max.fill", .teal)
    }
  }

  private var today: [DictationSession] {
    stats.sessions(since: Calendar.current.startOfDay(for: Date()))
  }
  private var todaySeconds: Double { today.reduce(0) { $0 + $1.speakSeconds } }
  private var todayWords: Int { today.reduce(0) { $0 + $1.finalWords } }

  private func card(_ title: String, _ value: String, _ sub: String, _ icon: String, _ tint: Color)
    -> some View
  {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(tint)
          .frame(width: 22, height: 22)
          .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      Text(value)
        .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
        .minimumScaleFactor(0.7)
        .lineLimit(1)
      Text(sub)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(cardBorder, lineWidth: 0.5)
    )
  }

  // MARK: Chart

  private struct DayValue: Identifiable {
    let day: Date
    let value: Double
    var id: Date { day }
  }

  private var days: [DayValue] {
    let cal = Calendar.current
    let hourly = state.range == .today
    let unit: Calendar.Component = hourly ? .hour : .day
    func bucket(_ d: Date) -> Date {
      hourly ? (cal.dateInterval(of: .hour, for: d)?.start ?? d) : cal.startOfDay(for: d)
    }
    let first =
      hourly
      ? cal.startOfDay(for: Date())
      : (start ?? cal.startOfDay(for: inRange.map(\.date).min() ?? Date()))
    let last = bucket(Date())
    var byBucket: [Date: Double] = [:]
    for s in inRange {
      let d = bucket(s.date)
      switch state.metric {
      case .minutes: byBucket[d, default: 0] += s.speakSeconds / 60
      case .words: byBucket[d, default: 0] += Double(s.finalWords)
      case .cost: byBucket[d, default: 0] += s.cost
      }
    }
    var out: [DayValue] = []
    var d = first
    while d <= last {
      out.append(DayValue(day: d, value: byBucket[d] ?? 0))
      d = cal.date(byAdding: unit, value: 1, to: d) ?? last.addingTimeInterval(86400)
    }
    return out
  }

  private var chart: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(state.range == .today ? "Activity by Hour" : "Activity by Day")
          .font(.headline)
        Spacer()
        Picker("Metric", selection: $state.metric) {
          ForEach(DashboardState.Metric.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 220)
      }
      if inRange.isEmpty {
        Text("No activity recorded in this period.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 190)
      } else {
        Chart(days) { d in
          BarMark(
            x: .value("Time", d.day, unit: state.range == .today ? .hour : .day),
            y: .value(state.metric.rawValue, d.value)
          )
          .foregroundStyle(Color.accentColor.gradient)
          .cornerRadius(4)
        }
        .frame(height: 190)
      }
    }
    .padding(16)
    .background(cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(cardBorder, lineWidth: 0.5)
    )
  }

  // MARK: Recent

  private var recent: some View {
    let rows = Array(inRange.suffix(10).reversed())
    return VStack(alignment: .leading, spacing: 10) {
      Text("Recent Dictations").font(.headline)
      if rows.isEmpty {
        Text("No dictations in this period.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .padding(.vertical, 8)
      } else {
        VStack(spacing: 0) {
          HStack {
            Text("When").frame(width: 155, alignment: .leading)
            Text("Duration").frame(width: 72, alignment: .leading)
            Text("Words").frame(width: 82, alignment: .leading)
            Text("Cleanup").frame(width: 120, alignment: .leading)
            Spacer()
            Text("Cost")
          }
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.tertiary)
          .textCase(.uppercase)
          .padding(.horizontal, 8)
          .padding(.bottom, 6)

          Divider().opacity(0.5)

          ForEach(rows) { s in
            HStack {
              Text(s.date.formatted(date: .abbreviated, time: .shortened))
                .frame(width: 155, alignment: .leading)
                .foregroundStyle(.primary)
              Text(Self.duration(s.speakSeconds))
                .monospacedDigit()
                .frame(width: 72, alignment: .leading)
              Text("\(s.finalWords) words")
                .monospacedDigit()
                .frame(width: 82, alignment: .leading)
              Text(Self.tokenLabel(s))
                .frame(width: 120, alignment: .leading)
              Spacer()
              Text(s.cost > 0 ? Self.money(s.cost) : "–")
                .monospacedDigit()
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .hoverHighlight(cornerRadius: 7)
          }
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(cardBorder, lineWidth: 0.5)
    )
  }

  private var footer: some View {
    HStack {
      Text(
        "Cost reflects Claude API pricing when Claude cleanup is used. Local Gemma and Claude subscriptions aren't billed per call."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      Spacer(minLength: 12)
      Button("Reset Stats", role: .destructive) {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = String(localized: "Reset all dictation stats?")
        a.informativeText = String(
          localized: "This permanently clears your dictation history and cannot be undone.")
        a.addButton(withTitle: String(localized: "Cancel"))
        let resetBtn = a.addButton(withTitle: String(localized: "Reset"))
        resetBtn.hasDestructiveAction = true
        if a.runModal() == .alertSecondButtonReturn { stats.reset() }
      }
      .controlSize(.small)
    }
  }

  // MARK: Formatting

  private static func tokenLabel(_ s: DictationSession) -> String {
    if s.model == nil { return "As spoken" }
    let total = s.inputTokens + s.outputTokens
    return total > 0 ? "\(total) tokens" : "Local"
  }

  static func duration(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m \(s % 60)s" }
    return "\(s / 3600)h \((s % 3600) / 60)m"
  }

  static func compact(_ n: Int) -> String {
    n >= 1_000_000
      ? String(format: "%.2fM", Double(n) / 1e6)
      : n >= 10_000 ? String(format: "%.1fk", Double(n) / 1e3) : n.formatted()
  }

  static func money(_ v: Double) -> String {
    v < 0.01 && v > 0 ? String(format: "$%.4f", v) : String(format: "$%.2f", v)
  }
}
