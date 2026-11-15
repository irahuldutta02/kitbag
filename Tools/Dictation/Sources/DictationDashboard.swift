import AppKit
import Charts
import SwiftUI

/// The dashboard window, opened from the menu tab and the settings page.
@MainActor
enum DictationDashboard {
  private static var window: NSWindow?

  static func show() {
    if window == nil {
      let w = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 780, height: 700),
        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
      w.title = String(localized: "Dictation Dashboard")
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
    case today = "Today", week = "7 days", month = "30 days", all = "All time"
    var id: String { rawValue }
    var days: Int? { self == .today ? 1 : self == .week ? 7 : self == .month ? 30 : nil }
  }
  enum Metric: String, CaseIterable, Identifiable {
    case minutes = "Minutes", words = "Words", cost = "Cost"
    var id: String { rawValue }
  }
  @Published var range = Range.week
  @Published var metric = Metric.minutes
}

struct DashboardView: View {
  @ObservedObject private var stats = DictationStats.shared
  @StateObject private var state = DashboardState()

  private var start: Date? {
    guard let d = state.range.days else { return nil }
    return Calendar.current.date(byAdding: .day, value: -(d - 1), to: Calendar.current.startOfDay(for: Date()))
  }
  private var inRange: [DictationSession] { stats.sessions(since: start) }
  private var summary: DictationSummary { DictationSummary(inRange) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          Text("Dictation").font(.title.weight(.semibold))
          Spacer()
          Picker("Range", selection: $state.range) {
            ForEach(DashboardState.Range.allCases) { Text($0.rawValue).tag($0) }
          }.pickerStyle(.segmented).labelsHidden().frame(width: 340)
        }
        if stats.sessions.isEmpty {
          Text("No dictations yet. Hold the Globe key and say something.")
            .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 200)
        } else {
          cards
          chart
          recent
        }
        footer
      }
      .padding(24)
    }
    .frame(minWidth: 680, minHeight: 560)
  }

  // MARK: Numbers

  private var cards: some View {
    let s = summary
    return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
      card("Speaking time", Self.duration(s.speakSeconds), "\(s.sessions) dictations", "mic.fill", .red)
      card("Words", s.words.formatted(), "\(Int(s.wordsPerMinute.rounded())) words per minute", "text.alignleft", .blue)
      card("Time saved", Self.duration(s.minutesSaved * 60), "vs typing at 40 wpm", "clock.badge.checkmark", .green)
      card("Tokens", Self.compact(s.tokens), "\(Self.compact(s.inputTokens)) in · \(Self.compact(s.outputTokens)) out", "number", .purple)
      card("Estimated cost", Self.money(s.cost), "\(Self.money(s.costPerDictation)) per dictation", "dollarsign.circle.fill", .orange)
      card("Today", Self.duration(todaySeconds), "\(todayWords) words", "sun.max.fill", .teal)
    }
  }

  private var today: [DictationSession] {
    stats.sessions(since: Calendar.current.startOfDay(for: Date()))
  }
  private var todaySeconds: Double { today.reduce(0) { $0 + $1.speakSeconds } }
  private var todayWords: Int { today.reduce(0) { $0 + $1.finalWords } }

  private func card(_ title: String, _ value: String, _ sub: String, _ icon: String, _ tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(title, systemImage: icon).font(.caption).foregroundStyle(tint)
      Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
      Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
    let first = hourly ? cal.startOfDay(for: Date()) : (start ?? cal.startOfDay(for: inRange.map(\.date).min() ?? Date()))
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
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(state.range == .today ? "Per hour" : "Per day").font(.headline)
        Spacer()
        Picker("Metric", selection: $state.metric) {
          ForEach(DashboardState.Metric.allCases) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
      }
      Chart(days) { d in
        BarMark(x: .value("Time", d.day, unit: state.range == .today ? .hour : .day), y: .value(state.metric.rawValue, d.value))
          .foregroundStyle(Color.accentColor.gradient).cornerRadius(3)
      }
      .frame(height: 190)
    }
    .padding(14)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  // MARK: Recent

  private var recent: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Recent dictations").font(.headline)
      ForEach(Array(stats.sessions.suffix(8).reversed())) { s in
        HStack {
          Text(s.date.formatted(date: .abbreviated, time: .shortened)).frame(width: 150, alignment: .leading)
          Text(Self.duration(s.speakSeconds)).frame(width: 70, alignment: .leading)
          Text("\(s.finalWords) words").frame(width: 80, alignment: .leading)
          Text(Self.tokenLabel(s)).frame(width: 100, alignment: .leading)
          Spacer()
          Text(s.model == nil ? "–" : Self.money(s.cost)).monospacedDigit()
        }
        .font(.callout).foregroundStyle(.secondary)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var footer: some View {
    HStack {
      Text("Cost is what Claude Code reports for each cleanup, at API prices. On a Claude subscription you aren't billed per call.")
        .font(.caption).foregroundStyle(.secondary)
      Spacer()
      Button("Reset stats", role: .destructive) {
        let a = NSAlert()
        a.messageText = String(localized: "Reset all dictation stats?")
        a.informativeText = String(localized: "This can't be undone.")
        a.addButton(withTitle: String(localized: "Reset"))
        a.addButton(withTitle: String(localized: "Cancel"))
        if a.runModal() == .alertFirstButtonReturn { stats.reset() }
      }.controlSize(.small)
    }
  }

  // MARK: Formatting

  private static func tokenLabel(_ s: DictationSession) -> String {
    if s.model == nil { return "as spoken" }
    return "\(s.inputTokens + s.outputTokens) tokens"
  }

  static func duration(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m \(s % 60)s" }
    return "\(s / 3600)h \((s % 3600) / 60)m"
  }

  static func compact(_ n: Int) -> String {
    n >= 1_000_000 ? String(format: "%.2fM", Double(n) / 1e6)
      : n >= 10_000 ? String(format: "%.1fk", Double(n) / 1e3) : n.formatted()
  }

  static func money(_ v: Double) -> String {
    v < 0.01 && v > 0 ? String(format: "$%.4f", v) : String(format: "$%.2f", v)
  }
}
