import Combine
import Foundation
import Security

struct Server: Codable, Identifiable, Equatable {
  var id = UUID()
  var name = ""
  var host = ""
  var port = 22
  var user = ""
  var group = "Servers"
  var favorite = false
  var keyLogin = false
  var distribution = "Ubuntu"
  var valid: Bool {
    !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !user.isEmpty
      && (1...65535).contains(port)
  }
  var endpoint: String { "[\(host.lowercased())]:\(port)" }
}
struct Credentials: Codable {
  var password = ""
  var privateKey = ""
  var passphrase = ""
}
enum AppError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    if case .message(let s) = self { return s }
    return nil
  }
}
enum Vault {
  static let service = "com.modernterm.ios.credentials"
  static func query(_ id: UUID) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: id.uuidString,
    ]
  }
  static func read(_ id: UUID) throws -> Credentials {
    var q = query(id)
    q[kSecReturnData as String] = true
    var value: CFTypeRef?
    let result = SecItemCopyMatching(q as CFDictionary, &value)
    if result == errSecItemNotFound { return Credentials() }
    guard result == errSecSuccess, let data = value as? Data else {
      throw AppError.message("Could not read saved credentials (\(result)).")
    }
    return try JSONDecoder().decode(Credentials.self, from: data)
  }
  static func save(_ value: Credentials, id: UUID) throws {
    let data = try JSONEncoder().encode(value)
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    var status = SecItemUpdate(query(id) as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var q = query(id)
      q.merge(attributes) { _, new in new }
      status = SecItemAdd(q as CFDictionary, nil)
    }
    guard status == errSecSuccess else {
      throw AppError.message("Could not save credentials (\(status)).")
    }
  }
  static func delete(_ id: UUID) { SecItemDelete(query(id) as CFDictionary) }
}
@MainActor final class ServerStore: ObservableObject {
  @Published var servers: [Server] = []
  @Published var error: String?
  @Published var migrationMessage: String?
  private let file: URL
  init(file: URL? = nil) {
    self.file = file ?? URL.applicationSupportDirectory.appendingPathComponent("servers.json")
    if FileManager.default.fileExists(atPath: self.file.path) {
      do {
        servers = try JSONDecoder().decode([Server].self, from: Data(contentsOf: self.file))
      } catch {
        self.error =
          "Could not read sessions. Existing file has been preserved: \(error.localizedDescription)"
      }
    }
  }
  func save(_ server: Server, credentials: Credentials) throws {
    guard error == nil, server.valid else {
      throw AppError.message("Check host, username and port before saving.")
    }
    try Vault.save(credentials, id: server.id)
    var next = servers
    if let i = next.firstIndex(where: { $0.id == server.id }) {
      next[i] = server
    } else {
      next.append(server)
    }
    try persist(next)
    servers = next
  }
  func delete(_ server: Server) throws {
    let next = servers.filter { $0.id != server.id }
    try persist(next)
    servers = next
    Vault.delete(server.id)
  }
  func importMigration(_ migration: MacMigration) throws -> MigrationReceipt {
    guard error == nil else {
      throw AppError.message("Repair the existing session file before importing.")
    }
    let existing = Set(servers.map(\.id))
    let additions = migration.sessions.filter { !existing.contains($0.server.id) }
    guard servers.count + additions.count <= 200 else {
      throw AppError.message("Too many saved servers.")
    }
    var written: [(UUID, Credentials)] = []
    do {
      for entry in additions {
        let previous = try Vault.read(entry.server.id)
        try Vault.save(entry.credentials, id: entry.server.id)
        written.append((entry.server.id, previous))
      }
      let next = servers + additions.map(\.server)
      try persist(next)
      servers = next
    } catch {
      for (id, previous) in written { try? Vault.save(previous, id: id) }
      throw error
    }
    return MigrationReceipt(
      imported: additions.count, skipped: migration.sessions.count - additions.count,
      passwords: additions.filter { !$0.credentials.password.isEmpty }.count,
      keys: additions.filter { !$0.credentials.privateKey.isEmpty }.count, date: Date())
  }
  func importPendingMigration(directory: URL = .documentsDirectory) {
    let incoming = directory.appendingPathComponent(MacMigration.inboxName)
    guard FileManager.default.fileExists(atPath: incoming.path) else { return }
    do {
      let attributes = try incoming.resourceValues(forKeys: [.fileSizeKey])
      guard (attributes.fileSize ?? 0) <= 4 * 1024 * 1024 else {
        throw AppError.message("Migration file exceeds 4 MiB.")
      }
      var privateInbox = incoming
      var resourceValues = URLResourceValues()
      resourceValues.isExcludedFromBackup = true
      try privateInbox.setResourceValues(resourceValues)
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.complete], ofItemAtPath: incoming.path)
      let migration = try MacMigration.decode(Data(contentsOf: incoming))
      let receipt = try importMigration(migration)
      try JSONEncoder().encode(receipt).write(
        to: directory.appendingPathComponent(MacMigration.receiptName),
        options: [.atomic, .completeFileProtection])
      try FileManager.default.removeItem(at: incoming)
      migrationMessage =
        "Imported \(receipt.imported) servers, \(receipt.passwords) passwords and \(receipt.keys) keys. \(receipt.skipped) existing entries were preserved. The temporary import file was removed."
    } catch {
      migrationMessage =
        "Import failed; the private inbox file was preserved: \(error.localizedDescription)"
    }
  }
  private func persist(_ values: [Server]) throws {
    guard error == nil else {
      throw AppError.message("Session file is unreadable; repair it before making changes.")
    }
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(values).write(to: file, options: [.atomic, .completeFileProtection])
  }
}
func shellQuote(_ s: String) -> String {
  "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
func remotePath(_ directory: String, _ name: String) -> String {
  (directory == "/" ? "" : directory) + "/" + name
}
