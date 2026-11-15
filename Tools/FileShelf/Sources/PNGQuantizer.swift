import Compression
import CoreGraphics
import Foundation

/// Makes PNGs much smaller the way pngquant does: the picture is reduced to a palette of at most
/// 256 colors (with dithering so gradients stay smooth), keeping transparency, and written as an
/// indexed PNG.
enum PNGQuantizer {
  struct Failure: Error {}

  static func write(_ image: CGImage, colors: Int, to url: URL) throws {
    let w = image.width, h = image.height
    guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw Failure() }
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let drawn: Bool = px.withUnsafeMutableBytes { buf in
      guard let ctx = CGContext(
        data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
      return true
    }
    guard drawn else { throw Failure() }

    // Straight (not premultiplied) colors; note whether anything is see-through.
    var hasClear = false
    var hasAlpha = false
    for i in stride(from: 0, to: px.count, by: 4) {
      let a = Int(px[i + 3])
      if a == 0 { hasClear = true; hasAlpha = true }
      else if a < 255 {
        hasAlpha = true
        for c in 0..<3 { px[i + c] = UInt8(min(255, Int(px[i + c]) * 255 / a)) }
      }
    }

    let palette = makePalette(px, count: max(2, min(colors, 256) - (hasClear ? 1 : 0)))
    var entries = palette
    let clearIndex = hasClear ? 0 : -1
    if hasClear { entries.insert((0, 0, 0, 0), at: 0) }

    let indices = map(px, w: w, h: h, palette: entries, firstColor: hasClear ? 1 : 0, clearIndex: clearIndex)
    let data = png(w: w, h: h, palette: entries, indices: indices, hasAlpha: hasAlpha)
    guard let data else { throw Failure() }
    try data.write(to: url, options: .atomic)
  }

  // MARK: Palette (median cut)

  private typealias RGBA = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)

  private static func makePalette(_ px: [UInt8], count: Int) -> [RGBA] {
    // Histogram on 5-5-5-4 bit bins, keeping the exact average of each bin.
    var n = [Int](repeating: 0, count: 65536)
    var sum = [Int](repeating: 0, count: 65536 * 4)
    for i in stride(from: 0, to: px.count, by: 4) {
      let a = Int(px[i + 3])
      if a == 0 { continue }
      let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
      let key = (r >> 3) | ((g >> 3) << 5) | ((b >> 3) << 10)  // 15 bits of color
      let slot = key + (a >= 255 ? 0 : 32768)  // opaque and translucent colors kept apart
      n[slot] += 1
      sum[slot * 4] += r; sum[slot * 4 + 1] += g; sum[slot * 4 + 2] += b; sum[slot * 4 + 3] += a
    }
    var bins: [Int] = []
    for i in 0..<65536 where n[i] > 0 { bins.append(i) }
    if bins.isEmpty { return [(0, 0, 0, 255)] }

    func avg(_ b: Int, _ c: Int) -> Int { sum[b * 4 + c] / n[b] }
    var boxes: [[Int]] = [bins]
    while boxes.count < count {
      // Split the box holding the most pixels (that can still be split).
      var best = -1, bestPixels = 0
      for (i, box) in boxes.enumerated() where box.count > 1 {
        let pixels = box.reduce(0) { $0 + n[$1] }
        if pixels > bestPixels { best = i; bestPixels = pixels }
      }
      if best < 0 { break }
      let box = boxes[best]
      // Cut across the channel with the widest spread.
      var lo = [255, 255, 255, 255], hi = [0, 0, 0, 0]
      for b in box { for c in 0..<4 { let v = avg(b, c); lo[c] = min(lo[c], v); hi[c] = max(hi[c], v) } }
      var channel = 0
      for c in 1..<4 where hi[c] - lo[c] > hi[channel] - lo[channel] { channel = c }
      let sorted = box.sorted { avg($0, channel) < avg($1, channel) }
      var acc = 0
      var cut = 1
      for (i, b) in sorted.enumerated() {
        acc += n[b]
        if acc * 2 >= bestPixels { cut = max(1, min(i + 1, sorted.count - 1)); break }
      }
      boxes[best] = Array(sorted[..<cut])
      boxes.append(Array(sorted[cut...]))
    }
    return boxes.map { box in
      var t = [0, 0, 0, 0], total = 0
      for b in box { for c in 0..<4 { t[c] += sum[b * 4 + c] }; total += n[b] }
      return (UInt8(t[0] / total), UInt8(t[1] / total), UInt8(t[2] / total), UInt8(t[3] / total))
    }
  }

  // MARK: Mapping with Floyd–Steinberg dithering

  private static func map(
    _ px: [UInt8], w: Int, h: Int, palette: [RGBA], firstColor: Int, clearIndex: Int
  ) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: w * h)
    var cache = [Int16](repeating: -1, count: 65536 * 2)
    var errNow = [Float](repeating: 0, count: (w + 2) * 3)
    var errNext = [Float](repeating: 0, count: (w + 2) * 3)

    func nearest(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Int {
      var best = firstColor, bestD = Int.max
      for i in firstColor..<palette.count {
        let p = palette[i]
        let dr = r - Int(p.r), dg = g - Int(p.g), db = b - Int(p.b), da = a - Int(p.a)
        let d = dr * dr * 2 + dg * dg * 4 + db * db * 3 + da * da * 2
        if d < bestD { bestD = d; best = i }
      }
      return best
    }

    for y in 0..<h {
      for x in 0..<w {
        let i = (y * w + x) * 4
        let a = Int(px[i + 3])
        if a == 0, clearIndex >= 0 { out[y * w + x] = UInt8(clearIndex); continue }
        let e = (x + 1) * 3
        let r = max(0, min(255, Int(Float(px[i]) + errNow[e])))
        let g = max(0, min(255, Int(Float(px[i + 1]) + errNow[e + 1])))
        let b = max(0, min(255, Int(Float(px[i + 2]) + errNow[e + 2])))
        let key = (r >> 3) | ((g >> 3) << 5) | ((b >> 3) << 10) | (a >= 255 ? 0 : 32768)
        var idx = Int(cache[key])
        if idx < 0 { idx = nearest(r, g, b, a); cache[key] = Int16(idx) }
        out[y * w + x] = UInt8(idx)
        let p = palette[idx]
        let er = [Float(r - Int(p.r)), Float(g - Int(p.g)), Float(b - Int(p.b))]
        for c in 0..<3 {
          errNow[e + 3 + c] += er[c] * 7 / 16
          errNext[e - 3 + c] += er[c] * 3 / 16
          errNext[e + c] += er[c] * 5 / 16
          errNext[e + 3 + c] += er[c] * 1 / 16
        }
      }
      swap(&errNow, &errNext)
      for i in errNext.indices { errNext[i] = 0 }
    }
    return out
  }

  // MARK: PNG file

  private static func png(w: Int, h: Int, palette: [RGBA], indices: [UInt8], hasAlpha: Bool) -> Data? {
    var d = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)] }
    func chunk(_ type: String, _ body: [UInt8]) {
      d.append(contentsOf: be32(UInt32(body.count)))
      let t = Array(type.utf8) + body
      d.append(contentsOf: t)
      d.append(contentsOf: be32(crc32(t)))
    }
    chunk("IHDR", be32(UInt32(w)) + be32(UInt32(h)) + [8, 3, 0, 0, 0])
    chunk("sRGB", [0])
    chunk("PLTE", palette.flatMap { [$0.r, $0.g, $0.b] })
    if hasAlpha {
      var alphas = palette.map(\.a)
      while alphas.last == 255 { alphas.removeLast() }
      if !alphas.isEmpty { chunk("tRNS", alphas) }
    }
    // One filter byte (0 = none) in front of every row, then zlib.
    var raw = [UInt8](); raw.reserveCapacity((w + 1) * h)
    for y in 0..<h { raw.append(0); raw.append(contentsOf: indices[(y * w)..<((y + 1) * w)]) }
    guard let z = zlib(raw) else { return nil }
    chunk("IDAT", z)
    chunk("IEND", [])
    return d
  }

  private static func zlib(_ raw: [UInt8]) -> [UInt8]? {
    let cap = raw.count + raw.count / 8 + 1024
    var dst = [UInt8](repeating: 0, count: cap)
    let n = compression_encode_buffer(&dst, cap, raw, raw.count, nil, COMPRESSION_ZLIB)  // raw deflate
    guard n > 0 else { return nil }
    var a: UInt32 = 1, b: UInt32 = 0
    for v in raw { a = (a + UInt32(v)) % 65521; b = (b + a) % 65521 }
    let adler = (b << 16) | a
    return [0x78, 0x9C] + dst[..<n] + [UInt8(adler >> 24), UInt8((adler >> 16) & 255), UInt8((adler >> 8) & 255), UInt8(adler & 255)]
  }

  private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
    var c = UInt32(i)
    for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
    return c
  }

  private static func crc32(_ bytes: [UInt8]) -> UInt32 {
    var c: UInt32 = 0xFFFF_FFFF
    for b in bytes { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
    return c ^ 0xFFFF_FFFF
  }
}
