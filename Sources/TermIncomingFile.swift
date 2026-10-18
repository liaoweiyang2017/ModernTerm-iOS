import Foundation

struct TermIncomingFile: Identifiable {
  let id = UUID()
  let data: Data
  let name: String

  static func readBatch(_ urls: [URL]) throws -> [TermIncomingFile] {
    guard !urls.isEmpty, urls.count <= 20 else { throw AppError.message("Choose 1–20 files.") }
    var total = 0
    return try urls.map { url in
      let file = try read(url)
      total += file.data.count
      guard total <= TermArchive.maximum else {
        throw AppError.message("Selected files exceed 16 MiB.")
      }
      return file
    }
  }

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
