import Foundation
import Crypto
import _CryptoExtras
import Citadel
import NIOCore
import NIOSSH

// RFC 8332: RSA key blobs retain ssh-rsa encoding, but signatures use SHA-2 only.
struct RSAHostKey: NIOSSHPublicKeyProtocol {
  static let publicKeyPrefix = "ssh-rsa"
  static let hostKeyAlgorithms = ["rsa-sha2-512", "rsa-sha2-256"]
  let modulus: Data
  let exponent: Data
  private let key: _RSA.Signing.PublicKey

  init(modulus: Data, exponent: Data) throws {
    let key = try _RSA.Signing.PublicKey(n: modulus, e: exponent)
    guard key.keySizeInBits >= 2048 else { throw RSAWireError.invalidKey }
    self.key = key
    self.modulus = modulus
    self.exponent = exponent
  }
  var rawRepresentation: Data {
    var buffer = ByteBuffer()
    _ = write(to: &buffer)
    return Data(buffer.readableBytesView)
  }
  func isValidSignature<D: DataProtocol>(_ signature: NIOSSHSignatureProtocol, for data: D) -> Bool {
    if let signature = signature as? RSASHA256Signature {
      return key.isValidSignature(.init(rawRepresentation: signature.bytes),
        for: SHA256.hash(data: data), padding: .insecurePKCS1v1_5)
    }
    if let signature = signature as? RSASHA512Signature {
      return key.isValidSignature(.init(rawRepresentation: signature.bytes),
        for: SHA512.hash(data: data), padding: .insecurePKCS1v1_5)
    }
    return false
  }
  func write(to buffer: inout ByteBuffer) -> Int {
    writeMPInt(exponent, to: &buffer) + writeMPInt(modulus, to: &buffer)
  }
  static func read(from buffer: inout ByteBuffer) throws -> Self {
    let e = try readMPInt(from: &buffer)
    let n = try readMPInt(from: &buffer)
    return try Self(modulus: n, exponent: e)
  }
}

enum RSAWireError: Error { case invalidKey, invalidString }
private func readString(from buffer: inout ByteBuffer) throws -> Data {
  guard let size: UInt32 = buffer.readInteger(), size <= 16_384,
        let bytes = buffer.readBytes(length: Int(size)) else { throw RSAWireError.invalidString }
  return Data(bytes)
}
private func readMPInt(from buffer: inout ByteBuffer) throws -> Data {
  var value = try readString(from: &buffer)
  guard let first = value.first, first < 128 else { throw RSAWireError.invalidKey }
  if first == 0 {
    guard value.count > 1, value[value.startIndex + 1] >= 128 else { throw RSAWireError.invalidKey }
    value.removeFirst()
  }
  return Data(value)
}
private func writeMPInt(_ value: Data, to buffer: inout ByteBuffer) -> Int {
  let bytes = value.first.map { $0 >= 128 } == true ? Data([0]) + value : value
  return buffer.writeInteger(UInt32(bytes.count)) + buffer.writeBytes(bytes)
}
struct RSASHA256Signature: NIOSSHSignatureProtocol {
  static let signaturePrefix = "rsa-sha2-256"
  let bytes: Data
  var rawRepresentation: Data { bytes }
  func write(to buffer: inout ByteBuffer) -> Int {
    buffer.writeInteger(UInt32(bytes.count)) + buffer.writeBytes(bytes)
  }
  static func read(from buffer: inout ByteBuffer) throws -> Self {
    Self(bytes: try readString(from: &buffer))
  }
}
struct RSASHA512Signature: NIOSSHSignatureProtocol {
  static let signaturePrefix = "rsa-sha2-512"
  let bytes: Data
  var rawRepresentation: Data { bytes }
  func write(to buffer: inout ByteBuffer) -> Int {
    buffer.writeInteger(UInt32(bytes.count)) + buffer.writeBytes(bytes)
  }
  static func read(from buffer: inout ByteBuffer) throws -> Self {
    Self(bytes: try readString(from: &buffer))
  }
}
enum SSHCompatibility {
  static let algorithms: SSHAlgorithms = {
    var value = SSHAlgorithms()
    value.publicKeyAlgorihtms = .add([
      (RSAHostKey.self, RSASHA256Signature.self),
      (RSAHostKey.self, RSASHA512Signature.self),
    ])
    return value
  }()
}
