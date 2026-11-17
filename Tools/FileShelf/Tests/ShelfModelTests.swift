import AppKit
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

@Suite struct ConverterTests {
  private func tempDir() throws -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
  }

  private func png(in dir: URL, name: String = "a.png") throws -> URL {
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 10, bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let u = dir.appendingPathComponent(name)
    try rep.representation(using: .png, properties: [:])!.write(to: u)
    return u
  }

  @Test func offersOnlySensibleFormats() throws {
    let d = try tempDir()
    let p = try png(in: d)
    let t = d.appendingPathComponent("n.txt")
    try "x".write(to: t, atomically: true, encoding: .utf8)
    #expect(!Converter.formats(for: [p]).contains(.png))  // already a PNG
    #expect(Converter.formats(for: [p]).contains(.jpeg))
    #expect(Converter.formats(for: [t]).contains(.pdf))  // text can become PDF, RTF, DOCX…
    #expect(!Converter.formats(for: [t]).contains(.txt))
    #expect(Converter.formats(for: [d]) == [.zip])  // folders can only be zipped
  }

  @Test func convertsWithoutOverwriting() throws {
    let d = try tempDir()
    let p = try png(in: d)
    let first = try Converter.convert(p, to: .jpeg, quality: 0.8, into: d)
    let second = try Converter.convert(p, to: .jpeg, quality: 0.8, into: d)
    #expect(first[0].lastPathComponent == "a.jpg")
    #expect(second[0].lastPathComponent == "a 2.jpg")
  }

  @Test func mergesAndSplitsPDF() throws {
    let d = try tempDir()
    let a = try png(in: d, name: "a.png")
    let b = try png(in: d, name: "b.png")
    let merged = try Converter.merge([a, b], into: d)
    #expect(try Converter.convert(merged.output, to: .png, quality: 1, into: d).count == 2)
  }

  @Test func unreadableFileIsAnError() throws {
    let d = try tempDir()
    let bad = d.appendingPathComponent("bad.png")
    try "nope".write(to: bad, atomically: true, encoding: .utf8)
    #expect(throws: ConvertError.self) { try Converter.convert(bad, to: .jpeg, quality: 1, into: d) }
  }
}

@Suite struct ConverterEdgeCaseTests {
  @Test func everyKindOfFileOffersSomething() throws {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    let weird = d.appendingPathComponent("blob.xyzzy")
    try "x".write(to: weird, atomically: true, encoding: .utf8)
    #expect(Converter.formats(for: [weird]) == [.zip])
    let out = try Converter.convert(weird, to: .zip, quality: 1, into: d)
    #expect(out[0].lastPathComponent == "blob.zip")
    #expect(FileManager.default.fileExists(atPath: out[0].path))
    #expect(Converter.formats(for: [out[0]]).isEmpty)  // a zip is not zipped again
  }

  @Test func textBecomesRTFDocxAndPDF() throws {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    let t = d.appendingPathComponent("n.txt")
    try "hello world".write(to: t, atomically: true, encoding: .utf8)
    for f in [ConvertFormat.rtf, .docx, .pdf, .html] {
      let out = try Converter.convert(t, to: f, quality: 1, into: d)
      #expect(out[0].pathExtension == f.ext)
      #expect(((try? out[0].resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0)
    }
    let rtf = d.appendingPathComponent("n.rtf")
    let back = try Converter.convert(rtf, to: .txt, quality: 1, into: d)
    #expect(try String(contentsOf: back[0], encoding: .utf8).contains("hello world"))
  }

  @Test func svgIsAnImage() throws {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    let svg = d.appendingPathComponent("v.svg")
    try "<svg xmlns='http://www.w3.org/2000/svg' width='40' height='20'><rect width='40' height='20' fill='red'/></svg>"
      .write(to: svg, atomically: true, encoding: .utf8)
    #expect(Converter.kind(of: svg) == .image)
    let out = try Converter.convert(svg, to: .png, quality: 1, into: d)
    #expect(NSImage(contentsOf: out[0]) != nil)
  }

  @Test func foldersAreOnlyZipped() throws {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    let svg = d.appendingPathComponent("v.svg")
    try "<svg xmlns='http://www.w3.org/2000/svg'/>".write(to: svg, atomically: true, encoding: .utf8)
    #expect(Converter.kind(of: d) == .other)
  }

  @Test func mergedNames() {
    let a = URL(fileURLWithPath: "/x/a.png"), b = URL(fileURLWithPath: "/x/b.pdf")
    #expect(Converter.mergedName([a, b]) == "a + b")
    #expect(Converter.mergedName([a, b, a]) == "a + 2 more")
  }
}
