import Foundation
import SwiftUI
import Testing

@testable import KitbagCore

@MainActor
private final class FakeTool: KitbagTool {
  struct Boom: Error {}
  static var created = 0
  var starts = 0
  var stops = 0
  var visible: Bool?
  let fails: Bool
  init(fails: Bool = false) {
    self.fails = fails
    Self.created += 1
  }
  func start() throws {
    if fails { throw Boom() }
    starts += 1
  }
  func stop() { stops += 1 }
  func menuVisibilityChanged(_ v: Bool) { visible = v }
  var senders: [FileSender] = []
  var provided: [FileSender] = []
  var fileSenders: [FileSender] { provided }
  func receiveFileSenders(_ s: [FileSender]) { senders = s }
  func makeMenuView() -> AnyView { AnyView(EmptyView()) }
}

@MainActor @Suite(.serialized) final class ToolManagerTests {
  private let defaults = UserDefaults(suiteName: "kitbag.tests.\(UUID().uuidString)")!
  private var made: [String: FakeTool] = [:]

  init() { FakeTool.created = 0 }

  private func descriptor(_ id: String, fails: Bool = false) -> ToolDescriptor {
    ToolDescriptor(id: id, name: LocalizedStringKey(id), symbol: "star", defaultEnabled: false) {
      [unowned self] in
      let t = FakeTool(fails: fails)
      self.made[id] = t
      return t
    }
  }

  @Test func nothingCreatedUntilEnabled() {
    let m = ToolManager(descriptors: [descriptor("a"), descriptor("b")], defaults: defaults)
    m.bootstrap()
    #expect(FakeTool.created == 0)
    m.setEnabled("a", true)
    #expect(FakeTool.created == 1)
    #expect(m.active["b"] == nil)
  }

  @Test func disableStopsAndReleasesInstance() {
    let m = ToolManager(descriptors: [descriptor("a")], defaults: defaults)
    m.setEnabled("a", true)
    weak var weakTool = made["a"]
    let tool = made.removeValue(forKey: "a")!
    m.setEnabled("a", false)
    #expect(tool.stops == 1)
    #expect(m.active["a"] == nil)
    _ = tool  // keep alive until after the assertions above
    #expect(weakTool != nil)
  }

  @Test func instanceDeallocatedAfterDisable() {
    let m = ToolManager(descriptors: [descriptor("a")], defaults: defaults)
    m.setEnabled("a", true)
    weak var weakTool: FakeTool? = made["a"]
    made.removeAll()
    m.setEnabled("a", false)
    #expect(weakTool == nil)
  }

  @Test func togglingOneToolDoesNotDisturbAnother() {
    let m = ToolManager(descriptors: [descriptor("a"), descriptor("b")], defaults: defaults)
    m.setEnabled("a", true)
    m.setEnabled("b", true)
    let b = made["b"]!
    m.setEnabled("a", false)
    m.setEnabled("a", true)
    #expect(b.starts == 1)
    #expect(b.stops == 0)
    #expect(m.active["b"] != nil)
  }

  @Test func failingToolIsContained() {
    let m = ToolManager(
      descriptors: [descriptor("bad", fails: true), descriptor("ok")], defaults: defaults)
    m.setEnabled("bad", true)
    m.setEnabled("ok", true)
    #expect(m.active["bad"] == nil)
    #expect(m.errors["bad"] != nil)
    #expect(m.active["ok"] != nil)
    #expect(made["bad"]?.stops == 1)
  }

  @Test func visibilityReachesOnlyActiveTools() {
    let m = ToolManager(descriptors: [descriptor("a"), descriptor("b")], defaults: defaults)
    m.setEnabled("a", true)
    m.setVisibleTool("a")
    #expect(made["a"]?.visible == true)
    #expect(made["b"] == nil)
    m.setEnabled("b", true)  // another tab is showing, so b is not visible
    #expect(made["b"]?.visible == false)
    m.setVisibleTool("b")
    #expect(made["a"]?.visible == false)
    #expect(made["b"]?.visible == true)
    m.setVisibleTool(nil)
    #expect(made["b"]?.visible == false)
  }

  @Test func integrationsNeedTheirAppInstalled() {
    let d = ToolDescriptor(
      id: "x", name: "x", symbol: "star", requiresApp: "com.example.app",
      make: { FakeTool() })
    let missing = ToolManager(descriptors: [d], defaults: defaults, isInstalled: { _ in false })
    missing.setEnabled("x", true)
    #expect(!missing.isAvailable(d) && missing.active["x"] == nil)
    missing.bootstrap()
    #expect(missing.active["x"] == nil)
    let present = ToolManager(
      descriptors: [d], defaults: defaults, isInstalled: { $0 == "com.example.app" })
    present.bootstrap()
    #expect(present.isAvailable(d) && present.active["x"] != nil)
  }

  @Test func fileSendersReachOtherTools() {
    let m = ToolManager(descriptors: [descriptor("a"), descriptor("b")], defaults: defaults)
    m.setEnabled("a", true)
    m.setEnabled("b", true)
    made["b"]!.provided = [
      FileSender(
        id: "x", title: "X", icon: { AnyView(EmptyView()) },
        send: { _ in FileSendResult(success: true) })
    ]
    m.setEnabled("a", false)
    m.setEnabled("a", true)  // republishes
    #expect(made["a"]?.senders.map(\.id) == ["x"])
  }

  @Test func menuExtraMatchingUsesIdentifierThenTitle() {
    #expect(
      MenuExtra.matches(
        identifier: "com.apple.menuextra.wifi", text: nil, wantedID: "com.apple.menuextra.wifi",
        wantedText: "Wi-Fi"))
    #expect(
      MenuExtra.matches(
        identifier: nil, text: "Wi-Fi, connected", wantedID: "x", wantedText: "wi-fi"))
    #expect(
      !MenuExtra.matches(identifier: "other", text: "Battery", wantedID: "x", wantedText: "Wi-Fi"))
  }

  @Test func enabledStatePersists() {
    ToolManager(descriptors: [descriptor("a")], defaults: defaults).setEnabled("a", true)
    let b = ToolManager(descriptors: [descriptor("a")], defaults: defaults)
    b.bootstrap()
    #expect(b.active["a"] != nil)
  }

  /// Tools may depend only on KitbagCore, never on each other.
  @Test func toolModulesDoNotImportEachOther() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let tools = root.appendingPathComponent("Tools")
    let names = try FileManager.default.contentsOfDirectory(atPath: tools.path).filter {
      !$0.hasPrefix(".")
    }
    #expect(names.count >= 2)
    for name in names {
      let files = FileManager.default.enumerator(
        at: tools.appendingPathComponent(name), includingPropertiesForKeys: nil)!
      for case let f as URL in files where f.pathExtension == "swift" {
        let text = try String(contentsOf: f, encoding: .utf8)
        for other in names where other != name {
          #expect(!text.contains("import \(other)"), "\(f.lastPathComponent) imports \(other)")
        }
      }
    }
  }
}
