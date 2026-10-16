import SwiftUI
import UniformTypeIdentifiers

struct SharedFile: Identifiable {
  let id = UUID()
  let url: URL
}
struct EditingFile: Identifiable {
  var id: String { path }
  let path: String
  let baseline: Data
  let text: String
}
struct FilesScreen: View {
  @ObservedObject var session: SSHSession
  @State private var location = ""
  @State private var selection = Set<String>()
  @State private var importing = false
  @State private var deleteConfirm = false
  @State private var sharing: SharedFile?
  @State private var editing: EditingFile?
  @State private var error: String?
  @State private var working = false
  @State private var selecting = false
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        TextField("Remote path", text: $location).textInputAutocapitalization(.never)
          .autocorrectionDisabled().onSubmit { perform { try await session.refresh(location) } }
        Button("Go", systemImage: "arrow.right.circle") {
          perform { try await session.refresh(location) }
        }
        Button("Refresh", systemImage: "arrow.clockwise") {
          perform { try await session.refresh() }
        }
      }.padding(10).background(.quaternary)
      HStack {
        Button("Upload", systemImage: "arrow.up.doc") { importing = true }
        Spacer()
        Button(selecting ? "Done" : "Select") {
          selecting.toggle()
          selection.removeAll()
        }
        if selecting {
          Button("Delete", systemImage: "trash", role: .destructive) { deleteConfirm = true }
            .disabled(selection.isEmpty)
        }
      }.padding(10)
      if working { ProgressView().padding(5) }
      List {
        Button("..", systemImage: "arrow.up.folder") {
          perform { try await session.refresh(remotePath(session.path, "..")) }
        }
        ForEach(session.files) { file in
          Button {
            if selecting {
              if selection.contains(file.name) {
                selection.remove(file.name)
              } else {
                selection.insert(file.name)
              }
            } else if file.isDirectory {
              perform { try await session.refresh(remotePath(session.path, file.name)) }
            } else if file.isRegular {
              download(file)
            }
          } label: {
            HStack {
              if selecting {
                Image(
                  systemName: selection.contains(file.name) ? "checkmark.circle.fill" : "circle"
                ).foregroundStyle(.tint)
              }
              Image(systemName: file.isDirectory ? "folder.fill" : "doc").foregroundStyle(
                file.isDirectory ? Color.orange : Color.secondary)
              Text(file.name).foregroundStyle(.primary).lineLimit(1)
              Spacer()
              if !file.isDirectory {
                Text(
                  ByteCountFormatter.string(
                    fromByteCount: Int64(clamping: file.size), countStyle: .file)
                ).font(.caption).foregroundStyle(.secondary)
              }
            }
          }
          .contextMenu {
            if file.isRegular {
              Button("Download", systemImage: "arrow.down.doc") { download(file) }
              Button("Edit text", systemImage: "square.and.pencil") {
                perform {
                  let path = remotePath(session.path, file.name)
                  let data = try await session.readFile(path)
                  guard let text = String(data: data, encoding: .utf8) else {
                    throw AppError.message("Only UTF-8 text files can be edited.")
                  }
                  editing = EditingFile(path: path, baseline: data, text: text)
                }
              }
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
              selection = [file.name]
              deleteConfirm = true
            }
          }
        }
      }.listStyle(.plain).disabled(working || !session.connected)
    }.onAppear { location = session.path }.onChange(of: session.path) { _, value in
      location = value
      selection.removeAll()
    }
    .disabled(!session.connected)
    .fileImporter(
      isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: true
    ) { result in
      switch result {
      case .success(let urls):
        perform {
          for url in urls {
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            try await session.upload(url)
          }
        }
      case .failure(let e): error = e.localizedDescription
      }
    }
    .sheet(item: $sharing) { item in ShareSheet(url: item.url) }
    .sheet(item: $editing) { item in RemoteEditorScreen(session: session, file: item) }
    .confirmationDialog(
      "Permanently delete \(selection.count) selected item(s)? Nonempty folders are protected.",
      isPresented: $deleteConfirm, titleVisibility: .visible
    ) {
      Button("Delete selected", role: .destructive) {
        let items = session.files.filter { selection.contains($0.name) }
        perform {
          try await session.delete(items)
          selection.removeAll()
        }
      }
    }
    .alert("SFTP", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
      Button("OK") { error = nil }
    } message: {
      Text(error ?? "")
    }
  }
  private func download(_ file: RemoteFile) {
    perform {
      sharing = SharedFile(
        url: try await session.download(remotePath(session.path, file.name), name: file.name))
    }
  }
  private func perform(_ action: @escaping () async throws -> Void) {
    guard !working else { return }
    working = true
    Task {
      defer { working = false }
      do { try await action() } catch { self.error = error.localizedDescription }
    }
  }
}
struct ShareSheet: UIViewControllerRepresentable {
  let url: URL
  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [url], applicationActivities: nil)
  }
  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
struct RemoteEditorScreen: View {
  @ObservedObject var session: SSHSession
  let file: EditingFile
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @State private var baseline = Data()
  @State private var original = ""
  @State private var working = false
  @State private var error: String?
  @State private var discard = false
  var body: some View {
    NavigationStack {
      TextEditor(text: $text).font(.system(size: 13, design: .monospaced)).autocorrectionDisabled()
        .textInputAutocapitalization(.never).disabled(working)
        .navigationTitle(URL(fileURLWithPath: file.path).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Close") { if text != original { discard = true } else { dismiss() } }.disabled(
              working)
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(working ? "Saving…" : "Save") {
              let data = Data(text.utf8)
              working = true
              Task {
                defer { working = false }
                do {
                  try await session.saveText(data, remote: file.path, baseline: baseline)
                  baseline = data
                  original = text
                } catch { self.error = error.localizedDescription }
              }
            }.disabled(working || text == original)
          }
          ToolbarItem(placement: .bottomBar) {
            Text("\(text.components(separatedBy:"\n").count) lines · UTF-8").font(.caption)
          }
        }
    }.onAppear {
      text = file.text
      original = file.text
      baseline = file.baseline
    }.interactiveDismissDisabled(text != original || working)
      .confirmationDialog("Discard unsaved changes?", isPresented: $discard) {
        Button("Discard", role: .destructive) { dismiss() }
      }
      .alert(
        "Save failed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
      ) {
        Button("OK") { error = nil }
      } message: {
        Text(error ?? "")
      }
  }
}
