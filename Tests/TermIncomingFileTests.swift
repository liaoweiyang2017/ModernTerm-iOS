import XCTest

@testable import ModerntermIOS

final class TermIncomingFileTests: XCTestCase {
  func testBoundedLocalAttachmentRead() throws {
    let source = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "reference", withExtension: "term"))
    let file = try TermIncomingFile.read(source)
    XCTAssertEqual(try TermArchive.decode(file.data, password: "互通测试-café-🔐-2026").count, 2)
    XCTAssertThrowsError(
      try TermIncomingFile.read(URL(string: "https://example.invalid/test.term")!))
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".term")
    defer { try? FileManager.default.removeItem(at: tmp) }
    try Data("not an archive".utf8).write(to: tmp)
    XCTAssertThrowsError(try TermIncomingFile.read(tmp))
    try Data(repeating: 0, count: TermArchive.maximum + 1).write(to: tmp)
    XCTAssertThrowsError(try TermIncomingFile.read(tmp))
  }
}
