import Foundation
import Testing

@testable import FileShelf

@MainActor @Suite final class ShelfModelTests {
  private let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  private let defaults = UserDefaults(suiteName: "kitbag.fileshelf.\(UUID().uuidString)")!

  init() throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }
  deinit { try? FileManager.default.removeItem(at: dir) }

  private func file(_ name: String, text: String = "x") throws -> URL {
    let u = dir.appendingPathComponent(name)
    try text.write(to: u, atomically: true, encoding: .utf8)
    return u
  }

  @Test func addRemoveClearAndDuplicates() throws {
    let m = ShelfModel(defaults: defaults)
    let a = try file("a.txt")
    let b = try file("b.txt")
    m.add([a, b, a])
    #expect(m.items.count == 2)
    m.remove(m.items[0].id)
    #expect(m.items.count == 1)
    m.clear()
    #expect(m.items.isEmpty)
  }

  @Test func itemsPersistAsBookmarksOnly() throws {
    let m = ShelfModel(defaults: defaults)
    m.add([try file("a.txt", text: String(repeating: "z", count: 100_000))])
    #expect(defaults.data(forKey: "fileshelf.items")!.count < 5_000)
    let m2 = ShelfModel(defaults: defaults)
    #expect(m2.items.count == 1)
    #expect(m2.url(for: m2.items[0].id) != nil)
  }

  @Test func missingSourceIsFlagged() throws {
    let m = ShelfModel(defaults: defaults)
    let a = try file("a.txt")
    m.add([a])
    try FileManager.default.removeItem(at: a)
    m.refresh()
    #expect(m.missing == [m.items[0].id])
    #expect(m.url(for: m.items[0].id) == nil)
  }

  @Test func movedSourceIsFollowed() throws {
    let m = ShelfModel(defaults: defaults)
    let a = try file("a.txt")
    m.add([a])
    let sub = dir.appendingPathComponent("elsewhere")
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: a, to: sub.appendingPathComponent("renamed.txt"))
    m.refresh()
    #expect(m.missing.isEmpty)
    #expect(m.items[0].name == "renamed.txt")
  }

  @Test func restoredFileIsNotAddedTwice() throws {
    let m = ShelfModel(defaults: defaults)
    let a = try file("a.txt")
    m.add([a])
    try FileManager.default.removeItem(at: a)
    m.refresh()
    _ = try file("a.txt")
    m.add([a])
    #expect(m.items.count == 1)
  }

  @Test func shelfIsCapped() throws {
    let m = ShelfModel(defaults: defaults)
    m.add(try (0..<(ShelfModel.maxItems + 5)).map { try file("f\($0).txt") })
    #expect(m.items.count == ShelfModel.maxItems)
  }

  @Test func settingsPersist() {
    let m = ShelfModel(defaults: defaults)
    m.mode = .move
    m.clearAfterDrop = true
    let m2 = ShelfModel(defaults: defaults)
    #expect(m2.mode == .move)
    #expect(m2.clearAfterDrop)
  }

  @Test func acceptsFileDrops() {
    #expect(FileShelfTool().acceptsFileDrops)
  }
}
