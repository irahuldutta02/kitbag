import Foundation
import Testing

@testable import Authenticator

/// Files produced by independent reference code (Python's argon2-cffi, cryptography and hashlib).
private enum Fixture {
  static let protonPlain = #"""
{"version": 1, "entries": [{"id": "a1", "content": {"uri": "otpauth://totp/Alice?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&algorithm=SHA256&digits=8&period=15", "entry_type": "Totp", "name": "Alice"}, "note": null}, {"id": "a2", "content": {"uri": "steam://JBSWY3DPEHPK3PXP", "entry_type": "Steam", "name": "My Steam"}, "note": "n"}]}
"""#
  static let protonEncrypted = #"""
{"version": 1, "salt": "CC+hfjLkHEt2xhVDNQKb7w==", "content": "LUAKxepi5bzJ0m6OsNab7vlxRZ9brCTSQQCZHKoS2HbRb0dpgYgYgzVj+qyMHNz4uk5NSboWbo31cZIfeQQWfpetIhCpPwZVNeP3wkP1Pwcc16291x7fvjIWt4bgQvCblnPx/7P6wpZ97tCjLPlTB3kxwwyoZG3X4OKHQ/aKiasDY/pg/QQwb0WpRnBo5o9Farn4MBkaiyosay0QcOzVTk3wCrbzMJNwU68I30RO4JTzxca1KGk0RRSe6ZfmiiwmCCKohLjK8UoCjU5LgU05ZQHLoRzSsrT6SjOXc/rH+8F9qjhTZUqGa9+7ArD0zQFxKcKSNFtsRv8V3ypEcURaJ1H66Kpq5Y7AsTA1tqh1s/Y1bWRm5on2UParJKDUlzjp9q4wsfEJAsMqSnmsGMK1NlWMz1u3C6xn5/Nz0cCTLJkt09QP2tQH53E4dyMeMb9ZxqBPTIosh0HdaCPbm36mB9kI4ntroQ=="}
"""#  // password: hunter2
  static let twoFASPlain = #"""
{"schemaVersion": 4, "services": [{"name": "GitHub", "secret": "JBSWY3DPEHPK3PXP", "otp": {"issuer": "GitHub", "account": "alice", "digits": 6, "period": 30, "algorithm": "SHA1", "tokenType": "TOTP", "source": "Manual"}}, {"name": "Counter", "secret": "JBSWY3DPEHPK3PXP", "otp": {"tokenType": "HOTP", "source": "Manual", "counter": 1}}]}
"""#
  static let twoFASEncrypted = #"""
{"schemaVersion": 4, "servicesEncrypted": "W4qVfE0mM8PTNo3FtptiJZ9dC9TPQDXf6vmlXtiObpyqLNY+ZSZX6Qsab0FtMPKZXozr/XciR0dCt/2InyiGo6O23bwbtiMP5OwXRxVnQLndVNqE/xLSf59Bbc3YmRI/nSA4lhzvPI4ZHku/jN19ie+gPz1Cb9Af31Uu1ZuB/IXzNf99pHebLzecjexrOvVggHgAHcSFQEyMd82Tcq78Hw6vdq3xtd3lwl/3MFixlqnUKas7Ad/GIhOn5eYNa6zmmNFa6qrmkfaCmluzN7EQ+vQlQP3lkvEp5cn55n/1f1NTlH5yNvCD0XtbgAq5Ib528S2vuUhht7SxPSLv1U3bi/SupDeU2M9RiedAVAcYJNr1bxJcPpXzrzeSV7ShUnNFkiPsvaRxVKMgzmMqbwJCa7go/orkjcY5R0gWbNvtIw==:wU9O2ulA87LWJx1eAefUhEmjREddf6vi2JH232kDghk=:1/bNyGwQcA4XF790", "reference": []}
"""#  // password: test
}

private func bytes(_ hex: String) -> [UInt8] {
  stride(from: 0, to: hex.count, by: 2).map {
    UInt8(hex[hex.index(hex.startIndex, offsetBy: $0)..<hex.index(hex.startIndex, offsetBy: $0 + 2)], radix: 16)!
  }
}

@Suite struct ThirdPartyImportTests {
  @Test func blake2bMatchesReference() {
    #expect(Blake2b.hash(Array("abc".utf8), length: 64) == bytes("ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923"))
    #expect(Blake2b.hash([], length: 32) == bytes("0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8"))
    let long = (0..<256).map { UInt8($0) } + [UInt8](repeating: 0, count: 44)
    #expect(Blake2b.hash(long, length: 64) == bytes("aa3cd72a60ea2f16d489990f2a3567cd85cbe7b618d8fd605e12fcbc5130d037919680c7ede1e41d440455bd66cff2ce9a266a80c1331584f372ad08c08e1b81"))
  }

  @Test func argon2idMatchesReference() {
    #expect(Argon2id.hash(password: Array("pw".utf8), salt: Array("saltsaltsaltsalt".utf8), memoryKiB: 64, iterations: 3)
      == bytes("90a7dfe3c606d9439470a366ccdba2145ccd34bdb78730362a50b3a40398075f"))
    // The parameters Proton uses.
    #expect(Argon2id.hash(password: Array("correct horse".utf8), salt: Array("0123456789abcdef".utf8), memoryKiB: 19456, iterations: 2)
      == bytes("ae4d8c8b713876044c8347c76986a9b5655944aaacfffe9bea4dff9e7b6a1899"))
  }


  @Test func protonPlain() throws {
    let r = try ThirdPartyImport.Proton.parse(Data(Fixture.protonPlain.utf8), password: nil)
    #expect(r.entries.count == 2 && r.unusable == 0)
    #expect(r.entries[0].issuer == "GitHub" && r.entries[0].title == "Alice")
    #expect(r.entries[0].algorithm == .sha256 && r.entries[0].digits == 8 && r.entries[0].period == 15)
    #expect(r.entries[1].kind == .steam && r.entries[1].title == "My Steam" && r.entries[1].secret == "JBSWY3DPEHPK3PXP")
  }

  @Test func protonEncrypted() throws {
    let data = Data(Fixture.protonEncrypted.utf8)
    #expect(throws: ThirdPartyImport.Failure.needsPassword) { try ThirdPartyImport.Proton.parse(data, password: nil) }
    #expect(throws: ThirdPartyImport.Failure.wrongPassword) { try ThirdPartyImport.Proton.parse(data, password: "nope") }
    let r = try ThirdPartyImport.Proton.parse(data, password: "hunter2")
    #expect(r.entries.count == 2 && r.entries[0].issuer == "GitHub")
  }

  @Test func twoFAS() throws {
    let plain = try ThirdPartyImport.TwoFAS.parse(Data(Fixture.twoFASPlain.utf8), password: nil)
    #expect(plain.entries.count == 1 && plain.unusable == 1)  // the counter-based one is skipped
    #expect(plain.entries[0].issuer == "GitHub" && plain.entries[0].title == "alice")
    let data = Data(Fixture.twoFASEncrypted.utf8)
    #expect(throws: ThirdPartyImport.Failure.needsPassword) { try ThirdPartyImport.TwoFAS.parse(data, password: nil) }
    #expect(throws: ThirdPartyImport.Failure.wrongPassword) { try ThirdPartyImport.TwoFAS.parse(data, password: "x") }
    #expect(try ThirdPartyImport.TwoFAS.parse(data, password: "test").entries.count == 1)
  }

  @Test func otherFilesAreNotRecognized() {
    #expect(throws: ThirdPartyImport.Failure.notRecognized) { try ThirdPartyImport.Proton.parse(Data(Fixture.twoFASPlain.utf8), password: nil) }
    #expect(throws: ThirdPartyImport.Failure.notRecognized) { try ThirdPartyImport.TwoFAS.parse(Data("hello".utf8), password: nil) }
    #expect(throws: ThirdPartyImport.Failure.notRecognized) { try ThirdPartyImport.parse(Data("hello".utf8), as: .google, password: nil) }
  }

  @Test func qrCodeRoundTrips() throws {
    var e = AuthEntry()
    e.title = "alice@example.com"; e.issuer = "Example"; e.secret = "JBSWY3DPEHPK3PXP"
    let image = try #require(QRCode.image(for: e.uri))
    var rect = CGRect(origin: .zero, size: image.size)
    let cg = try #require(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
    let read = QRScanner.messages(in: cg)
    #expect(read == [e.uri])
    #expect(OTPImport.parse(read[0]).first?.secret == e.secret)
  }
}
