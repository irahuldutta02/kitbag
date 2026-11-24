import Testing

@testable import Mirror

@MainActor @Suite struct MirrorTests {
  @Test func startsIdleAndFlipped() {
    let m = MirrorModel()
    #expect(m.state == .idle)
    #expect(m.flipped)
  }

  @Test func stopWhenIdleIsSafe() {
    let m = MirrorModel()
    m.stop()
    #expect(m.state == .idle)
  }
}
