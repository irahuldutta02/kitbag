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
}
