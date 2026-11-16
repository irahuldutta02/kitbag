import Foundation
import Testing

@testable import SystemMonitor

@MainActor @Suite struct SamplerTests {
  @Test func cpuUsageMath() {
    #expect(SystemSampler.cpuUsage(prev: [0, 0, 0, 0], cur: [30, 20, 50, 0]) == 0.5)
    #expect(SystemSampler.cpuUsage(prev: [5, 5, 5, 5], cur: [5, 5, 5, 5]) == 0)
    // 32-bit counter wrap
    #expect(SystemSampler.cpuUsage(prev: [UInt32.max - 9, 0, 0, 0], cur: [10, 0, 20, 0]) == 0.5)
  }

  @Test func liveSnapshotIsSane() {
    var s = SystemSampler()
    _ = s.sample()
    let snap = s.sample(now: Date().addingTimeInterval(1))
    #expect((0...1).contains(snap.cpu))
    #expect(snap.memoryTotal > 0)
    #expect(snap.memoryUsed <= snap.memoryTotal)
    #expect(snap.storageTotal > 0)
    #expect(snap.netDown >= 0)
    if let h = snap.battery?.health { #expect((0...1).contains(h)) }
  }

  @Test func processesAreGroupedBySource() {
    let helper =
      "/Applications/Google Chrome.app/Contents/Frameworks/X.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
    let main = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    #expect(ProcessSampler.groupKey(path: helper).id == ProcessSampler.groupKey(path: main).id)
    #expect(ProcessSampler.groupKey(path: main).name == "Google Chrome")
    let daemon = ProcessSampler.groupKey(path: "/usr/libexec/mds_stores")
    #expect(daemon.name == "mds_stores")
    #expect(daemon.appPath == nil)
  }

  @Test func liveProcessListIsGroupedAndIncludesSelf() {
    var p = ProcessSampler()
    let groups = p.sample()
    #expect(!groups.isEmpty)
    #expect(groups.contains { $0.pids.contains(getpid()) && $0.isSelf })
    #expect(groups.allSatisfy { $0.pids.count == $0.members.count })
    #expect(Set(groups.map(\.id)).count == groups.count)
  }

  @Test func timerRunsOnlyWhileActiveAndCollapsesOnHide() {
    let m = MonitorModel(defaults: UserDefaults(suiteName: "kitbag.sm.\(UUID().uuidString)")!)
    #expect(m.timer == nil)
    m.setActive(true)
    #expect(m.timer != nil)
    m.tick()
    #expect(m.snapshot != nil)
    m.toggle(.cpu)
    #expect(m.expanded == .cpu)
    m.setActive(false)
    #expect(m.timer == nil)
    #expect(m.expanded == nil)
    #expect(m.groups.isEmpty)
    #expect(m.snapshot == nil)
  }

  @Test func doesNotAcceptFileDrops() {
    #expect(!SystemMonitorTool().acceptsFileDrops)
  }
}

@MainActor @Suite struct BatteryHealthTests {
  @Test func appleSiliconUsesNominalOverDesign() {
    let r = SystemSampler.computeHealth(design: 4629, nominal: 4465, rawMax: 4338, maxCapacity: 100, cycles: 22)
    #expect(r?.cycles == 22)
    #expect(abs((r?.health ?? 0) - 4465.0 / 4629.0) < 0.0001)
  }

  @Test func intelUsesMaxCapacityInMilliamps() {
    let r = SystemSampler.computeHealth(design: 6000, nominal: nil, rawMax: nil, maxCapacity: 5100, cycles: 300)
    #expect(abs((r?.health ?? 0) - 0.85) < 0.0001)
  }

  @Test func chargeScaleMaxCapacityIsNotHealth() {
    #expect(SystemSampler.computeHealth(design: 4629, nominal: nil, rawMax: nil, maxCapacity: 100, cycles: 5) == nil)
  }

  @Test func missingCyclesIsNotZero() {
    let r = SystemSampler.computeHealth(design: 4629, nominal: 4400, rawMax: nil, maxCapacity: nil, cycles: nil)
    #expect(r != nil && r?.cycles == nil)
  }
}
