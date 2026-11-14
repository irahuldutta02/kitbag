import AppKit
import CoreAudio

@MainActor
final class AudioModel: ObservableObject {
  @Published private(set) var outputs: [AudioDevice] = []
  @Published private(set) var inputs: [AudioDevice] = []
  @Published private(set) var defaultOutput: AudioDeviceID = 0
  @Published private(set) var defaultInput: AudioDeviceID = 0
  @Published var message: String?
  /// Several outputs at once (through a Multi-Output device) instead of one.
  @Published private(set) var multiOutput = false
  @Published private(set) var selectedOutputs: Set<AudioDeviceID> = []

  private(set) var timer: Timer?

  // MARK: Lifecycle (polling only while the tab is visible)

  func setActive(_ on: Bool) {
    if on {
      refreshDevices()
      let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.refreshDevices() }
      }
      t.tolerance = 0.5
      RunLoop.main.add(t, forMode: .common)
      timer = t
    } else {
      timer?.invalidate()
      timer = nil
      outputs = []
      inputs = []
      message = nil
    }
  }

  // MARK: Devices

  func refreshDevices() {
    let all = CoreAudioDevices.all()
    outputs = all.filter(\.hasOutput)
    inputs = all.filter(\.hasInput)
    defaultOutput = CoreAudioDevices.defaultDevice(input: false)
    defaultInput = CoreAudioDevices.defaultDevice(input: true)
    if let uids = CoreAudioDevices.multiOutputMemberUIDs(defaultOutput: defaultOutput) {
      multiOutput = true
      selectedOutputs = Set(outputs.filter { uids.contains($0.uid) }.map(\.id))
    } else if !multiOutput {
      selectedOutputs = [defaultOutput]
    }
  }

  func setMultiOutput(_ on: Bool) {
    guard on != multiOutput else { return }
    multiOutput = on
    if !on {
      // Back to one device: keep the first selected one.
      selectedOutputs = Set(outputs.filter { selectedOutputs.contains($0.id) }.prefix(1).map(\.id))
      applyOutputs()
    }
  }

  /// Plays on the chosen devices: one directly, several through a Multi-Output device.
  private func applyOutputs() {
    // Wired/built-in first as the clock master; Bluetooth devices follow it.
    let chosen = outputs.filter { selectedOutputs.contains($0.id) }
      .sorted {
        ($0.transport == kAudioDeviceTransportTypeBluetooth ? 1 : 0)
          < ($1.transport == kAudioDeviceTransportTypeBluetooth ? 1 : 0)
      }
    var ok = true
    if chosen.count == 1 {
      ok = CoreAudioDevices.setDefault(chosen[0].id, input: false)
      CoreAudioDevices.destroyMultiOutput()
    } else if chosen.count > 1 {
      if let id = CoreAudioDevices.createMultiOutput(chosen) {
        ok = CoreAudioDevices.setDefault(id, input: false)
      } else {
        ok = false
      }
    }
    message = ok ? nil : String(localized: "Couldn't set up the selected outputs.")
    refreshDevices()
  }

  func select(_ device: AudioDevice, input: Bool) {
    if !input && multiOutput {
      if selectedOutputs.contains(device.id) {
        guard selectedOutputs.count > 1 else { return }  // keep at least one
        selectedOutputs.remove(device.id)
      } else {
        selectedOutputs.insert(device.id)
      }
      applyOutputs()
      return
    }
    let ok = CoreAudioDevices.setDefault(device.id, input: input)
    message = ok ? nil : String(localized: "Couldn't switch to “\(device.name)”.")
    refreshDevices()
  }

  func openSoundSettings() {
    for link in [
      "x-apple.systempreferences:com.apple.Sound-Settings.extension",
      "x-apple.systempreferences:com.apple.preference.sound",
    ] {
      if let url = URL(string: link), NSWorkspace.shared.open(url) { return }
    }
  }
}
