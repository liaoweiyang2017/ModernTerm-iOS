import Foundation
import SwiftUI
import UIKit

struct TermShareFile: Identifiable {
  let id = UUID()
  let url: URL
  static var directory: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "ModernTerm-SharedArchives", isDirectory: true)
  }
  static func prepare(_ data: Data, root: URL = directory) throws -> TermShareFile {
    guard data.count >= 64, data.count <= TermArchive.maximum, data.prefix(8) == TermArchive.magic
    else {
      throw AppError.message("Only encrypted .term files can be shared.")
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    cleanup(root: root)
    let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    let url = folder.appendingPathComponent("ModernTerm-connections.term")
    do {
      try data.write(to: url, options: [.atomic, .completeFileProtection])
      var file = url
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try file.setResourceValues(values)
      return TermShareFile(url: url)
    } catch {
      try? FileManager.default.removeItem(at: folder)
      throw error
    }
  }
  func remove() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  static func cleanup(root: URL = directory, now: Date = Date()) {
    let folders =
      (try? FileManager.default.contentsOfDirectory(
        at: root, includingPropertiesForKeys: [.creationDateKey])) ?? []
    for folder in folders where UUID(uuidString: folder.lastPathComponent) != nil {
      if let created = try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate,
        now.timeIntervalSince(created) > 24 * 60 * 60
      {
        try? FileManager.default.removeItem(at: folder)
      }
    }
  }
}

struct TermShareSheet: UIViewControllerRepresentable {
  let file: TermShareFile
  let completion: (Error?) -> Void
  func makeUIViewController(context: Context) -> UIActivityViewController {
    // Passing a file URL produces an attachment, not a link or plaintext message.
    let controller = UIActivityViewController(activityItems: [file.url], applicationActivities: nil)
    controller.completionWithItemsHandler = { _, _, _, error in completion(error) }
    return controller
  }
  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
