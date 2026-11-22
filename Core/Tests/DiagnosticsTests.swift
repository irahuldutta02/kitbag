import Foundation
import Testing

@testable import KitbagCore

@MainActor
struct DiagnosticsTests {
  @Test func recordsSamplesAndWritesLog() async throws {
    let d = Diagnostics.shared
    #expect(!d.isRecording)
    d.start()
    #expect(d.isRecording)
    Diagnostics.event("test", "hello")
    try await Task.sleep(nanoseconds: 4_500_000_000)
    d.stop()
    #expect(!d.isRecording)
    #expect(d.stoppedAt != nil)
    #expect(d.samples.count >= 1)
    let path = try #require(d.currentLogPath)
    let text = try String(contentsOfFile: path, encoding: .utf8)
    #expect(text.contains("[SAMPLE] app cpu="))
    #expect(text.contains("[EVENT] test: hello"))
    #expect(text.contains("recording stopped"))
    #expect(d.copyLogText())
  }
}
