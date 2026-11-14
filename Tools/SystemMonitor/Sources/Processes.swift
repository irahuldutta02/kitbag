import AppKit
import Darwin

/// Processes from one source (e.g. an app and all its helpers) shown as a single row.
struct ProcessEntry: Identifiable, Equatable {
  let pid: pid_t
  let name: String
  var cpu: Double  // percent of one core; may exceed 100
  var memory: UInt64  // physical footprint
  var id: pid_t { pid }
}

struct ProcessGroup: Identifiable, Equatable {
  let id: String
  let name: String
  let appPath: String?
  var members: [ProcessEntry] = []
  var pids: [pid_t] { members.map(\.pid) }
  var isSelf: Bool { pids.contains(getpid()) }
  var cpu: Double { members.reduce(0) { $0 + $1.cpu } }
  var memory: UInt64 { members.reduce(0) { $0 &+ $1.memory } }
}

struct ProcessSampler {
  private var prevCPU: [pid_t: UInt64] = [:]
  private var prevTime: UInt64?
  private let timebase: mach_timebase_info_data_t = {
    var t = mach_timebase_info_data_t()
    mach_timebase_info(&t)
    return t
  }()

  /// Groups by the outermost .app bundle; other processes group by executable name.
  static func groupKey(path: String) -> (id: String, name: String, appPath: String?) {
    if let r = path.range(of: ".app/") {
      let app = String(path[..<r.lowerBound]) + ".app"
      let name = ((app as NSString).lastPathComponent as NSString).deletingPathExtension
      return (app, name, app)
    }
    let name = (path as NSString).lastPathComponent
    return (name, name, nil)
  }

  /// CPU is measured since the previous call, so the first call reports 0 for CPU.
  mutating func sample() -> [ProcessGroup] {
    let now = DispatchTime.now().uptimeNanoseconds
    let wall = prevTime.map { Double(now &- $0) } ?? 0
    prevTime = now

    let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
    guard bytes > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: Int(bytes) / MemoryLayout<pid_t>.size + 32)
    let got = proc_listpids(
      UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
    guard got > 0 else { return [] }

    var groups: [String: ProcessGroup] = [:]
    var cpuNow: [pid_t: UInt64] = [:]
    var pathBuf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    for pid in pids.prefix(Int(got) / MemoryLayout<pid_t>.size) where pid > 0 {
      var ti = proc_taskinfo()
      let size = Int32(MemoryLayout<proc_taskinfo>.size)
      guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, size) == size,
        proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count)) > 0
      else { continue }
      let ticks = ti.pti_total_user &+ ti.pti_total_system
      let cpuNs = ticks &* UInt64(timebase.numer) / UInt64(timebase.denom)
      cpuNow[pid] = cpuNs
      var cpu = 0.0
      if wall > 0, let p = prevCPU[pid], cpuNs >= p { cpu = Double(cpuNs - p) / wall * 100 }

      var ri = rusage_info_v4()
      let ok = withUnsafeMutablePointer(to: &ri) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
          proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
        }
      }
      let mem = ok == 0 ? ri.ri_phys_footprint : ti.pti_resident_size

      let key = Self.groupKey(path: String(cString: pathBuf))
      var g = groups[key.id] ?? ProcessGroup(id: key.id, name: key.name, appPath: key.appPath)
      g.members.append(
        ProcessEntry(
          pid: pid, name: (String(cString: pathBuf) as NSString).lastPathComponent, cpu: cpu,
          memory: mem))
      groups[key.id] = g
    }
    prevCPU = cpuNow
    return Array(groups.values)
  }
}
