import CommonCrypto
import Crypto
import Foundation

struct TermEntry: Codable, Equatable {
  var server: Server
  var credentials: Credentials?
}
struct TermPayload: Codable {
  var schemaVersion = 1
  var entries: [TermEntry]
}
enum TermArchive {
  static let maximum = 16 * 1024 * 1024
  static let magic = Data([77, 84, 69, 82, 77, 0, 13, 10])
  static func passwordBytes(_ password: String) throws -> [UInt8] {
    let p = password.precomposedStringWithCanonicalMapping
    guard p.unicodeScalars.count >= 12, p.utf8.count <= 1024 else {
      throw AppError.message(
        "Use a file password of at least 12 characters (maximum 1024 UTF-8 bytes).")
    }
    return Array(p.utf8)
  }
  static func key(_ password: String, salt: Data) throws -> SymmetricKey {
    var p = try passwordBytes(password)
    var bytes = [UInt8](repeating: 0, count: 32)
    defer {
      _ = p.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
      _ = bytes.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
    }
    let status = p.withUnsafeBytes { pp in
      salt.withUnsafeBytes { sp in
        CCKeyDerivationPBKDF(
          CCPBKDFAlgorithm(kCCPBKDF2), pp.baseAddress!.assumingMemoryBound(to: Int8.self), p.count,
          sp.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
          CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 600000, &bytes, 32)
      }
    }
    guard status == kCCSuccess else {
      throw AppError.message("Could not derive file encryption key.")
    }
    return SymmetricKey(data: bytes)
  }
  static func validate(_ entries: [TermEntry]) throws {
    guard !entries.isEmpty, entries.count <= 200,
      entries.allSatisfy({
        $0.server.valid && !$0.server.user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && !$0.server.host.contains(where: { $0.isWhitespace }) && !$0.server.host.contains("://")
          && ($0.credentials?.privateKey.utf8.count ?? 0) <= 1024 * 1024
      })
    else { throw AppError.message("Invalid connections or archive limits exceeded.") }
  }
  static func encode(_ entries: [TermEntry], password: String) throws -> Data {
    try validate(entries)
    let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
    let nonce = AES.GCM.Nonce()
    let plain = try JSONEncoder().encode(TermPayload(entries: entries))
    guard plain.count <= maximum - 64 else { throw AppError.message("Archive exceeds 16 MiB.") }
    var header = magic + Data([0, 1, 1, 1, 0, 9, 39, 192]) + salt + Data(nonce)
    let n = UInt32(plain.count)
    header.append(contentsOf: [
      UInt8(n >> 24), UInt8(truncatingIfNeeded: n >> 16), UInt8(truncatingIfNeeded: n >> 8),
      UInt8(truncatingIfNeeded: n),
    ])
    let sealed = try AES.GCM.seal(
      plain, using: key(password, salt: salt), nonce: nonce, authenticating: header)
    return header + sealed.ciphertext + sealed.tag
  }
  static func decode(_ data: Data, password: String) throws -> [TermEntry] {
    guard data.count >= 64, data.count <= maximum,
      data.prefix(16) == magic + Data([0, 1, 1, 1, 0, 9, 39, 192])
    else {
      throw AppError.message("Invalid, oversized or unsupported .term file.")
    }
    let n = data[44..<48].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    guard Int(n) == data.count - 64 else { throw AppError.message("Invalid .term file length.") }
    let key = try key(password, salt: data.subdata(in: 16..<32))
    let plain: Data
    do {
      let box = try AES.GCM.SealedBox(
        nonce: AES.GCM.Nonce(data: data[32..<44]), ciphertext: data[48..<(data.count - 16)],
        tag: data.suffix(16))
      plain = try AES.GCM.open(box, using: key, authenticating: data.prefix(48))
    } catch { throw AppError.message("Wrong password or damaged file.") }
    let payload: TermPayload
    do { payload = try JSONDecoder().decode(TermPayload.self, from: plain) } catch {
      throw AppError.message("Invalid connection data.")
    }
    guard payload.schemaVersion == 1 else { throw AppError.message("Unsupported payload version.") }
    try validate(payload.entries)
    return payload.entries
  }
  static func grouped(_ entries: [TermEntry]) -> [[TermEntry]] {
    var groups: [[TermEntry]] = []
    for entry in entries {
      if let i = groups.firstIndex(where: { $0[0].server.id == entry.server.id }) {
        if !groups[i].contains(entry) { groups[i].append(entry) }
      } else {
        groups.append([entry])
      }
    }
    return groups
  }
}
