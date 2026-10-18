import Foundation

struct TermIncomingFile: Identifiable {
  let id = UUID()
  let data: Data
  let name: String

  static func read(_ url: URL) throws -> TermIncomingFile {
    guard url.isFileURL else { throw AppError.message("Open a local .term attachment.") }
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: TermArchive.maximum + 1) ?? Data()
    guard data.count <= TermArchive.maximum else {
      throw AppError.message("Selected files exceed 16 MiB.")
    }
    guard data.count >= 64, data.prefix(8) == TermArchive.magic else {
      throw AppError.message("This is not an encrypted .term file.")
    }
    return TermIncomingFile(data: data, name: url.lastPathComponent)
  }
}
