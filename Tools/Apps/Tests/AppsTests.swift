import Carbon.HIToolbox
import Foundation
import KitbagCore
import Testing

@testable import Apps

@MainActor @Suite struct AppsTests {
  private func withIsolatedDefaults(_ body: (UserDefaults) -> Void) {
    let suite = "kitbag.apps.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }
    body(defaults)
  }

  @Test func catalogHasUniqueIDs() {
    let ids = AppsModel.catalog.map(\.id)
    #expect(Set(ids).count == ids.count)
    #expect(ids == ["gdrive", "pdrive", "wispr", "openwhispr", "finetune"])
  }

  @Test func observesOnlyWhileActive() throws {
    let tool = AppsTool()
    try tool.start()
    #expect(tool.makeSettingsView() != nil)
    tool.stop()
    #expect(tool.makeSettingsView() == nil)
  }

  @Test func catalogCategoryAssignments() {
    let byID = Dictionary(uniqueKeysWithValues: AppsModel.catalog.map { ($0.id, $0.category) })
    #expect(byID["gdrive"] == .cloudStorage)
    #expect(byID["pdrive"] == .cloudStorage)
    #expect(byID["wispr"] == .dictation)
    #expect(byID["openwhispr"] == .dictation)
    #expect(byID["finetune"] == .audio)

    #expect(AppCategory.dictation.name == "Dictation")
    #expect(AppCategory.dictation.symbol == "waveform")
    #expect(AppCategory.cloudStorage.name == "Cloud Storage")
    #expect(AppCategory.cloudStorage.symbol == "icloud")
    #expect(AppCategory.audio.name == "Audio")
    #expect(AppCategory.audio.symbol == "speaker.wave.2")
  }

  @Test func groupsDictationSwitchWithDictationAppsAndFallbackForUnknown() {
    withIsolatedDefaults { defaults in
      let model = AppsModel(defaults: defaults)
      let dictationSwitch = ToolSwitch(
        id: "dictation", name: "Dictation", symbol: "mic.fill", category: "dictation",
        isOn: true, error: nil, set: { _ in })
      let uncategorizedSwitch = ToolSwitch(
        id: "custom", name: "Custom", symbol: "wrench", category: nil,
        isOn: false, error: nil, set: { _ in })
      let unknownCategorySwitch = ToolSwitch(
        id: "other", name: "Other", symbol: "star", category: "nonexistent",
        isOn: false, error: nil, set: { _ in })

      let groups = model.grouped(
        apps: AppsModel.catalog,
        switches: [dictationSwitch, uncategorizedSwitch, unknownCategorySwitch]
      )

      #expect(groups.map(\.id) == ["dictation", "cloudStorage", "audio", "kitbag-tools"])

      let dictationGroup = groups[0]
      #expect(dictationGroup.category == .dictation)
      #expect(dictationGroup.switches.map(\.id) == ["dictation"])
      #expect(dictationGroup.apps.map(\.id) == ["wispr", "openwhispr"])

      let cloudGroup = groups[1]
      #expect(cloudGroup.category == .cloudStorage)
      #expect(cloudGroup.switches.isEmpty)
      #expect(cloudGroup.apps.map(\.id) == ["gdrive", "pdrive"])

      let audioGroup = groups[2]
      #expect(audioGroup.category == .audio)
      #expect(audioGroup.switches.isEmpty)
      #expect(audioGroup.apps.map(\.id) == ["finetune"])

      let fallbackGroup = groups[3]
      #expect(fallbackGroup.category == nil)
      #expect(fallbackGroup.switches.map(\.id) == ["custom", "other"])
      #expect(fallbackGroup.apps.isEmpty)
    }
  }

  @Test func groupingOmitsEmptyCategories() {
    withIsolatedDefaults { defaults in
      let model = AppsModel(defaults: defaults)
      let dictationSwitch = ToolSwitch(
        id: "dictation", name: "Dictation", symbol: "mic.fill", category: "dictation",
        isOn: false, error: nil, set: { _ in })

      let groups = model.grouped(apps: [], switches: [dictationSwitch])
      #expect(groups.map(\.id) == ["dictation"])
      #expect(model.grouped(apps: [], switches: []).isEmpty)
    }
  }

  @Test func defaultShortcutAndPersistenceAndClearing() {
    withIsolatedDefaults { defaults in
      let initial = AppsModel(defaults: defaults)
      #expect(initial.shortcut == AppsModel.defaultShortcut)
      #expect(initial.shortcut?.display == "⌃⌥A")

      let custom = KeyShortcut(
        keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(controlKey | shiftKey), label: "P")
      #expect(initial.setShortcut(custom))
      #expect(initial.shortcut == custom)
      #expect(AppsModel(defaults: defaults).shortcut == custom)

      #expect(initial.setShortcut(nil))
      #expect(initial.shortcut == nil)
      #expect(AppsModel(defaults: defaults).shortcut == nil)

      #expect(initial.setShortcut(AppsModel.defaultShortcut))
      #expect(AppsModel(defaults: defaults).shortcut == AppsModel.defaultShortcut)
    }
  }
}
