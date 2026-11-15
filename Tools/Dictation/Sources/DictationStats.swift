import Foundation

/// One finished dictation.
struct DictationSession: Codable, Identifiable {
  var id = UUID()
  var date: Date
  var speakSeconds: Double
  var rawWords: Int
  var finalWords: Int
  /// The model that cleaned it up; nil when it was pasted as spoken.
  var model: String?
  var inputTokens: Int
  var outputTokens: Int
  /// Cost reported by Claude Code (what the same call would cost on the API).
  var cost: Double
}

/// Totals over some sessions.
struct DictationSummary {
  var sessions = 0
  var speakSeconds = 0.0
  var words = 0
  var inputTokens = 0
  var outputTokens = 0
  var cost = 0.0

  init(_ list: [DictationSession] = []) {
    for s in list {
      sessions += 1
      speakSeconds += s.speakSeconds
      words += s.finalWords
      inputTokens += s.inputTokens
      outputTokens += s.outputTokens
      cost += s.cost
    }
  }

  var minutes: Double { speakSeconds / 60 }
  var wordsPerMinute: Double { speakSeconds > 5 ? Double(words) / minutes : 0 }
  var tokens: Int { inputTokens + outputTokens }
  var costPerDictation: Double { sessions > 0 ? cost / Double(sessions) : 0 }
  /// Time saved against typing at 40 words per minute.
  var minutesSaved: Double { max(0, Double(words) / 40 - minutes) }
}

/// Keeps every dictation in a small JSON file so the dashboard survives restarts.
@MainActor
final class DictationStats: ObservableObject {
  static let shared = DictationStats()
  @Published private(set) var sessions: [DictationSession] = []
  private let url: URL

  init(url: URL? = nil) {
    self.url =
      url
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Kitbag/dictation-stats.json")
    if let data = try? Data(contentsOf: self.url) {
      let dec = JSONDecoder()
      dec.dateDecodingStrategy = .iso8601
      sessions = (try? dec.decode([DictationSession].self, from: data)) ?? []
    }
  }

  func add(_ s: DictationSession) {
    sessions.append(s)
    save()
  }

  func reset() {
    sessions = []
    save()
  }

  func sessions(since date: Date?) -> [DictationSession] {
    guard let date else { return sessions }
    return sessions.filter { $0.date >= date }
  }

  static func words(_ text: String) -> Int {
    text.split(whereSeparator: \.isWhitespace).count
  }

  private func save() {
    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601
    try? FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let data = try? enc.encode(sessions) { try? data.write(to: url, options: .atomic) }
  }
}
