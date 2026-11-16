import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Equatable {
  let id: AudioDeviceID
  let uid: String
  let name: String
  let hasInput: Bool
  let hasOutput: Bool
  let transport: UInt32

  var symbol: String {
    switch transport {
    case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
      return "headphones"
    case kAudioDeviceTransportTypeBuiltIn: return hasOutput ? "speaker.wave.2.fill" : "mic.fill"
    case kAudioDeviceTransportTypeUSB: return "cable.connector"
    case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
    case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
    default: return hasOutput ? "hifispeaker.fill" : "mic.fill"
    }
  }
}

enum CoreAudioDevices {
  private static let system = AudioObjectID(kAudioObjectSystemObject)

  private static func address(
    _ selector: AudioObjectPropertySelector,
    _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
  }

  static func all() -> [AudioDevice] {
    var a = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == 0 else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(system, &a, 0, nil, &size, &ids) == 0 else { return [] }
    return ids.compactMap { id in
      guard !isHidden(id) else { return nil }
      let input = channels(id, kAudioObjectPropertyScopeInput) > 0
      let output = channels(id, kAudioObjectPropertyScopeOutput) > 0
      guard input || output else { return nil }
      let uid = uid(id)
      guard uid != multiUID else { return nil }  // our own Multi-Output device isn't a choice
      // Private helper devices that apps (including Kitbag's recorder) create for themselves.
      guard !uid.hasPrefix("CADefaultDeviceAggregate"), !name(id).hasPrefix("CADefaultDeviceAggregate") else { return nil }
      return AudioDevice(
        id: id, uid: uid, name: name(id), hasInput: input, hasOutput: output,
        transport: transport(id))
    }
  }

  static let multiUID = "com.irahuldutta.kitbag.multi-output"

  static func uid(_ id: AudioDeviceID) -> String {
    var ref: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var a = address(kAudioDevicePropertyDeviceUID)
    guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &ref) == 0, let ref else { return "" }
    return ref.takeRetainedValue() as String
  }

  /// If the default output is Kitbag's Multi-Output device, the UIDs of the devices it plays on.
  static func multiOutputMemberUIDs(defaultOutput: AudioDeviceID) -> [String]? {
    guard uid(defaultOutput) == multiUID else { return nil }
    var a = address(kAudioAggregateDevicePropertyFullSubDeviceList)
    var size = UInt32(MemoryLayout<CFArray?>.size)
    var list: Unmanaged<CFArray>?
    guard AudioObjectGetPropertyData(defaultOutput, &a, 0, nil, &size, &list) == 0, let list
    else { return nil }
    return list.takeRetainedValue() as? [String]
  }

  /// A stacked aggregate ("Multi-Output") device that plays on all `devices` at once.
  /// The first device is the clock master; the others are drift-corrected to it.
  static func createMultiOutput(_ devices: [AudioDevice]) -> AudioDeviceID? {
    destroyMultiOutput()
    guard let master = devices.first else { return nil }
    let subs: [[String: Any]] = devices.enumerated().map { i, d in
      [kAudioSubDeviceUIDKey: d.uid, kAudioSubDeviceDriftCompensationKey: i == 0 ? 0 : 1]
    }
    let description: [String: Any] = [
      kAudioAggregateDeviceNameKey: "Kitbag Multi-Output",
      kAudioAggregateDeviceUIDKey: multiUID,
      kAudioAggregateDeviceIsStackedKey: 1,
      kAudioAggregateDeviceIsPrivateKey: 0,
      kAudioAggregateDeviceMainSubDeviceKey: master.uid,
      kAudioAggregateDeviceSubDeviceListKey: subs,
    ]
    var id: AudioObjectID = 0
    return AudioHardwareCreateAggregateDevice(description as CFDictionary, &id) == 0 ? id : nil
  }

  static func destroyMultiOutput() {
    var a = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == 0 else { return }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(system, &a, 0, nil, &size, &ids) == 0 else { return }
    for id in ids where uid(id) == multiUID { AudioHardwareDestroyAggregateDevice(id) }
  }

  static func defaultDevice(input: Bool) -> AudioDeviceID {
    var id: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var a = address(
      input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
    AudioObjectGetPropertyData(system, &a, 0, nil, &size, &id)
    return id
  }

  /// Sets the default device. For outputs the system-sound output follows on a best-effort basis.
  @discardableResult
  static func setDefault(_ device: AudioDeviceID, input: Bool) -> Bool {
    func set(_ selector: AudioObjectPropertySelector) -> Bool {
      var id = device
      var a = address(selector)
      return AudioObjectSetPropertyData(
        system, &a, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id) == 0
    }
    if input { return set(kAudioHardwarePropertyDefaultInputDevice) }
    let ok = set(kAudioHardwarePropertyDefaultOutputDevice)
    _ = set(kAudioHardwarePropertyDefaultSystemOutputDevice)
    return ok
  }

  private static func name(_ id: AudioDeviceID) -> String {
    var ref: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var a = address(kAudioObjectPropertyName)
    guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &ref) == 0, let ref else {
      return "Device \(id)"
    }
    return ref.takeRetainedValue() as String
  }

  private static func transport(_ id: AudioDeviceID) -> UInt32 {
    var value: UInt32 = 0
    var size = UInt32(4)
    var a = address(kAudioDevicePropertyTransportType)
    AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value)
    return value
  }

  private static func isHidden(_ id: AudioDeviceID) -> Bool {
    var value: UInt32 = 0
    var size = UInt32(4)
    var a = address(kAudioDevicePropertyIsHidden)
    return AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == 0 && value != 0
  }

  private static func channels(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Int {
    var a = address(kAudioDevicePropertyStreamConfiguration, scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == 0, size > 0 else { return 0 }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, raw) == 0 else { return 0 }
    let list = UnsafeMutableAudioBufferListPointer(
      raw.assumingMemoryBound(to: AudioBufferList.self))
    return list.reduce(0) { $0 + Int($1.mNumberChannels) }
  }
}
