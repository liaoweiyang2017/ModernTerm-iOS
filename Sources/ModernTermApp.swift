import SwiftUI

@main struct ModernTermApp: App {
  @StateObject private var store = ServerStore()
  @StateObject private var workspace = Workspace()
  @Environment(\.scenePhase) private var phase
  @AppStorage("appearance") private var appearance = "system"
  var body: some Scene {
    WindowGroup {
      Group {
        #if DEBUG
          if ProcessInfo.processInfo.arguments.contains("--monitor-preview") {
            MonitoringPreview()
          } else {
            RootScreen()
          }
        #else
          RootScreen()
        #endif
      }.environmentObject(store).environmentObject(workspace).preferredColorScheme(
        appearance == "dark" ? .dark : appearance == "light" ? .light : nil
      )
      .onChange(of: phase) { _, value in
        if value == .background { workspace.disconnectAll() }
        if value == .active { store.importPendingMigration() }
      }
    }
  }
}
@MainActor final class Workspace: ObservableObject {
  @Published var sessions: [SSHSession] = []
  @Published var selected: UUID?
  func open(_ server: Server) {
    if let existing = sessions.first(where: { $0.server.id == server.id }) {
      selected = existing.id
      existing.connect()
      return
    }
    guard sessions.count < 8 else { return }
    let session = SSHSession(server: server)
    sessions.append(session)
    selected = session.id
    session.connect()
  }
  func close(_ session: SSHSession) {
    session.disconnect()
    sessions.removeAll { $0.id == session.id }
    if selected == session.id { selected = sessions.first?.id }
  }
  func disconnectAll() { sessions.forEach { $0.disconnect() } }
}
struct RootScreen: View {
  @EnvironmentObject var store: ServerStore
  @EnvironmentObject var workspace: Workspace
  @State private var compactColumn: NavigationSplitViewColumn = .sidebar
  @State private var editing: Server?
  @State private var query = ""
  @State private var overview = false
  @State private var settings = false
  @State private var macros = false
  @State private var transfer = false
  @State private var incomingFile: TermIncomingFile?
  @State private var readingAttachment = false
  @State private var deleteServer: Server?
  @State private var error: String?
  var filtered: [Server] {
    store.servers.filter {
      query.isEmpty || ($0.name + $0.host + $0.group).localizedCaseInsensitiveContains(query)
    }.sorted { a, b in
      a.favorite != b.favorite
        ? a.favorite : a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
  }
  var body: some View {
    NavigationSplitView(preferredCompactColumn: $compactColumn) {
      List(selection: $workspace.selected) {
        if !workspace.sessions.isEmpty {
          Section("Open sessions") {
            ForEach(workspace.sessions) { session in
              MonitoringSessionRow(session: session).tag(session.id)
                .contextMenu {
                  Button("Close session", role: .destructive) { workspace.close(session) }
                }
            }
          }
        }
        Section("Servers") {
          ForEach(filtered) { server in
            Button {
              if workspace.sessions.count >= 8
                && !workspace.sessions.contains(where: { $0.server.id == server.id })
              {
                error = "Close a session before opening another (maximum 8)."
              } else {
                workspace.open(server)
              }
            } label: {
              HStack(spacing: 12) {
                Image(systemName: "server.rack").foregroundStyle(.orange).font(.title3)
                VStack(alignment: .leading) {
                  Text(server.name.isEmpty ? server.host : server.name).foregroundStyle(.primary)
                  Text("\(server.user)@\(server.host):\(server.port)").font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if server.favorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }
              }.padding(.vertical, 4)
            }.contextMenu {
              Button("Edit", systemImage: "pencil") { editing = server }
              Button("Delete", systemImage: "trash", role: .destructive) { deleteServer = server }
            }
          }
        }
      }.overlay {
        if store.servers.isEmpty {
          ContentUnavailableView(
            "Your servers, wherever you are", systemImage: "terminal",
            description: Text("Add an SSH server to open its terminal and SFTP files."))
        }
      }
      .searchable(text: $query, prompt: "Search servers")
      .navigationTitle("ModernTerm")
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button("SSH transfer", systemImage: "square.and.arrow.up.on.square") { transfer = true }
          Button("Add server", systemImage: "plus") { editing = Server() }
        }
        ToolbarItemGroup(placement: .bottomBar) {
          Button("Settings", systemImage: "gearshape") { settings = true }
          Spacer()
          Button("Overview", systemImage: "chart.xyaxis.line") { overview = true }
          Spacer()
          Button("Macros", systemImage: "curlybraces") { macros = true }
        }
      }
    } detail: {
      if let session = workspace.sessions.first(where: { $0.id == workspace.selected }) {
        SessionScreen(session: session)
      } else {
        ContentUnavailableView(
          "ModernTerm", systemImage: "terminal",
          description: Text("Select a server to connect securely."))
      }
    }
    .onChange(of: workspace.selected) { _, value in if value != nil { compactColumn = .detail } }
    .task { store.importPendingMigration() }
    .sheet(item: $editing) { server in ServerEditor(server: server) }
    .sheet(isPresented: $overview) {
      NavigationStack {
        MonitoringOverview { server in
          workspace.open(server)
          overview = false
        }
        .toolbar { Button("Done") { overview = false } }
      }
    }
    .sheet(isPresented: $settings) { SettingsScreen() }
    .sheet(isPresented: $transfer) { TermTransferScreen() }
    .sheet(item: $incomingFile) { file in TermTransferScreen(incoming: file) }
    .overlay {
      if readingAttachment {
        ProgressView("Opening attachment…").padding().background(
          .regularMaterial, in: RoundedRectangle(cornerRadius: 12))
      }
    }
    .onOpenURL { url in
      guard
        !readingAttachment && incomingFile == nil && !transfer && editing == nil && !settings
          && !overview && !macros
      else {
        error = "Finish or cancel the current screen, then open the attachment again."
        return
      }
      readingAttachment = true
      Task {
        defer { readingAttachment = false }
        do {
          incomingFile = try await Task.detached { try TermIncomingFile.read(url) }.value
        } catch { self.error = error.localizedDescription }
      }
    }
    .sheet(isPresented: $macros) {
      MacrosScreen(session: workspace.sessions.first(where: { $0.id == workspace.selected }))
    }
    .alert(
      "ModernTerm",
      isPresented: Binding(
        get: { error != nil || store.error != nil }, set: { if !$0 { error = nil } })
    ) {
      Button("OK") { error = nil }
    } message: {
      Text(error ?? store.error ?? "")
    }
    .confirmationDialog(
      "Delete this saved server and its credentials?",
      isPresented: Binding(get: { deleteServer != nil }, set: { if !$0 { deleteServer = nil } }),
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        if let server = deleteServer {
          do { try store.delete(server) } catch { self.error = error.localizedDescription }
        }
        deleteServer = nil
      }
    }
  }
}
struct ServerEditor: View {
  @EnvironmentObject var store: ServerStore
  @Environment(\.dismiss) private var dismiss
  @State var server: Server
  @State private var credentials = Credentials()
  @State private var importing = false
  @State private var error: String?
  var body: some View {
    NavigationStack {
      Form {
        Section("Server") {
          TextField("Name", text: $server.name)
          TextField("Host", text: $server.host).textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          TextField("Port", value: $server.port, format: .number).keyboardType(.numberPad)
          TextField("Username", text: $server.user).textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          TextField("Group", text: $server.group)
          Toggle("Favorite", isOn: $server.favorite)
          Picker("Distribution", selection: $server.distribution) {
            ForEach(["Ubuntu", "Debian", "Fedora", "Linux", "macOS"], id: \.self) { Text($0) }
          }
        }
        Section("Authentication") {
          Toggle("Use private key", isOn: $server.keyLogin)
          if server.keyLogin {
            Button(credentials.privateKey.isEmpty ? "Import private key…" : "Replace private key…")
            { importing = true }
            SecureField("Key passphrase (optional)", text: $credentials.passphrase)
            Text("OpenSSH Ed25519 and RSA keys are supported. Private keys stay on this device.")
              .font(.caption).foregroundStyle(.secondary)
          } else {
            SecureField("Password", text: $credentials.password).textContentType(.password)
          }
          Text(
            "Saved in the iOS Keychain, without repeated authorization prompts. Not synced to iCloud."
          ).font(.caption).foregroundStyle(.secondary)
        }
      }.navigationTitle("SSH server").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            do {
              server.host = server.host.trimmingCharacters(in: .whitespacesAndNewlines)
              try store.save(server, credentials: credentials)
              dismiss()
            } catch { self.error = error.localizedDescription }
          }.disabled(!server.valid)
        }
      }
    }.onAppear {
      do { credentials = try Vault.read(server.id) } catch {
        self.error = error.localizedDescription
      }
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .text]) { result in
      do {
        let url = try result.get()
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= 1024 * 1024 else {
          throw AppError.message("Key file is too large.")
        }
        let key = try String(contentsOf: url, encoding: .utf8)
        guard key.contains("PRIVATE KEY") else {
          throw AppError.message("Select a private key, not a public key.")
        }
        credentials.privateKey = key
      } catch { self.error = error.localizedDescription }
    }
    .alert("Server", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
      Button("OK") { error = nil }
    } message: {
      Text(error ?? "")
    }
  }
}
struct SettingsScreen: View {
  @EnvironmentObject private var store: ServerStore
  @Environment(\.dismiss) private var dismiss
  @AppStorage("appearance") private var appearance = "system"
  @AppStorage("fontSize") private var fontSize = 13.0
  @AppStorage("palette") private var palette = "modernterm"
  @AppStorage("monitorInterval") private var monitorInterval = 10
  @AppStorage("followDirectory") private var follow = false
  var body: some View {
    NavigationStack {
      Form {
        Section("Appearance") {
          Picker("Theme", selection: $appearance) {
            Text("System").tag("system")
            Text("Light").tag("light")
            Text("Dark").tag("dark")
          }
          Picker("Terminal colors", selection: $palette) {
            ForEach(Palette.all) { Text($0.name).tag($0.id) }
          }
          Slider(value: $fontSize, in: 10...24, step: 1) { Text("Font size") }
          Text("SF Mono · \(Int(fontSize)) pt")
        }
        Section("Monitoring") {
          Picker("Refresh interval", selection: $monitorInterval) {
            Text("5 seconds").tag(5)
            Text("10 seconds").tag(10)
            Text("30 seconds").tag(30)
          }
          Text(
            "Linux metrics are read over SSH without sudo or agents. GPU requires nvidia-smi; containers require Docker access. History contains the last 60 samples and is not synced or uploaded."
          ).font(.footnote).foregroundStyle(.secondary)
        }
        Section("Connection") {
          Toggle("SFTP follows directory reports", isOn: $follow)
          Text(
            "Directory following requires your remote shell to emit OSC 7. iOS suspends applications in the background, so ModernTerm disconnects when backgrounded; reconnect from the session toolbar when you return."
          ).font(.footnote).foregroundStyle(.secondary)
        }
        Section("Mac migration") {
          Button("Import Mac sessions") { store.importPendingMigration() }
          Text(
            store.migrationMessage
              ?? "A private USB migration file can be placed in this app's Documents folder. Existing sessions are preserved; credentials are stored in the iOS Keychain."
          )
          .font(.footnote).foregroundStyle(.secondary)
        }
        Section("About") {
          LabeledContent("Version", value: "0.2.2")
          LabeledContent("Developer", value: "Weiyang Liao / 廖卫阳")
          Text("Native SwiftUI + UIKit · SwiftTerm · Citadel").font(.footnote)
          NavigationLink("What's new") {
            ScrollView {
              Text(
                "0.2.0\n\nMonitoring-first workspace, live CPU/core, memory/swap, disk/IO, network/TCP, uptime/load, NVIDIA GPU, Docker and process panels; recent trends and multi-server overview.\n\n0.1.0\n\nSSH sessions, saved passwords and private keys, host fingerprint verification, native terminal with Tab/control keys, SFTP upload/download and multi-delete, remote UTF-8 editing with conflict checks, Linux server information, terminal palettes and macros.\n\niOS local shell, persistent background connections, SSH tunnels, and automatic session recovery are not included in this initial mobile release."
              ).padding()
            }.navigationTitle("Changelog")
          }
          NavigationLink("Open-source licenses") {
            ScrollView {
              Text(
                (try? String(
                  contentsOf: Bundle.main.url(forResource: "ThirdParty", withExtension: "txt")!))
                  ?? ""
              ).font(.caption).padding()
            }.navigationTitle("Licenses")
          }
        }
      }.navigationTitle("Settings").toolbar { Button("Done") { dismiss() } }
    }
  }
}
struct Macro: Codable, Identifiable {
  var id = UUID()
  var name: String
  var command: String
}
struct MacrosScreen: View {
  let session: SSHSession?
  @Environment(\.dismiss) private var dismiss
  @AppStorage("macros") private var storage = Data()
  @State private var name = ""
  @State private var command = ""
  @State private var pending: Macro?
  var items: [Macro] { (try? JSONDecoder().decode([Macro].self, from: storage)) ?? [] }
  var body: some View {
    NavigationStack {
      Form {
        Section("Saved commands") {
          ForEach(items) { macro in
            Button(macro.name) { pending = macro }.disabled(session?.connected != true)
          }.onDelete { indices in
            var next = items
            next.remove(atOffsets: indices)
            storage = (try? JSONEncoder().encode(next)) ?? Data()
          }
        }
        Section("New macro") {
          TextField("Name", text: $name)
          TextField("Command", text: $command, axis: .vertical).autocorrectionDisabled()
            .textInputAutocapitalization(.never)
          Button("Save") {
            var next = items
            next.append(Macro(name: name, command: command))
            storage = (try? JSONEncoder().encode(next)) ?? Data()
            name = ""
            command = ""
          }.disabled(name.isEmpty || command.isEmpty)
        }
      }.navigationTitle("Macros").toolbar { Button("Done") { dismiss() } }.confirmationDialog(
        "Send this command to the active server?",
        isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
        titleVisibility: .visible
      ) {
        Button("Send") {
          if let pending { session?.send(Data((pending.command + "\n").utf8)) }
          pending = nil
        }
      } message: {
        Text(pending?.command ?? "")
      }
    }
  }

}
