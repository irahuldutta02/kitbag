// Usage: swift scripts/render-svg.swift in.svg out.png [size]
// Renders an SVG to a transparent PNG with AppKit (Quick Look adds an opaque white background).
import AppKit

let args = CommandLine.arguments
guard args.count >= 3, let image = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else {
  FileHandle.standardError.write(Data("cannot read SVG\n".utf8))
  exit(1)
}
let side = args.count > 3 ? Int(args[3]) ?? 1024 : 1024
guard
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)
else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
