import XCTest
import Crypto
import _CryptoExtras
import NIOCore
@testable import NIOSSH
@testable import ModerntermIOS

final class RSAHostKeyTests: XCTestCase {
  func testSHA2SignaturesAndTampering() throws {
    let privateKey = try _RSA.Signing.PrivateKey(keySize: .bits2048)
    let parts = try privateKey.publicKey.getKeyPrimitives()
    let key = try RSAHostKey(modulus: parts.modulus, exponent: parts.publicExponent)
    let message = Data("SSH exchange hash test".utf8)
    let s256 = try privateKey.signature(for: SHA256.hash(data: message), padding: .insecurePKCS1v1_5)
    let s512 = try privateKey.signature(for: SHA512.hash(data: message), padding: .insecurePKCS1v1_5)
    XCTAssertTrue(key.isValidSignature(RSASHA256Signature(bytes: s256.rawRepresentation), for: message))
    XCTAssertTrue(key.isValidSignature(RSASHA512Signature(bytes: s512.rawRepresentation), for: message))
    XCTAssertFalse(key.isValidSignature(RSASHA256Signature(bytes: s512.rawRepresentation), for: message))
    XCTAssertFalse(key.isValidSignature(RSASHA256Signature(bytes: s256.rawRepresentation), for: Data("tampered".utf8)))
    XCTAssertEqual(RSAHostKey.hostKeyAlgorithms, ["rsa-sha2-512", "rsa-sha2-256"])
    XCTAssertFalse(RSAHostKey.hostKeyAlgorithms.contains("ssh-rsa"))
    let host = NIOSSHPublicKey(backingKey: .custom(key))
    let signature = NIOSSHSignature(backingSignature: .custom(RSASHA256Signature(bytes: s256.rawRepresentation)))
    XCTAssertTrue(host.matchesHostKeyAlgorithm("rsa-sha2-256", signature: signature))
    XCTAssertFalse(host.matchesHostKeyAlgorithm("rsa-sha2-512", signature: signature))
    XCTAssertFalse(host.matchesHostKeyAlgorithm("ssh-rsa", signature: signature))
    var buffer = ByteBuffer()
    _ = key.write(to: &buffer)
    let decoded = try RSAHostKey.read(from: &buffer)
    XCTAssertEqual(decoded.rawRepresentation, key.rawRepresentation)
    XCTAssertTrue(decoded.isValidSignature(RSASHA512Signature(bytes: s512.rawRepresentation), for: message))
  }
  func testMalformedKeyAndSignatureRejected() throws {
    var buffer = ByteBuffer(bytes: [0, 0, 0, 20, 1])
    XCTAssertThrowsError(try RSAHostKey.read(from: &buffer))
    XCTAssertThrowsError(try RSASHA256Signature.read(from: &buffer))
  }
  func testGatewayUsernameRoundtrip() throws {
    var server = Server()
    server.host = "ssh.region-1.example.com"
    server.user = "test-account@ZONE-M6"
    let copy = try JSONDecoder().decode(Server.self, from: JSONEncoder().encode(server))
    XCTAssertTrue(copy.valid)
    XCTAssertEqual(copy.user, "test-account@ZONE-M6")
  }
}
