import SwiftUI
import UniformTypeIdentifiers

extension UTType {
  static var termArchive: UTType {
    UTType(exportedAs: "com.modernterm.archive", conformingTo: .data)
  }
}
struct TermDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.termArchive] }
  var data: Data
  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}
struct TermTransferScreen: View {
  @EnvironmentObject var store: ServerStore
  @Environment(\.dismiss) private var dismiss
  @State private var selected = Set<UUID>()
  @State private var includeSecrets = false
  @State private var password = ""
  @State private var repeatPassword = ""
  @State private var busy = false
  @State private var operation = UUID()
  @State private var message: String?
  @State private var picking = false
  @State private var exporting = false
  @State private var document: TermDocument?
  @State private var files: [Data] = []
  @State private var fileNames: [String] = []
  @State private var mergedDuplicates = 0
  @State private var fileIndex = 0
  @State private var decoded: [TermEntry] = []
  @State private var groups: [[TermEntry]] = []
  @State private var choices: [UUID: Int] = [:]
  @State private var copies = Set<UUID>()
  var ready: [TermEntry] {
    groups.compactMap { group in
      let id = group[0].server.id
      let index = choices[id] ?? (group.count == 1 ? 0 : -1)
      guard index >= 0, index < group.count else { return nil }
      var entry = group[index]
      if store.servers.contains(where: { $0.id == id }) {
        guard copies.contains(id) else { return nil }
        entry.server.id = UUID()
      }
      return entry
    }
  }
  var body: some View {
    NavigationStack {
      Form {
        if files.isEmpty && groups.isEmpty {
          Section("Export saved SSH connections") {
            Button(selected.count == store.servers.count ? "Deselect all" : "Select all") {
              selected = selected.count == store.servers.count ? [] : Set(store.servers.map(\.id))
            }
            ForEach(store.servers) { server in
              Toggle(
                isOn: Binding(
                  get: { selected.contains(server.id) },
                  set: { if $0 { selected.insert(server.id) } else { selected.remove(server.id) } })
              ) {
                VStack(alignment: .leading) {
                  Text(server.name.isEmpty ? server.host : server.name)
                  Text("\(server.user)@\(server.host):\(server.port)").font(.caption)
                }
              }
            }
            Toggle("Include saved passwords and private keys", isOn: $includeSecrets)
            Text(
              "The entire file is encrypted. Use a separate long password; a forgotten file password cannot be recovered."
            ).font(.caption)
            SecureField("File password (12+ characters)", text: $password)
            SecureField("Repeat file password", text: $repeatPassword)
            Button("Export \(selected.count) connections") { export() }.disabled(
              selected.isEmpty || password != repeatPassword || password.isEmpty)
          }
          Section("Import") {
            Button("Choose .term files…") {
              password = ""
              repeatPassword = ""
              picking = true
            }
            Text(
              "Select up to 20 files / 16 MiB total. You will preview all connections before saving. Host trust is not transferred."
            ).font(.caption)
          }
        } else if !files.isEmpty {
          Section("Unlock file \(fileIndex + 1) of \(files.count)") {
            Text(
              fileNames.indices.contains(fileIndex) ? fileNames[fileIndex] : "Encrypted connections"
            )
            SecureField("File password", text: $password)
            Button("Unlock and continue") { unlock() }
            Button("Cancel import", role: .cancel) { reset() }
          }
        } else {
          Section("Import preview") {
            Text(
              "\(ready.count) new connections; \(groups.count - ready.count) skipped. Nothing will connect automatically."
            )
            Text(
              "\(groups.filter { store.servers.map(\.id).contains($0[0].server.id) }.count) already saved; \(groups.filter { $0.count > 1 }.count) conflicting IDs; \(mergedDuplicates) identical entries merged. Versions follow selected file order."
            ).font(.caption)
            ForEach(groups.indices, id: \.self) { i in
              let group = groups[i]
              let id = group[0].server.id
              VStack(alignment: .leading) {
                Text(group[0].server.name.isEmpty ? group[0].server.host : group[0].server.name)
                Picker(
                  group.count > 1 ? "Conflicting versions — choose one" : "Import",
                  selection: Binding(
                    get: { choices[id] ?? (group.count == 1 ? 0 : -1) }, set: { choices[id] = $0 })
                ) {
                  Text("Skip").tag(-1)
                  ForEach(group.indices, id: \.self) { n in
                    Text(
                      "\(n + 1): \(group[n].server.user)@\(group[n].server.host):\(group[n].server.port) · \(group[n].credentials == nil ? "configuration only" : "with credentials")"
                    ).tag(n)
                  }
                }
                if store.servers.contains(where: { $0.id == id }) {
                  Toggle(
                    "Already saved — import as a new copy",
                    isOn: Binding(
                      get: { copies.contains(id) },
                      set: { if $0 { copies.insert(id) } else { copies.remove(id) } }))
                }
              }
            }
            Text("Configuration-only connections may need credentials before connecting.").font(
              .caption)
            Button("Import \(ready.count) connections") {
              do {
                let count = try store.importTerm(ready)
                reset()
                message = "Imported \(count) connections."
              } catch { message = error.localizedDescription }
            }.disabled(ready.isEmpty)
            Button("Cancel import", role: .cancel) { reset() }
          }
        }
        if busy { ProgressView("Processing encrypted file…") }
        if let message { Text(message).foregroundStyle(.secondary) }
      }
      .disabled(busy)
      .navigationTitle("SSH transfer")
      .toolbar {
        Button(busy ? "Cancel" : "Done") {
          reset()
          dismiss()
        }
      }
      .fileImporter(
        isPresented: $picking, allowedContentTypes: [.termArchive, .data],
        allowsMultipleSelection: true
      ) { result in
        do {
          let urls = try result.get()
          guard !urls.isEmpty, urls.count <= 20 else {
            throw AppError.message("Choose 1–20 files.")
          }
          var total = 0
          let read = try urls.map { url in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: TermArchive.maximum + 1) ?? Data()
            total += data.count
            guard total <= TermArchive.maximum else {
              throw AppError.message("Selected files exceed 16 MiB.")
            }
            return data
          }
          reset()
          files = read
          fileNames = urls.map { $0.lastPathComponent }
        } catch {
          reset()
          message = error.localizedDescription
        }
      }
      .fileExporter(
        isPresented: $exporting, document: document, contentType: .termArchive,
        defaultFilename: "ModernTerm-connections.term"
      ) { result in
        document = nil
        switch result {
        case .success: message = "Encrypted file exported."
        case .failure: message = "Export cancelled or failed."
        }
      }
    }.onDisappear {
      // Older iOS versions also call this when presenting the system document picker.
      // Its FileDocument must stay alive until the export completion callback.
      if !exporting && !picking {
        reset()
        document = nil
      }
    }
  }
  private func reset() {
    operation = UUID()
    busy = false
    files = []
    fileNames = []
    mergedDuplicates = 0
    fileIndex = 0
    decoded = []
    groups = []
    choices = [:]
    copies = []
    password = ""
    repeatPassword = ""
    message = nil
  }
  private func export() {
    do {
      let entries = try store.servers.filter { selected.contains($0.id) }.map {
        TermEntry(server: $0, credentials: includeSecrets ? try Vault.read($0.id) : nil)
      }
      let secret = password
      busy = true
      message = nil
      let token = operation
      Task {
        do {
          let data = try await Task.detached { try TermArchive.encode(entries, password: secret) }
            .value
          guard token == operation else { return }
          document = TermDocument(data: data)
          exporting = true
        } catch {
          guard token == operation else { return }
          message = error.localizedDescription
        }
        password = ""
        repeatPassword = ""
        busy = false
      }
    } catch { message = error.localizedDescription }
  }
  private func unlock() {
    let data = files[fileIndex]
    let secret = password
    busy = true
    message = nil
    let token = operation
    Task {
      do {
        let entries = try await Task.detached { try TermArchive.decode(data, password: secret) }
          .value
        guard token == operation else { return }
        guard decoded.count + entries.count <= 200 else {
          throw AppError.message("Import exceeds 200 connections.")
        }
        decoded += entries
        fileIndex += 1
        password = ""
        if fileIndex == files.count {
          groups = TermArchive.grouped(decoded)
          mergedDuplicates = decoded.count - groups.flatMap { $0 }.count
          decoded = []
          files = []
        }
      } catch {
        guard token == operation else { return }
        message = error.localizedDescription
      }
      busy = false
    }
  }
}
