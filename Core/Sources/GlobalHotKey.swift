import Carbon.HIToolbox
import Foundation

/// A system-wide shortcut (Carbon hot key). Needs no extra permission.
@MainActor
public final class GlobalHotKey {
  private static var nextID: UInt32 = 1
  private static var table: [UInt32: GlobalHotKey] = [:]
  private static var handlerInstalled = false

  private let id: UInt32
  private var ref: EventHotKeyRef?
  public var onPress: (() -> Void)?

  public init() {
    id = Self.nextID
    Self.nextID += 1
    Self.installHandler()
  }

  /// False if another app already owns this shortcut.
  @discardableResult
  public func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
    unregister()
    var newRef: EventHotKeyRef?
    let hotKeyID = EventHotKeyID(signature: OSType(0x4B54_4247), id: id)
    let status = RegisterEventHotKey(
      keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &newRef)
    guard status == noErr, let newRef else { return false }
    ref = newRef
    Self.table[id] = self
    return true
  }

  public func unregister() {
    if let ref { UnregisterEventHotKey(ref) }
    ref = nil
    Self.table[id] = nil
  }

  private static func installHandler() {
    guard !handlerInstalled else { return }
    handlerInstalled = true
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, _ -> OSStatus in
        var hk = EventHotKeyID()
        GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
          MemoryLayout<EventHotKeyID>.size, nil, &hk)
        let id = hk.id
        DispatchQueue.main.async {
          MainActor.assumeIsolated { GlobalHotKey.table[id]?.onPress?() }
        }
        return noErr
      }, 1, &spec, nil, nil)
  }
}
