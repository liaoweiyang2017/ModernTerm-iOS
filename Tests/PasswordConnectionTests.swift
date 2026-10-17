import XCTest
@testable import ModerntermIOS

@MainActor final class PasswordConnectionTests: XCTestCase {
  struct Fixture: Decodable {
    let port, ipv6Port: Int
    let user, password, hostKey, rsaKey: String
  }
  func fixture() throws -> Fixture {
    guard let url = Bundle(for: Self.self).url(forResource: "PasswordFixture", withExtension: "json") else {
      throw XCTSkip("Run Scripts/password_integration.py")
    }
    return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
  }
  func testPasswordGatewayWithAtUsernameAndRestrictedChannels() async throws {
    let f = try fixture()
    var server = Server()
    server.host = "localhost"
    server.port = f.port
    server.user = f.user
    let storage = "hostkey." + server.endpoint
    let previous = UserDefaults.standard.object(forKey: storage)
    UserDefaults.standard.set(f.hostKey, forKey: storage)
    defer { UserDefaults.standard.set(previous, forKey: storage) }
    let session = SSHSession(server: server)
    defer { session.disconnect() }
    for _ in 0..<3 {
      session.connect(credentials: Credentials(password: f.password), startTerminal: true)
      for _ in 0..<100 {
        if session.writer != nil || session.error != nil { break }
        try await Task.sleep(nanoseconds: 100_000_000)
      }
      XCTAssertTrue(session.connected, session.error ?? "Not connected")
      XCTAssertNotNil(session.writer, session.error ?? "No terminal")
      guard session.writer != nil else { return }
      session.send(Data("PASSWORD_ECHO_OK\n".utf8))
      for _ in 0..<50 {
        if String(decoding: session.terminal.getTerminal().getBufferAsData(), as: UTF8.self).contains("PASSWORD_ECHO_OK") { break }
        try await Task.sleep(nanoseconds: 100_000_000)
      }
      XCTAssertTrue(String(decoding: session.terminal.getTerminal().getBufferAsData(), as: UTF8.self).contains("PASSWORD_ECHO_OK"))
      let rejected = expectation(description: "SFTP rejection completes")
      Task {
        do { try await session.refresh(); XCTFail("Fixture rejects SFTP") } catch {}
        rejected.fulfill()
      }
      await fulfillment(of: [rejected], timeout: 3)
      XCTAssertTrue(session.connected)
      XCTAssertNotNil(session.writer)
      session.disconnect()
      XCTAssertFalse(session.connected)
    }
    session.connect(credentials: Credentials(password: "deliberately-wrong"))
    for _ in 0..<100 {
      if session.error != nil { break }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    XCTAssertFalse(session.connected)
    XCTAssertNotNil(session.error)
    XCTAssertFalse(session.error?.contains(f.password) ?? false)
  }
  func testIPv6CancellationAndHostTrust() async throws {
    let f = try fixture()
    var server = Server()
    server.host = "::1"
    server.port = f.ipv6Port
    server.user = f.user
    let storage = "hostkey." + server.endpoint
    let previous = UserDefaults.standard.object(forKey: storage)
    UserDefaults.standard.removeObject(forKey: storage)
    defer { UserDefaults.standard.set(previous, forKey: storage) }
    let session = SSHSession(server: server)
    defer { session.disconnect() }
    session.connect(credentials: Credentials(password: f.password))
    for _ in 0..<100 {
      if session.trust != nil || session.error != nil { break }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    XCTAssertNotNil(session.trust, session.error ?? "Missing trust request")
    session.trust?.answer(false)
    session.trust = nil
    for _ in 0..<100 {
      if session.error != nil { break }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    XCTAssertFalse(session.connected)
    XCTAssertNil(UserDefaults.standard.object(forKey: storage))
    session.disconnect()
    UserDefaults.standard.set(f.hostKey, forKey: storage)
    session.connect(credentials: Credentials(password: f.password))
    session.disconnect()
    session.connect(credentials: Credentials(password: f.password))
    for _ in 0..<100 {
      if session.connected || session.error != nil { break }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    XCTAssertTrue(session.connected, session.error ?? "IPv6 reconnect failed")
    try await Task.sleep(nanoseconds: 200_000_000)
    XCTAssertTrue(session.connected, "Old callback must not disconnect the new generation")
  }

  func testExistingRSAUserKeyAuthentication() async throws {
    let f = try fixture()
    var server = Server()
    server.host = "127.0.0.1"
    server.port = f.port
    server.user = f.user
    server.keyLogin = true
    let storage = "hostkey." + server.endpoint
    let previous = UserDefaults.standard.object(forKey: storage)
    UserDefaults.standard.set(f.hostKey, forKey: storage)
    defer { UserDefaults.standard.set(previous, forKey: storage) }
    let session = SSHSession(server: server)
    defer { session.disconnect() }
    session.connect(credentials: Credentials(privateKey: f.rsaKey), startTerminal: true)
    for _ in 0..<100 {
      if session.writer != nil || session.error != nil { break }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    XCTAssertTrue(session.connected, session.error ?? "RSA user authentication failed")
    XCTAssertNotNil(session.writer)
  }

}
