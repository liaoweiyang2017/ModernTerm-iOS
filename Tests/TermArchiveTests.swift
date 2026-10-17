import XCTest

@testable import ModerntermIOS

final class TermArchiveTests: XCTestCase {
  let password = "互通测试-café-🔐-2026"
  func fixture() throws -> Data {
    try Data(
      contentsOf: XCTUnwrap(
        Bundle(for: Self.self).url(forResource: "reference", withExtension: "term")))
  }
  func testReferenceUnicodeAndRandomRoundTrip() throws {
    let entries = try TermArchive.decode(fixture(), password: password)
    XCTAssertEqual(entries.count, 2)
    XCTAssertEqual(entries[0].server.user, "test@ZC-M6")
    XCTAssertEqual(entries[0].server.distribution, "Debian")
    XCTAssertEqual(entries[0].credentials?.privateKey, "TEST KEY\nnot-a-real-key\n")
    XCTAssertNil(entries[1].credentials)
    let a = try TermArchive.encode(entries, password: password)
    let b = try TermArchive.encode(entries, password: password)
    XCTAssertNotEqual(a, b)
    XCTAssertNil(a.range(of: Data("ssh.example.invalid".utf8)))
    XCTAssertEqual(
      try TermArchive.decode(a, password: password.decomposedStringWithCanonicalMapping), entries)
    try a.write(to: URL.documentsDirectory.appendingPathComponent("ios-export.term"))
  }
  func testRejectsWrongPasswordTamperingLengthsAndVersion() throws {
    let data = try fixture()
    XCTAssertThrowsError(try TermArchive.decode(data, password: "wrong-password-123"))
    for index in [8, 15, 16, 32, 44, 48, data.count - 1] {
      var changed = data
      changed[index] ^= 1
      XCTAssertThrowsError(try TermArchive.decode(changed, password: password))
    }
    XCTAssertThrowsError(try TermArchive.decode(data.dropLast(), password: password))
    XCTAssertThrowsError(try TermArchive.decode(data + Data([0]), password: password))
    XCTAssertThrowsError(
      try TermArchive.decode(Data(repeating: 0, count: TermArchive.maximum + 1), password: password)
    )
    XCTAssertThrowsError(
      try TermArchive.encode(TermArchive.decode(data, password: password), password: "short"))
  }
  func testDuplicateAndConflictGrouping() throws {
    let entries = try TermArchive.decode(fixture(), password: password)
    var changed = entries[0]
    changed.server.host = "changed.invalid"
    let groups = TermArchive.grouped(entries + [entries[0], changed])
    XCTAssertEqual(groups.count, 2)
    XCTAssertEqual(groups[0].count, 2)
  }
  func testAndroidExportWhenProvided() throws {
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "android-export", withExtension: "term"))
    XCTAssertEqual(
      try TermArchive.decode(Data(contentsOf: url), password: password),
      try TermArchive.decode(fixture(), password: password))
  }
  @MainActor func testImportRollbackAndRecovery() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("servers.json")
    let store = ServerStore(file: file)
    var entries = try TermArchive.decode(fixture(), password: password)
    for i in entries.indices { entries[i].server.id = UUID() }
    defer { entries.forEach { Vault.delete($0.server.id) } }
    for stage in ["credential", "configuration"] {
      store.transferCheckpoint = { if $0 == stage { throw AppError.message("Injected failure") } }
      XCTAssertThrowsError(try store.importTerm(entries))
      XCTAssertTrue(store.servers.isEmpty)
      XCTAssertEqual(try Vault.read(entries[0].server.id).password, "")
    }
    store.transferCheckpoint = nil
    XCTAssertEqual(try store.importTerm(entries), 2)
    XCTAssertThrowsError(try store.importTerm(entries))
    let overflow = (0..<199).map { _ in
      TermEntry(
        server: Server(id: UUID(), host: "capacity.invalid", user: "test"), credentials: nil)
    }
    XCTAssertThrowsError(try store.importTerm(overflow))
    XCTAssertEqual(store.servers.count, 2)
    XCTAssertEqual(try Vault.read(entries[0].server.id).password, "synthetic-only")
    let orphan = UUID()
    defer { Vault.delete(orphan) }
    try Vault.save(Credentials(password: "orphan"), id: orphan)
    try JSONEncoder().encode([orphan, entries[0].server.id]).write(
      to: dir.appendingPathComponent("term-import-journal.json"))
    let recovered = ServerStore(file: file)
    XCTAssertNil(recovered.error)
    XCTAssertEqual(recovered.servers.count, 2)
    XCTAssertEqual(try Vault.read(orphan).password, "")
    XCTAssertEqual(try Vault.read(entries[0].server.id).password, "synthetic-only")
  }
}
