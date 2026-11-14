import Darwin
import Foundation
import IOKit
import IOKit.ps

struct BatteryInfo: Equatable {
  var percent: Double  // 0...1
  var charging: Bool
  var onAC: Bool
  var health: Double?  // maximum capacity vs design capacity, 0...1
  var cycles: Int?
}

struct SystemSnapshot: Equatable {
  var cpu: Double = 0  // 0...1
  var memoryUsed: UInt64 = 0
  var memoryTotal: UInt64 = 0
  var storageUsed: UInt64 = 0
  var storageTotal: UInt64 = 0
  var netDown: Double = 0  // bytes/s
  var netUp: Double = 0
  var battery: BatteryInfo?
}

/// All samplers use direct system APIs (no subprocesses).
struct SystemSampler {
  private var prevCPU: [UInt32]?
  private var prevNet: [String: (rx: UInt32, tx: UInt32)] = [:]
  private var prevTime: Date?
  private var storage: (used: UInt64, total: UInt64) = (0, 0)
  private var ticks = 0
  private var health: (health: Double, cycles: Int)?

  mutating func sample(now: Date = Date()) -> SystemSnapshot {
    var s = SystemSnapshot()
    let dt = prevTime.map { now.timeIntervalSince($0) } ?? 0
    prevTime = now

    // CPU
    if let cur = Self.cpuTicks() {
      if let p = prevCPU { s.cpu = Self.cpuUsage(prev: p, cur: cur) }
      prevCPU = cur
    }
    // Memory
    (s.memoryUsed, s.memoryTotal) = Self.memory()
    // Storage changes slowly: refresh about every 15 samples.
    // Battery health changes even more slowly.
    if ticks % 15 == 0 {
      storage = Self.storage()
      health = Self.batteryHealth()
    }
    ticks += 1
    (s.storageUsed, s.storageTotal) = storage
    // Network
    let net = Self.netCounters()
    var down: UInt64 = 0
    var up: UInt64 = 0
    for (name, cur) in net {
      if let p = prevNet[name] {
        down += UInt64(cur.rx &- p.rx)
        up += UInt64(cur.tx &- p.tx)
      }
    }
    prevNet = net
    if dt > 0 {
      s.netDown = Double(down) / dt
      s.netUp = Double(up) / dt
    }
    s.battery = Self.battery()
    s.battery?.health = health?.health
    s.battery?.cycles = health?.cycles
    return s
  }

  /// Forces storage/battery health to refresh on the next sample (call when polling restarts).
  mutating func reset() { ticks = 0 }

  // MARK: pure helpers (tested)

  /// Ticks are user, system, idle, nice. Subtraction wraps (32-bit counters).
  static func cpuUsage(prev: [UInt32], cur: [UInt32]) -> Double {
    let d = zip(cur, prev).map { Double($0 &- $1) }
    let total = d.reduce(0, +)
    guard total > 0 else { return 0 }
    return (total - d[2]) / total
  }

  // MARK: system calls

  static func cpuTicks() -> [UInt32]? {
    var info = host_cpu_load_info()
    var count = mach_msg_type_number_t(
      MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
      }
    }
    guard kr == KERN_SUCCESS else { return nil }
    let t = info.cpu_ticks
    return [t.0, t.1, t.2, t.3]
  }

  static func memory() -> (used: UInt64, total: UInt64) {
    let total = ProcessInfo.processInfo.physicalMemory
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(
      MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &stats) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
      }
    }
    guard kr == KERN_SUCCESS else { return (0, total) }
    // Activity Monitor's "Memory Used": app (internal - purgeable) + wired + compressed.
    let pages =
      UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)
      &+ UInt64(stats.wire_count) &+ UInt64(stats.compressor_page_count)
    return (min(pages &* UInt64(getpagesize()), total), total)
  }

  static func storage() -> (used: UInt64, total: UInt64) {
    let keys: Set<URLResourceKey> = [
      .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
    ]
    guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
      let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage
    else { return (0, 0) }
    return (UInt64(max(0, Int64(total) - free)), UInt64(total))
  }

  /// Per-interface 32-bit byte counters for physical ("en*") interfaces.
  static func netCounters() -> [String: (rx: UInt32, tx: UInt32)] {
    var result: [String: (rx: UInt32, tx: UInt32)] = [:]
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0, let first = head else { return result }
    defer { freeifaddrs(head) }
    for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
      let ifa = ptr.pointee
      guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
        let data = ifa.ifa_data
      else { continue }
      let name = String(cString: ifa.ifa_name)
      guard name.hasPrefix("en"), ifa.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
      let d = data.assumingMemoryBound(to: if_data.self).pointee
      result[name] = (d.ifi_ibytes, d.ifi_obytes)
    }
    return result
  }

  static func batteryHealth() -> (health: Double, cycles: Int)? {
    let svc = IOServiceGetMatchingService(
      kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard svc != 0 else { return nil }
    defer { IOObjectRelease(svc) }
    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
      let top = props?.takeRetainedValue() as? [String: Any]
    else { return nil }
    let d = top["BatteryData"] as? [String: Any] ?? top
    let cycles = (top["CycleCount"] as? NSNumber)?.intValue ?? 0
    // Apple Silicon reports Maximum Capacity as a percentage (what System Settings shows).
    if let pct = (top["MaxCapacity"] as? NSNumber)?.doubleValue, pct <= 100 {
      return (pct / 100, cycles)
    }
    guard let design = (d["DesignCapacity"] as? NSNumber)?.doubleValue, design > 0,
      let now = ((d["NominalChargeCapacity"] ?? d["AppleRawMaxCapacity"]) as? NSNumber)?.doubleValue
    else { return nil }
    return (min(now / design, 1), cycles)
  }

  static func battery() -> BatteryInfo? {
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
    else { return nil }
    for ps in list {
      guard
        let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
        d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
        let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int,
        max > 0
      else { continue }
      return BatteryInfo(
        percent: Double(cur) / Double(max),
        charging: d[kIOPSIsChargingKey] as? Bool ?? false,
        onAC: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
        health: nil, cycles: nil)
    }
    return nil
  }
}
