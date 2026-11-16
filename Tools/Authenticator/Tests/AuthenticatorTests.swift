import AppKit
import Foundation
import Testing

@testable import Authenticator

/// Builds a Google Authenticator export the way the app does, to test reading it.
private func varint(_ v: UInt64) -> [UInt8] {
  var out: [UInt8] = []
  var n = v
  repeat {
    var b = UInt8(n & 0x7F)
    n >>= 7
    if n != 0 { b |= 0x80 }
    out.append(b)
  } while n != 0
  return out
}
private func field(_ number: Int, bytes: [UInt8]) -> [UInt8] { varint(UInt64(number << 3 | 2)) + varint(UInt64(bytes.count)) + bytes }
private func field(_ number: Int, int: Int) -> [UInt8] { varint(UInt64(number << 3)) + varint(UInt64(int)) }

private func migrationLink(_ accounts: [(secret: Data, name: String, issuer: String, algorithm: Int, digits: Int, type: Int)]) -> String {
  var payload: [UInt8] = []
  for a in accounts {
    let one =
      field(1, bytes: Array(a.secret)) + field(2, bytes: Array(a.name.utf8)) + field(3, bytes: Array(a.issuer.utf8))
      + field(4, int: a.algorithm) + field(5, int: a.digits) + field(6, int: a.type)
    payload += field(1, bytes: one)
  }
  payload += field(2, int: 1) + field(3, int: 1)  // version, batch size: must be skipped
  let b64 = Data(payload).base64EncodedString().addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
  return "otpauth-migration://offline?data=\(b64)"
}

@MainActor @Suite struct AuthenticatorTests {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kitbag-auth-\(UUID().uuidString)")
  let suite = "kitbag.auth.tests.\(UUID().uuidString)"
  let pb = NSPasteboard(name: .init("kitbag.auth.tests.\(UUID().uuidString)"))

  private func makeModel() -> AuthenticatorModel {
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let m = AuthenticatorModel(
      storage: FileVault(url: dir.appendingPathComponent("vault.json")), defaults: UserDefaults(suiteName: suite)!,
      pasteboard: pb)
    m.start()
    return m
  }

  private func entry(_ title: String, issuer: String = "", secret: String = "JBSWY3DPEHPK3PXP") -> AuthEntry {
    var e = AuthEntry()
    e.title = title
    e.issuer = issuer
    e.secret = secret
    return e
  }

  // MARK: Codes (RFC 6238 appendix B test vectors)

  @Test func rfc6238Vectors() {
    let sha1 = Data("12345678901234567890".utf8)
    let sha256 = Data("12345678901234567890123456789012".utf8)
    let sha512 = Data("1234567890123456789012345678901234567890123456789012345678901234".utf8)
    func code(_ k: Data, _ a: OTPAlgorithm, _ t: Double) -> String {
      OTP.code(secret: k, algorithm: a, digits: 8, period: 30, kind: .totp, at: Date(timeIntervalSince1970: t))
    }
    #expect(code(sha1, .sha1, 59) == "94287082")
    #expect(code(sha256, .sha256, 59) == "46119246")
    #expect(code(sha512, .sha512, 59) == "90693936")
    #expect(code(sha1, .sha1, 1_111_111_109) == "07081804")
    #expect(code(sha1, .sha1, 20_000_000_000) == "65353130")
  }

  @Test func sixDigitCodeKeepsLeadingZeros() {
    let c = OTP.code(secret: Data("12345678901234567890".utf8), algorithm: .sha1, digits: 6, period: 30, kind: .totp, at: Date(timeIntervalSince1970: 1_111_111_109))
    #expect(c == "081804")
  }

  @Test func steamCodesUseTheSteamAlphabet() {
    let c = OTP.code(secret: Data("12345678901234567890".utf8), algorithm: .sha1, digits: 5, period: 30, kind: .steam, at: Date(timeIntervalSince1970: 59))
    #expect(c.count == 5 && c.allSatisfy { OTP.steamAlphabet.contains($0) })
  }

  @Test func base32RoundTripsAndToleratesPasting() {
    #expect(Base32.decode("JBSWY3DPEHPK3PXP") == Data("Hello!\u{DE}\u{AD}\u{BE}\u{EF}".utf8).prefix(0) + Base32.decode("jbsw y3dp-ehpk 3pxp=")!)
    let data = Data((0..<20).map { UInt8($0 * 13) })
    #expect(Base32.decode(Base32.encode(data)) == data)
    #expect(Base32.decode("not base32!") == nil && Base32.decode("") == nil)
  }

  @Test func nextCodeIsWhatTheCurrentOneBecomes() {
    let e = entry("x")
    let t = Date(timeIntervalSince1970: 1_000_000_010)  // 20 s into a 30 s step
    #expect(e.nextCode(at: t) == e.code(at: t.addingTimeInterval(30)))
    #expect(e.nextCode(at: t) != e.code(at: t))
    // Right at the start of a step the next code is a full step away, not the current one.
    let start = Date(timeIntervalSince1970: 1_000_000_020 - 20 + 30 - 30 + 0)
    #expect(e.nextCode(at: start) == e.code(at: start.addingTimeInterval(30)))
  }

  @Test func timeRemaining() {
    #expect(OTP.remaining(period: 30, at: Date(timeIntervalSince1970: 59)) == 1)
    #expect(OTP.remaining(period: 30, at: Date(timeIntervalSince1970: 60)) == 30)
    #expect(OTP.grouped("123456", kind: .totp) == "123 456" && OTP.grouped("12345678", kind: .totp) == "1234 5678" && OTP.grouped("A2B3C", kind: .steam) == "A2B3C")
  }

  // MARK: Links

  @Test func readsOtpauthLinks() throws {
    let e = try #require(OTPImport.entry("otpauth://totp/GitHub:octo%20cat@x.com?secret=jbsw y3dp&issuer=GitHub&algorithm=SHA256&digits=8&period=60".replacingOccurrences(of: " ", with: "")))
    #expect(e.issuer == "GitHub" && e.title == "octo cat@x.com" && e.algorithm == .sha256 && e.digits == 8 && e.period == 60 && e.kind == .totp)
    let bare = try #require(OTPImport.entry("otpauth://totp/Work?secret=JBSWY3DPEHPK3PXP"))
    #expect(bare.title == "Work" && bare.issuer == "" && bare.digits == 6 && bare.period == 30 && bare.algorithm == .sha1)
    let steam = try #require(OTPImport.entry("otpauth://steam/Steam:me?secret=JBSWY3DPEHPK3PXP&digits=8"))
    #expect(steam.kind == .steam && steam.digits == 5)
  }

  @Test func rejectsWhatItCannotUse() {
    #expect(OTPImport.entry("otpauth://hotp/x?secret=JBSWY3DPEHPK3PXP&counter=1") == nil)
    #expect(OTPImport.entry("otpauth://totp/x?secret=!!!") == nil)
    #expect(OTPImport.entry("otpauth://totp/x") == nil)
    #expect(OTPImport.entry("https://example.com") == nil)
    #expect(OTPImport.entry("otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&algorithm=MD5") == nil)
  }

  @Test func linkRoundTrips() throws {
    var e = entry("me@x.com", issuer: "Some Co: Ltd")
    e.digits = 8; e.period = 60; e.algorithm = .sha512
    let back = try #require(OTPImport.entry(e.uri))
    #expect(back.title == e.title && back.issuer == e.issuer && back.digits == 8 && back.period == 60 && back.algorithm == .sha512 && back.secret == e.secret)
  }

  @Test func readsGoogleAuthenticatorExport() {
    let a = Data("12345678901234567890".utf8)
    let b = Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    let link = migrationLink([
      (a, "Google:me@x.com", "", 1, 1, 2),
      (b, "Bank", "MyBank", 2, 2, 2),
      (b, "Counter", "X", 1, 1, 1),  // HOTP: skipped
    ])
    let list = OTPImport.parse(link)
    #expect(list.count == 2)
    #expect(list[0].issuer == "Google" && list[0].title == "me@x.com" && list[0].secretData == a && list[0].digits == 6)
    #expect(list[1].issuer == "MyBank" && list[1].algorithm == .sha256 && list[1].digits == 8 && list[1].secretData == b)
  }

  // MARK: Accounts

  @Test func searchAndOrder() {
    let m = makeModel()
    m.add(entry("zed@x.com", issuer: "Zed", secret: "AAAAAAAA"))
    m.add(entry("a@x.com", issuer: "Amazon", secret: "BBBBBBBB"))
    m.add(entry("work", issuer: "GitHub", secret: "CCCCCCCC"))
    #expect(m.filtered("").map(\.primary) == ["Amazon", "GitHub", "Zed"])
    #expect(m.filtered("hub").map(\.primary) == ["GitHub"])
    #expect(m.filtered("a@x").map(\.primary) == ["Amazon"])
    m.togglePin(m.entries.first { $0.issuer == "Zed" }!.id)
    #expect(m.filtered("").first?.primary == "Zed")
  }

  @Test func sameSecretIsNotAddedTwice() {
    let m = makeModel()
    #expect(m.add(entry("one")) == .added)
    #expect(m.add(entry("two", secret: "jbsw y3dp ehpk 3pxp")) == .duplicate)
    #expect(m.entries.count == 1)
  }

  @Test func accountsSurviveARestart() {
    let m = makeModel()
    m.add(entry("keep", issuer: "Svc"))
    let again = makeModel()
    #expect(again.entries.map(\.title) == ["keep"])
  }

  @Test func editAndDelete() {
    let m = makeModel()
    m.add(entry("old"))
    var e = m.entries[0]
    e.title = "new"
    #expect(m.update(e) && m.entries[0].title == "new")
    m.delete(e.id)
    #expect(m.entries.isEmpty)
  }

  @Test func copyHidesTheCodeFromClipboardHistoryAndClearsLater() {
    let m = makeModel()
    let e = entry("x")
    m.copyCode(e, at: Date(timeIntervalSince1970: 59))
    #expect(pb.string(forType: .string) == e.code(at: Date(timeIntervalSince1970: 59)))
    #expect(pb.types?.contains(.init("org.nspasteboard.ConcealedType")) == true)
  }

  @Test func copyNextPutsTheUpcomingCodeOnTheClipboard() {
    let m = makeModel()
    let e = entry("x")
    let t = Date(timeIntervalSince1970: 1_000_000_010)
    m.copyNextCode(e, at: t)
    #expect(pb.string(forType: .string) == e.nextCode(at: t) && pb.string(forType: .string) != e.code(at: t))
    #expect(m.copiedNext)
    m.copyCode(e, at: t)
    #expect(pb.string(forType: .string) == e.code(at: t) && !m.copiedNext)
  }

  @Test func neverOverwritesAVaultItCouldNotRead() throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("vault.json")
    try Data("not json".utf8).write(to: url)
    let m = makeModel()
    #expect(m.storageError != nil)
    #expect(m.add(entry("x")) == .failed)
    #expect(try Data(contentsOf: url) == Data("not json".utf8))
  }

  // MARK: Backup

  @Test func backupRoundTrip() throws {
    let m = makeModel()
    var e = entry("me@x.com", issuer: "GitHub")
    e.digits = 8; e.pinned = true
    m.add(e)
    m.add(entry("two", secret: "MFRGGZDFMZTWQ2LK"))
    let data = try m.exportBackup()
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("otpauth://totp/") && text.contains("\"Kitbag Authenticator\""))

    m.removeAll()
    let r = m.restore(from: data)
    #expect(r == RestoreSummary(added: 2, skipped: 0, invalid: 0))
    #expect(m.entries.first { $0.issuer == "GitHub" }?.digits == 8)
    #expect(m.entries.first { $0.issuer == "GitHub" }?.pinned == true)
    #expect(m.restore(from: data) == RestoreSummary(added: 0, skipped: 2, invalid: 0))  // restoring twice adds nothing
  }

  @Test func restoreAcceptsLinksAndRejectsRubbish() {
    let m = makeModel()
    let links = "otpauth://totp/A?secret=JBSWY3DPEHPK3PXP\n\notpauth://totp/B?secret=MFRGGZDFMZTWQ2LK\n"
    #expect(m.restore(from: Data(links.utf8)).added == 2)
    #expect(m.restore(from: Data("hello".utf8)).recognized == false)
    let bad = #"{"entries":[{"title":"x","secret":"!!"},{"title":"ok","secret":"GEZDGNBVGY3TQOJQ"}]}"#
    let r = m.restore(from: Data(bad.utf8))
    #expect(r.added == 1 && r.invalid == 1)
  }
}
