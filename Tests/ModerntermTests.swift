import XCTest

@testable import ModerntermIOS

@MainActor final class ModerntermTests: XCTestCase {
  func testServerValidationAndSecretSeparation() throws {
    var s = Server()
    XCTAssertFalse(s.valid)
    s.host = "localhost"
    s.user = "tester"
    XCTAssertTrue(s.valid)
    s.port = 65536
    XCTAssertFalse(s.valid)
    s.port = 22
    let data = try JSONEncoder().encode(s)
    XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("password"))
    XCTAssertEqual(try JSONDecoder().decode(Server.self, from: data), s)
  }
  func testShellEscapingAndPaths() {
    XCTAssertEqual(shellQuote("a'b"), "'a'\\''b'")
    XCTAssertEqual(remotePath("/", "name"), "/name")
    XCTAssertEqual(remotePath("/home/test", "a b"), "/home/test/a b")
  }
  func testVaultRoundtrip() throws {
    let id = UUID()
    defer { Vault.delete(id) }
    try Vault.save(
      Credentials(password: "test-only", privateKey: "key-test", passphrase: "phrase"), id: id)
    XCTAssertEqual(try Vault.read(id).password, "test-only")
    try Vault.save(Credentials(password: "changed"), id: id)
    XCTAssertEqual(try Vault.read(id).password, "changed")
    Vault.delete(id)
    XCTAssertEqual(try Vault.read(id).password, "")
  }
  func testPalettes() {
    XCTAssertEqual(Palette.all.count, 18)
    XCTAssertEqual(Set(Palette.all.map(\.id)).count, 18)
    XCTAssertTrue(Palette.all.allSatisfy { $0.ansi.count == 16 })
  }
  func testChangedHostKeyRejected() async throws {
    struct Fixture: Decodable {
      let port: Int
      let user: String
      let key: String
    }
    guard let url = Bundle(for: Self.self).url(forResource: "Fixture", withExtension: "json") else {
      throw XCTSkip("Run Scripts/integration.py")
    }
    let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    var server = Server()
    server.host = "127.0.0.1"
    server.port = fixture.port
    server.user = fixture.user
    server.keyLogin = true
    let key = "hostkey." + server.endpoint
    let previous = UserDefaults.standard.object(forKey: key)
    UserDefaults.standard.set("different-known-host-key", forKey: key)
    defer {
      if let previous {
        UserDefaults.standard.set(previous, forKey: key)
      } else {
        UserDefaults.standard.removeObject(forKey: key)
      }
    }
    let session = SSHSession(server: server)
    defer { session.disconnect() }
    session.connect(credentials: Credentials(privateKey: fixture.key))
    for _ in 0..<100 {
      if session.error != nil { break }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    XCTAssertFalse(session.connected)
    XCTAssertTrue(
      session.error?.contains("changed") == true, session.error ?? "Missing host-key rejection")
    XCTAssertNil(session.trust)
  }
  func testSSHAndSFTPRoundtrip() async throws {
    struct Fixture: Decodable {
      let port: Int
      let user: String
      let key: String
      let hostKey: String
      let directory: String
    }
    guard let url = Bundle(for: Self.self).url(forResource: "Fixture", withExtension: "json") else {
      throw XCTSkip("Run Scripts/integration.py for temporary SSH fixture")
    }
    let f = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    var server = Server()
    server.name = "Ephemeral SSH test"
    server.host = "127.0.0.1"
    server.port = f.port
    server.user = f.user
    server.keyLogin = true
    let key = "hostkey." + server.endpoint
    let old = UserDefaults.standard.object(forKey: key)
    UserDefaults.standard.set(f.hostKey, forKey: key)
    defer {
      if let old {
        UserDefaults.standard.set(old, forKey: key)
      } else {
        UserDefaults.standard.removeObject(forKey: key)
      }
    }
    let session = SSHSession(server: server)
    defer { session.disconnect() }
    session.connect(credentials: Credentials(privateKey: f.key))
    for _ in 0..<200 {
      if session.writer != nil { break }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    XCTAssertTrue(session.connected, session.error ?? session.status)
    XCTAssertNotNil(session.writer)
    guard session.connected, session.writer != nil else { return }
    session.send(Data("printf 'IOS_PTY_OK\\n'\n".utf8))
    for _ in 0..<50 {
      if String(decoding: session.terminal.getTerminal().getBufferAsData(), as: UTF8.self).contains(
        "IOS_PTY_OK")
      {
        break
      }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    XCTAssertTrue(
      String(decoding: session.terminal.getTerminal().getBufferAsData(), as: UTF8.self).contains(
        "IOS_PTY_OK"))
    try await session.refresh(f.directory)
    let local = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".txt")
    let original = Data("ModernTerm iOS UTF-8 中文\n".utf8)
    try original.write(to: local)
    defer { try? FileManager.default.removeItem(at: local) }
    try await session.upload(local)
    let remote = remotePath(f.directory, local.lastPathComponent)
    let downloaded = try await session.download(remote, name: local.lastPathComponent)
    defer { try? FileManager.default.removeItem(at: downloaded.deletingLastPathComponent()) }
    XCTAssertEqual(try Data(contentsOf: downloaded), original)
    let edited = Data("edited 中文\n".utf8)
    try await session.saveText(edited, remote: remote, baseline: original)
    let roundtrip = try await session.readFile(remote)
    XCTAssertEqual(roundtrip, edited)
    do {
      try await session.saveText(original, remote: remote, baseline: original)
      XCTFail("Conflict must be rejected")
    } catch {}
    try await session.refresh()
    let selected = session.files.filter { $0.name == local.lastPathComponent }
    XCTAssertEqual(selected.count, 1)
    try await session.delete(selected)
    XCTAssertFalse(session.files.contains { $0.name == local.lastPathComponent })
  }
}
