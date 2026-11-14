import Foundation
import Testing

@testable import SpeedTest

@MainActor @Suite struct SpeedTestTests {
  @Test func mbpsMath() {
    #expect(SpeedProbe.mbps(bytes: 12_500_000, seconds: 1) == 100)
    #expect(SpeedProbe.mbps(bytes: 1, seconds: 0) == 0)
  }

  @Test func idleUntilStartedAndCancelIsSafe() {
    let m = SpeedTestModel()
    #expect(m.phase == .idle)
    #expect(!m.isRunning)
    m.cancel()
    #expect(m.phase == .idle)
  }

  @Test func resetClearsResults() {
    let m = SpeedTestModel()
    m.reset()
    #expect(m.download == nil && m.upload == nil && m.ping == nil)
    #expect(m.phase == .idle)
  }

  @Test func doesNotAcceptFileDrops() {
    #expect(!SpeedTestTool().acceptsFileDrops)
  }
}
