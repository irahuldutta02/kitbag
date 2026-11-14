import Foundation
import KitbagCore
import Testing

@testable import Blip

@MainActor @Suite struct BlipTests {
  @Test func isATablessIntegration() {
    #expect(BlipTool.descriptor.requiresApp == "net.blip.macos")
    #expect(!BlipTool.descriptor.showsTab)
  }

  @Test func offersASenderOnlyWhileActive() throws {
    let tool = BlipTool()
    #expect(tool.fileSenders.isEmpty)
    try tool.start()
    #expect(tool.fileSenders.map(\.id) == ["blip"])
    tool.stop()
    #expect(tool.fileSenders.isEmpty)
  }

  @Test func ignoresNonFileURLs() async {
    let m = BlipModel()
    let result = await m.send([URL(string: "https://example.com")!])
    #expect(!result.success && result.message == nil)
  }
}
