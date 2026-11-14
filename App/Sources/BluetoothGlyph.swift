import SwiftUI

/// The Bluetooth rune (SF Symbols has no Bluetooth glyph). Takes the surrounding foreground color.
struct BluetoothGlyph: View {
  var body: some View {
    RuneShape().stroke(style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
  }

  private struct RuneShape: Shape {
    func path(in rect: CGRect) -> Path {
      func p(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
      }
      var path = Path()
      path.move(to: p(0, 0.28))
      path.addLine(to: p(1, 0.72))
      path.addLine(to: p(0.5, 1))
      path.addLine(to: p(0.5, 0))
      path.addLine(to: p(1, 0.28))
      path.addLine(to: p(0, 0.72))
      return path
    }
  }
}
