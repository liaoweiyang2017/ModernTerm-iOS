import XCTest

@testable import ModerntermIOS

final class TermShareFileTests: XCTestCase {
  func testShareFileIsEncryptedAttachmentAndCleanupIsScoped() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try Data(
      contentsOf: XCTUnwrap(
        Bundle(for: TermArchiveTests.self).url(forResource: "reference", withExtension: "term")))
    let file = try TermShareFile.prepare(fixture, root: root)
    XCTAssertEqual(file.url.lastPathComponent, "ModernTerm-connections.term")
    XCTAssertEqual(try Data(contentsOf: file.url), fixture)
    XCTAssertEqual(
      try TermArchive.decode(Data(contentsOf: file.url), password: "互通测试-café-🔐-2026").count, 2)
    let unrelated = root.appendingPathComponent("keep.txt")
    try Data("keep".utf8).write(to: unrelated)
    TermShareFile.cleanup(root: root, now: Date().addingTimeInterval(25 * 60 * 60))
    XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    XCTAssertThrowsError(
      try TermShareFile.prepare(Data("plaintext configuration".utf8), root: root))
  }
}
