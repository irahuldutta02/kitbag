import AppKit
import SwiftUI

/// An sRGB color with the text formats developers paste around.
struct ColorValue: Equatable, Identifiable {
  let r: Int
  let g: Int
  let b: Int
  var id: String { hex }

  init(r: Int, g: Int, b: Int) {
    self.r = min(max(r, 0), 255)
    self.g = min(max(g, 0), 255)
    self.b = min(max(b, 0), 255)
  }

  init?(_ color: NSColor) {
    guard let c = color.usingColorSpace(.sRGB) else { return nil }
    self.init(
      r: Int((c.redComponent * 255).rounded()), g: Int((c.greenComponent * 255).rounded()),
      b: Int((c.blueComponent * 255).rounded()))
  }

  var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
  var rgb: String { "rgb(\(r), \(g), \(b))" }

  var hsl: String {
    let (rf, gf, bf) = (Double(r) / 255, Double(g) / 255, Double(b) / 255)
    let hi = max(rf, gf, bf)
    let lo = min(rf, gf, bf)
    let l = (hi + lo) / 2
    var h = 0.0
    var s = 0.0
    if hi != lo {
      let d = hi - lo
      s = l > 0.5 ? d / (2 - hi - lo) : d / (hi + lo)
      switch hi {
      case rf: h = (gf - bf) / d + (gf < bf ? 6 : 0)
      case gf: h = (bf - rf) / d + 2
      default: h = (rf - gf) / d + 4
      }
      h *= 60
    }
    return "hsl(\(Int(h.rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
  }

  var color: Color {
    Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
  }
}

struct Measurement: Equatable {
  let points: CGSize
  let scale: CGFloat

  var pointsText: String { "\(Int(points.width.rounded())) × \(Int(points.height.rounded())) pt" }
  var pixelsText: String {
    "\(Int((points.width * scale).rounded())) × \(Int((points.height * scale).rounded())) px"
  }
}
