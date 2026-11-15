import Testing

@testable import Apps

@MainActor @Suite struct AppsTests {
  @Test func catalogHasUniqueIDs() {
    let ids = AppsModel.catalog.map(\.id)
    #expect(Set(ids).count == ids.count)
    #expect(ids == ["gdrive", "pdrive", "wispr", "finetune"])
  }

  @Test func observesOnlyWhileActive() throws {
    let tool = AppsTool()
    try tool.start()
    #expect(tool.makeSettingsView() != nil)
    tool.stop()
    #expect(tool.makeSettingsView() == nil)
  }
}
