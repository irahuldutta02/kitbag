import Foundation
import Testing

@testable import Audio

@MainActor @Suite struct AudioTests {
  @Test func liveDeviceListIsSane() {
    let all = CoreAudioDevices.all()
    #expect(all.allSatisfy { $0.hasInput || $0.hasOutput })
    #expect(Set(all.map(\.id)).count == all.count)
  }

  @Test func ownMultiOutputDeviceIsNeverListed() {
    #expect(CoreAudioDevices.all().allSatisfy { $0.uid != CoreAudioDevices.multiUID })
  }

  @Test func pollingOnlyWhileActive() {
    let m = AudioModel()
    #expect(m.timer == nil)
    m.setActive(true)
    #expect(m.timer != nil)
    m.setActive(false)
    #expect(m.timer == nil && m.outputs.isEmpty && m.inputs.isEmpty)
  }

  @Test func doesNotAcceptFileDrops() {
    #expect(!AudioTool().acceptsFileDrops)
  }
}
