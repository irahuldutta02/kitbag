import Foundation

/// BLAKE2b (RFC 7693), unkeyed. Needed by Argon2, which CryptoKit doesn't offer.
enum Blake2b {
  private static let iv: [UInt64] = [
    0x6a09_e667_f3bc_c908, 0xbb67_ae85_84ca_a73b, 0x3c6e_f372_fe94_f82b, 0xa54f_f53a_5f1d_36f1,
    0x510e_527f_ade6_82d1, 0x9b05_688c_2b3e_6c1f, 0x1f83_d9ab_fb41_bd6b, 0x5be0_cd19_137e_2179,
  ]
  private static let sigma: [[Int]] = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
    [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
    [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
    [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
    [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
    [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
    [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
    [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
    [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
  ]

  @inline(__always) private static func rotr(_ x: UInt64, _ n: UInt64) -> UInt64 { (x >> n) | (x << (64 - n)) }

  static func hash(_ message: [UInt8], length outLen: Int) -> [UInt8] {
    precondition((1...64).contains(outLen))
    var h = iv
    h[0] ^= 0x0101_0000 ^ UInt64(outLen)
    var t: UInt64 = 0
    var offset = 0
    // The last block is always compressed with the final flag, even when the message is empty.
    repeat {
      let remaining = message.count - offset
      let isLast = remaining <= 128
      var block = [UInt8](repeating: 0, count: 128)
      let n = min(128, remaining)
      if n > 0 { block.replaceSubrange(0..<n, with: message[offset..<offset + n]) }
      t += UInt64(n)
      compress(&h, block, t, isLast)
      offset += n
      if isLast { break }
    } while true
    var out = [UInt8]()
    out.reserveCapacity(64)
    for word in h { for i in 0..<8 { out.append(UInt8((word >> (8 * UInt64(i))) & 0xFF)) } }
    return Array(out.prefix(outLen))
  }

  private static func compress(_ h: inout [UInt64], _ block: [UInt8], _ t: UInt64, _ last: Bool) {
    var m = [UInt64](repeating: 0, count: 16)
    for i in 0..<16 {
      var w: UInt64 = 0
      for j in 0..<8 { w |= UInt64(block[i * 8 + j]) << (8 * UInt64(j)) }
      m[i] = w
    }
    var v = h + iv
    v[12] ^= t
    if last { v[14] = ~v[14] }
    func g(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ x: UInt64, _ y: UInt64) {
      v[a] = v[a] &+ v[b] &+ x
      v[d] = rotr(v[d] ^ v[a], 32)
      v[c] = v[c] &+ v[d]
      v[b] = rotr(v[b] ^ v[c], 24)
      v[a] = v[a] &+ v[b] &+ y
      v[d] = rotr(v[d] ^ v[a], 16)
      v[c] = v[c] &+ v[d]
      v[b] = rotr(v[b] ^ v[c], 63)
    }
    for round in 0..<12 {
      let s = sigma[round % 10]
      g(0, 4, 8, 12, m[s[0]], m[s[1]])
      g(1, 5, 9, 13, m[s[2]], m[s[3]])
      g(2, 6, 10, 14, m[s[4]], m[s[5]])
      g(3, 7, 11, 15, m[s[6]], m[s[7]])
      g(0, 5, 10, 15, m[s[8]], m[s[9]])
      g(1, 6, 11, 12, m[s[10]], m[s[11]])
      g(2, 7, 8, 13, m[s[12]], m[s[13]])
      g(3, 4, 9, 14, m[s[14]], m[s[15]])
    }
    for i in 0..<8 { h[i] ^= v[i] ^ v[i + 8] }
  }
}

/// Argon2id (RFC 9106), version 1.3, with a single lane (parallelism 1), which is what
/// Proton Authenticator's password-protected export uses.
enum Argon2id {
  static func hash(
    password: [UInt8], salt: [UInt8], memoryKiB: Int, iterations: Int, length: Int = 32
  ) -> [UInt8]? {
    guard memoryKiB >= 8, iterations >= 1, (4...64).contains(length) else { return nil }
    let lanes = 1
    let blockCount = 4 * lanes * (memoryKiB / (4 * lanes))
    let segmentLength = blockCount / 4

    func le32(_ v: Int) -> [UInt8] { (0..<4).map { UInt8((UInt32(truncatingIfNeeded: v) >> (8 * UInt32($0))) & 0xFF) } }

    var h0Input = [UInt8]()
    h0Input += le32(lanes) + le32(length) + le32(memoryKiB) + le32(iterations) + le32(0x13) + le32(2)
    h0Input += le32(password.count) + password + le32(salt.count) + salt + le32(0) + le32(0)
    let h0 = Blake2b.hash(h0Input, length: 64)

    // Memory: `blockCount` blocks of 128 words.
    var memory = [UInt64](repeating: 0, count: blockCount * 128)
    func store(_ bytes: [UInt8], at block: Int) {
      for i in 0..<128 {
        var w: UInt64 = 0
        for j in 0..<8 { w |= UInt64(bytes[i * 8 + j]) << (8 * UInt64(j)) }
        memory[block * 128 + i] = w
      }
    }
    store(variableHash(h0 + le32(0) + le32(0), 1024), at: 0)
    store(variableHash(h0 + le32(1) + le32(0), 1024), at: 1)

    memory.withUnsafeMutableBufferPointer { mem in
      var zero = [UInt64](repeating: 0, count: 128)
      var addressBlock = [UInt64](repeating: 0, count: 128)
      var inputBlock = [UInt64](repeating: 0, count: 128)
      for pass in 0..<iterations {
        for slice in 0..<4 {
          let independent = pass == 0 && slice < 2
          var counter: UInt64 = 0
          func nextAddresses() {
            counter += 1
            inputBlock[6] = counter
            var tmp = [UInt64](repeating: 0, count: 128)
            compressBlock(&tmp, zero, inputBlock, xorInto: false)
            compressBlock(&addressBlock, zero, tmp, xorInto: false)
          }
          if independent {
            inputBlock = [UInt64](repeating: 0, count: 128)
            inputBlock[0] = UInt64(pass)
            inputBlock[1] = 0
            inputBlock[2] = UInt64(slice)
            inputBlock[3] = UInt64(blockCount)
            inputBlock[4] = UInt64(iterations)
            inputBlock[5] = 2
          }
          var start = 0
          if pass == 0 && slice == 0 {
            start = 2
            if independent { nextAddresses() }
          }
          var current = slice * segmentLength + start
          for index in start..<segmentLength {
            let previous = current % blockCount == 0 ? blockCount - 1 : current - 1
            let random: UInt64
            if independent {
              if index % 128 == 0 { nextAddresses() }
              random = addressBlock[index % 128]
            } else {
              random = mem[previous * 128]
            }
            let j1 = random & 0xFFFF_FFFF
            let areaSize: Int =
              pass == 0
              ? slice * segmentLength + index - 1
              : blockCount - segmentLength + index - 1
            var relative = (j1 &* j1) >> 32
            relative = UInt64(areaSize) &- 1 &- ((UInt64(areaSize) &* relative) >> 32)
            let startPosition = pass == 0 ? 0 : (slice == 3 ? 0 : (slice + 1) * segmentLength)
            let reference = (startPosition + Int(relative)) % blockCount

            let x = Array(mem[previous * 128..<previous * 128 + 128])
            let y = Array(mem[reference * 128..<reference * 128 + 128])
            var out = [UInt64](repeating: 0, count: 128)
            if pass > 0 {
              // Version 1.3 overwrites by XOR-ing into what was there.
              for i in 0..<128 { out[i] = mem[current * 128 + i] }
              compressBlock(&out, x, y, xorInto: true)
            } else {
              compressBlock(&out, x, y, xorInto: false)
            }
            for i in 0..<128 { mem[current * 128 + i] = out[i] }
            current += 1
          }
        }
      }
      zero = []
    }

    var last = [UInt8]()
    last.reserveCapacity(1024)
    for i in 0..<128 {
      let w = memory[(blockCount - 1) * 128 + i]
      for j in 0..<8 { last.append(UInt8((w >> (8 * UInt64(j))) & 0xFF)) }
    }
    return variableHash(last, length)
  }

  /// H' from the spec: BLAKE2b with an output of any length.
  private static func variableHash(_ input: [UInt8], _ length: Int) -> [UInt8] {
    let prefix = (0..<4).map { UInt8((UInt32(length) >> (8 * UInt32($0))) & 0xFF) }
    if length <= 64 { return Blake2b.hash(prefix + input, length: length) }
    let r = (length + 31) / 32 - 2
    var v = Blake2b.hash(prefix + input, length: 64)
    var out = Array(v.prefix(32))
    for _ in 1..<r {
      v = Blake2b.hash(v, length: 64)
      out += v.prefix(32)
    }
    out += Blake2b.hash(v, length: length - 32 * r)
    return out
  }

  /// G(X, Y): the compression function over 1 KiB blocks. With `xorInto`, the result is XOR-ed
  /// into `out` instead of replacing it.
  private static func compressBlock(_ out: inout [UInt64], _ x: [UInt64], _ y: [UInt64], xorInto: Bool) {
    var r = [UInt64](repeating: 0, count: 128)
    for i in 0..<128 { r[i] = x[i] ^ y[i] }
    var z = r
    z.withUnsafeMutableBufferPointer { p in
      for row in 0..<8 {
        let b = row * 16
        permute(p, [b, b + 1, b + 2, b + 3, b + 4, b + 5, b + 6, b + 7, b + 8, b + 9, b + 10, b + 11, b + 12, b + 13, b + 14, b + 15])
      }
      for col in 0..<8 {
        let b = col * 2
        permute(p, [b, b + 1, b + 16, b + 17, b + 32, b + 33, b + 48, b + 49, b + 64, b + 65, b + 80, b + 81, b + 96, b + 97, b + 112, b + 113])
      }
    }
    if xorInto {
      for i in 0..<128 { out[i] ^= z[i] ^ r[i] }
    } else {
      for i in 0..<128 { out[i] = z[i] ^ r[i] }
    }
  }

  @inline(__always) private static func rotr(_ x: UInt64, _ n: UInt64) -> UInt64 { (x >> n) | (x << (64 - n)) }
  @inline(__always) private static func mix(_ a: UInt64, _ b: UInt64) -> UInt64 {
    a &+ b &+ 2 &* (a & 0xFFFF_FFFF) &* (b & 0xFFFF_FFFF)
  }

  private static func permute(_ v: UnsafeMutableBufferPointer<UInt64>, _ i: [Int]) {
    func gb(_ a: Int, _ b: Int, _ c: Int, _ d: Int) {
      v[i[a]] = mix(v[i[a]], v[i[b]])
      v[i[d]] = rotr(v[i[d]] ^ v[i[a]], 32)
      v[i[c]] = mix(v[i[c]], v[i[d]])
      v[i[b]] = rotr(v[i[b]] ^ v[i[c]], 24)
      v[i[a]] = mix(v[i[a]], v[i[b]])
      v[i[d]] = rotr(v[i[d]] ^ v[i[a]], 16)
      v[i[c]] = mix(v[i[c]], v[i[d]])
      v[i[b]] = rotr(v[i[b]] ^ v[i[c]], 63)
    }
    gb(0, 4, 8, 12)
    gb(1, 5, 9, 13)
    gb(2, 6, 10, 14)
    gb(3, 7, 11, 15)
    gb(0, 5, 10, 15)
    gb(1, 6, 11, 12)
    gb(2, 7, 8, 13)
    gb(3, 4, 9, 14)
  }
}
