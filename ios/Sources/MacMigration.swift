import Foundation

// Private, one-shot USB inbox. Never bundled with the app or synchronized to iCloud.
struct MacMigration: Codable {
  struct Entry: Codable {
    let server: Server
    let credentials: Credentials
  }
  let version: Int
  let sessions: [Entry]
  static let inboxName = "ModernTerm-Mac-Import.json"
  static let receiptName = "ModernTerm-Mac-Import-Receipt.json"
  static func decode(_ data: Data) throws -> MacMigration {
    guard data.count <= 4 * 1024 * 1024 else {
      throw AppError.message("Migration file exceeds 4 MiB.")
    }
    let value = try JSONDecoder().decode(Self.self, from: data)
    guard value.version == 1, value.sessions.count <= 200,
      Set(value.sessions.map { $0.server.id }).count == value.sessions.count,
      value.sessions.allSatisfy({
        $0.server.valid && $0.credentials.privateKey.utf8.count <= 1024 * 1024
      })
    else { throw AppError.message("Invalid or unsupported Mac migration file.") }
    return value
  }
}
struct MigrationReceipt: Codable {
  let imported: Int
  let skipped: Int
  let passwords: Int
  let keys: Int
  let date: Date
}
