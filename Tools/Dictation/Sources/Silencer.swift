import CoreAudio
import Foundation

/// Keeps the Mac quiet while you dictate: mutes the default output, then puts it back exactly as it was.
///
/// Nothing is paused or played, so no app is touched; the sound just isn't heard. If the output has
/// no mute switch the volume is lowered to zero instead. If you change the volume or mute yourself
/// during dictation, that choice is respected and not overwritten.
@MainActor
final class Silencer {
  private struct Saved: Codable {
    var deviceUID: String
    var useMute: Bool
    var values: [UInt32: Float]  // element -> value to restore
  }

  private static let key = "kitbag.silencer.pending"
  private var saved: Saved?

  init() {
    restoreLeftover()
  }

  /// Mutes the current default output. Does nothing if already silenced.
  func silence() {
    guard saved == nil, let device = Self.defaultOutput(), let uid = Self.uid(device) else { return }
    var values: [UInt32: Float] = [:]
    var useMute = true
    for element in Self.elements where Self.settable(device, kAudioDevicePropertyMute, element) {
      if let v = Self.get(device, kAudioDevicePropertyMute, element) { values[element] = v }
    }
    if values.isEmpty {
      useMute = false
      for element in Self.elements where Self.settable(device, kAudioDevicePropertyVolumeScalar, element) {
        if let v = Self.get(device, kAudioDevicePropertyVolumeScalar, element) { values[element] = v }
      }
    }
    guard !values.isEmpty else { return }  // this output can't be silenced
    let selector = useMute ? kAudioDevicePropertyMute : kAudioDevicePropertyVolumeScalar
    // Already muted or at zero: nothing to do and nothing to restore.
    guard values.values.contains(where: { useMute ? $0 == 0 : $0 > 0 }) else { return }
    for element in values.keys { Self.set(device, selector, element, useMute ? 1 : 0) }
    let s = Saved(deviceUID: uid, useMute: useMute, values: values)
    saved = s
    if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: Self.key) }
  }

  /// Puts the sound back, unless the person changed it meanwhile.
  func restore() {
    guard let s = saved else { return }
    saved = nil
    UserDefaults.standard.removeObject(forKey: Self.key)
    apply(s)
  }

  /// After a crash or force quit the output could have been left muted; fix that on the next launch.
  private func restoreLeftover() {
    guard let data = UserDefaults.standard.data(forKey: Self.key),
      let s = try? JSONDecoder().decode(Saved.self, from: data)
    else { return }
    UserDefaults.standard.removeObject(forKey: Self.key)
    apply(s)
  }

  private func apply(_ s: Saved) {
    guard let device = Self.device(uid: s.deviceUID) else { return }  // headphones gone: nothing to fix
    let selector = s.useMute ? kAudioDevicePropertyMute : kAudioDevicePropertyVolumeScalar
    for (element, value) in s.values {
      // Still at the silenced value? Otherwise the person changed it and it is left alone.
      guard let now = Self.get(device, selector, element), now == (s.useMute ? 1 : 0) else { continue }
      Self.set(device, selector, element, value)
    }
  }

  // MARK: Core Audio

  private static let elements: [UInt32] = [0, 1, 2]  // main, left, right

  private static func address(_ selector: AudioObjectPropertySelector, _ element: UInt32) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
  }

  private static func settable(_ d: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ element: UInt32) -> Bool {
    var a = address(selector, element)
    guard AudioObjectHasProperty(d, &a) else { return false }
    var settable: DarwinBoolean = false
    return AudioObjectIsPropertySettable(d, &a, &settable) == noErr && settable.boolValue
  }

  private static func get(_ d: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ element: UInt32) -> Float? {
    var a = address(selector, element)
    if selector == kAudioDevicePropertyMute {
      var v: UInt32 = 0
      var size = UInt32(MemoryLayout<UInt32>.size)
      return AudioObjectGetPropertyData(d, &a, 0, nil, &size, &v) == noErr ? Float(v) : nil
    }
    var v: Float32 = 0
    var size = UInt32(MemoryLayout<Float32>.size)
    return AudioObjectGetPropertyData(d, &a, 0, nil, &size, &v) == noErr ? v : nil
  }

  private static func set(_ d: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ element: UInt32, _ value: Float) {
    var a = address(selector, element)
    if selector == kAudioDevicePropertyMute {
      var v = UInt32(value)
      AudioObjectSetPropertyData(d, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
    } else {
      var v = value
      AudioObjectSetPropertyData(d, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
    }
  }

  private static func defaultOutput() -> AudioDeviceID? {
    var a = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr, id != 0
    else { return nil }
    return id
  }

  private static func uid(_ d: AudioDeviceID) -> String? {
    var a = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceUID,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var ref: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(d, &a, 0, nil, &size, &ref) == noErr else { return nil }
    return ref?.takeRetainedValue() as String?
  }

  private static func device(uid: String) -> AudioDeviceID? {
    var a = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr else { return nil }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(system, &a, 0, nil, &size, &ids) == noErr else { return nil }
    return ids.first { Self.uid($0) == uid }
  }
}
