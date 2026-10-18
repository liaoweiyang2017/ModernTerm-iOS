import XCTest

@testable import ModerntermIOS

@MainActor final class MigrationTests: XCTestCase {
  func testImportPreservesExistingAndIsIdempotent() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ServerStore(file: directory.appendingPathComponent("servers.json"))
    var first = Server()
    first.host = "example.invalid"
    first.user = "test"
    first.name = "Existing"
    var second = Server()
    second.host = "other.invalid"
    second.user = "test"
    second.name = "Imported"
    defer {
      Vault.delete(first.id)
      Vault.delete(second.id)
    }
    try store.save(first, credentials: Credentials(password: "keep-original"))
    var changed = first
    changed.name = "Do not overwrite"
    let migration = MacMigration(
      version: 1,
      sessions: [
        .init(server: changed, credentials: Credentials(password: "do-not-use")),
        .init(server: second, credentials: Credentials(password: "test-only")),
      ])
    let validated = try MacMigration.decode(JSONEncoder().encode(migration))
    let result = try store.importMigration(validated)
    XCTAssertEqual(result.imported, 1)
    XCTAssertEqual(result.skipped, 1)
    XCTAssertEqual(store.servers.first?.name, "Existing")
    XCTAssertEqual(try Vault.read(first.id).password, "keep-original")
    XCTAssertEqual(try Vault.read(second.id).password, "test-only")
    let repeated = try store.importMigration(migration)
    XCTAssertEqual(repeated.imported, 0)
    XCTAssertEqual(repeated.skipped, 2)
  }
  func testPrivateInboxRemovedOnlyAfterSuccess() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ServerStore(file: directory.appendingPathComponent("servers.json"))
    var server = Server()
    server.host = "fixture.invalid"
    server.user = "test"
    defer { Vault.delete(server.id) }
    let migration = MacMigration(
      version: 1, sessions: [.init(server: server, credentials: Credentials(password: "test-only"))]
    )
    let inbox = directory.appendingPathComponent(MacMigration.inboxName)
    try JSONEncoder().encode(migration).write(to: inbox)
    store.importPendingMigration(directory: directory)
    XCTAssertFalse(FileManager.default.fileExists(atPath: inbox.path))
    let receipt = try JSONDecoder().decode(
      MigrationReceipt.self,
      from: Data(contentsOf: directory.appendingPathComponent(MacMigration.receiptName)))
    XCTAssertEqual(receipt.imported, 1)
    XCTAssertEqual(receipt.passwords, 1)
    try Data("invalid".utf8).write(to: inbox)
    store.importPendingMigration(directory: directory)
    XCTAssertTrue(FileManager.default.fileExists(atPath: inbox.path))
    XCTAssertTrue(store.migrationMessage?.contains("failed") == true)
  }
  func testRejectsUnknownVersionAndDuplicateIdentifiers() throws {
    var server = Server()
    server.host = "fixture.invalid"
    server.user = "test"
    let entry = MacMigration.Entry(server: server, credentials: Credentials())
    XCTAssertThrowsError(
      try MacMigration.decode(JSONEncoder().encode(MacMigration(version: 2, sessions: [entry]))))
    XCTAssertThrowsError(
      try MacMigration.decode(
        JSONEncoder().encode(MacMigration(version: 1, sessions: [entry, entry]))))
  }
}
