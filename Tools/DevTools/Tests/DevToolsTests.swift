import AppKit
import Foundation
import Testing

@testable import DevTools

@MainActor @Suite struct DevToolsTests {
  @Test func colorFormats() {
    let c = ColorValue(r: 255, g: 128, b: 0)
    #expect(c.hex == "#FF8000")
    #expect(c.rgb == "rgb(255, 128, 0)")
    #expect(c.hsl == "hsl(30, 100%, 50%)")
    #expect(ColorValue(r: 0, g: 0, b: 0).hsl == "hsl(0, 0%, 0%)")
    #expect(ColorValue(r: 300, g: -5, b: 10).hex == "#FF000A")  // clamped
  }

  @Test func colorFromNSColor() {
    let c = ColorValue(NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
    #expect(c?.hex == "#0000FF")
  }

  @Test func measurementText() {
    let m = Measurement(points: CGSize(width: 100.4, height: 50), scale: 2)
    #expect(m.pointsText == "100 × 50 pt")
    #expect(m.pixelsText == "201 × 100 px")
  }

  @Test func doesNotAcceptFileDrops() {
    #expect(!DevToolsTool().acceptsFileDrops)
  }

  @Test func versionParsing() {
    #expect(VersionsModel.sorted(["v20.9.0", "v18.20.1", "v20.11.0"]) == ["v18.20.1", "v20.9.0", "v20.11.0"])
    #expect(VersionsModel.parseNodeDefault("v20.11.0\n") == "v20.11.0")
    #expect(VersionsModel.parseNodeDefault("N/A\n") == nil)
    let node = "       v18.19.0   (LTS: Hydrogen)\n       v18.20.1   (Latest LTS: Hydrogen)\n->     v20.11.0   (Latest LTS: Iron)\n"
    #expect(VersionsModel.parseNodeAvailable(node) == ["node", "v20.11.0", "v18.20.1"])
    let py = "Available versions:\n  2.7.18\n  3.11.8\n  3.12.1\n  3.12.2\n  3.13-dev\n  pypy3.10-7.3.15\n"
    #expect(VersionsModel.parsePythonAvailable(py) == ["3.12.2", "3.11.8"])
    #expect(!VersionsModel.isVersion("20; rm -rf /"))
  }
}

@Suite struct VersionErrorTests {
  @Test func failureReasons() {
    #expect(VersionsModel.failureReason("pyenv: definition not found: 3.99.9", k: .python, version: "3.99.9").contains("doesn't exist"))
    #expect(VersionsModel.failureReason("Version '99.1.1' not found - try `nvm ls-remote`", k: .node, version: "99.1.1").contains("doesn't exist"))
  }
}
