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
