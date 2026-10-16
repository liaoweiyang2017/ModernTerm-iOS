import SwiftTerm
import SwiftUI

struct Palette: Codable, Identifiable {
  let id: String
  let name: String
  let background: String
  let foreground: String
  let ansi: [String]
  static let all: [Palette] =
    (try? JSONDecoder().decode(
      [Palette].self,
      from: Data(contentsOf: Bundle.main.url(forResource: "palettes", withExtension: "json")!)))
    ?? []
}
extension UIColor {
  convenience init(hex: String) {
    let n = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
    self.init(
      red: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255,
      blue: CGFloat(n & 255) / 255, alpha: 1)
  }
}
struct TerminalSurface: UIViewRepresentable {
  @ObservedObject var session: SSHSession
  @AppStorage("fontSize") var fontSize = 13.0
  @AppStorage("palette") var palette = "modernterm"
  @Environment(\.colorScheme) private var colorScheme
  func makeCoordinator() -> Coordinator { Coordinator(session) }
  func makeUIView(context: Context) -> TerminalView {
    session.terminal.terminalDelegate = context.coordinator
    return session.terminal
  }
  func updateUIView(_ view: TerminalView, context: Context) {
    let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    if view.font != font { view.font = font }
    let effectivePalette =
      palette == "ubuntu-neo"
      ? (colorScheme == .dark ? "ubuntu-neo-dark" : "ubuntu-neo-light") : palette
    if context.coordinator.palette != effectivePalette {
      if let p = Palette.all.first(where: { $0.id == effectivePalette }) {
        view.nativeBackgroundColor = UIColor(hex: p.background)
        view.nativeForegroundColor = UIColor(hex: p.foreground)
        view.installColors(
          p.ansi.map { hex in
            let n = UInt32(hex.dropFirst(), radix: 16) ?? 0
            return SwiftTerm.Color(
              red: UInt16((n >> 16) & 255) * 257, green: UInt16((n >> 8) & 255) * 257,
              blue: UInt16(n & 255) * 257)
          })
      }
      context.coordinator.palette = effectivePalette
    }
  }
  @MainActor final class Coordinator: NSObject, @preconcurrency TerminalViewDelegate {
    let session: SSHSession
    var palette = ""
    init(_ session: SSHSession) { self.session = session }
    func send(source: TerminalView, data: ArraySlice<UInt8>) { session.send(Data(data)) }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
      session.resize(cols: newCols, rows: newRows)
    }
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
      guard UserDefaults.standard.bool(forKey: "followDirectory"), let directory,
        let url = URL(string: directory), url.scheme == "file", url.host == session.server.host
      else { return }
      Task { try? await session.refresh(url.path) }
    }
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}  // Remote output cannot launch URLs automatically.
    func bell(source: TerminalView) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
  }
}
struct SessionScreen: View {
  @ObservedObject var session: SSHSession
  @State private var page = 0
  @State private var showDisconnect = false
  var body: some View {
    VStack(spacing: 0) {
      Picker("Workspace", selection: $page) {
        Text("Monitor").tag(0)
        Text("Terminal").tag(1)
        Text("SFTP").tag(2)
      }.pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 8)
      Group {
        if page == 0 {
          MonitoringScreen(session: session)
        } else if page == 1 {
          TerminalSurface(session: session)
        } else {
          FilesScreen(session: session).task(id: session.connected) {
            if session.connected {
              do { try await session.prepareFiles() } catch {
                session.error = error.localizedDescription
              }
            }
          }
        }
      }
      if page == 1 {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack {
            ForEach(
              [
                ("Esc", "\u{1b}"), ("Tab", "\t"), ("Ctrl-C", "\u{3}"), ("Ctrl-D", "\u{4}"),
                ("↑", "\u{1b}[A"), ("↓", "\u{1b}[B"), ("←", "\u{1b}[D"), ("→", "\u{1b}[C"),
              ], id: \.0
            ) { label, bytes in
              Button(label) { session.send(Data(bytes.utf8)) }.buttonStyle(.bordered).disabled(
                !session.connected)
            }
          }.padding(8)
        }.background(.bar)
      }
      HStack {
        Circle().fill(session.connected ? .green : .red).frame(width: 7, height: 7)
        Text(session.status).font(.caption)
        Spacer()
        Button("Monitor", systemImage: "cpu") { page = 0 }.font(.caption)
      }.padding(.horizontal).padding(.vertical, 7)
    }
    .navigationTitle(session.server.name.isEmpty ? session.server.host : session.server.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        if session.connected {
          Button("Disconnect", systemImage: "stop.circle") { showDisconnect = true }
        } else {
          Button("Connect", systemImage: "bolt.fill") { session.connect() }
        }
      }
    }
    .confirmationDialog("Disconnect this session?", isPresented: $showDisconnect) {
      Button("Disconnect", role: .destructive) { session.disconnect() }
    }
    .onChange(of: page) { _, value in if value == 1 { session.startShell() } }
    .onChange(of: session.connected) { _, value in if value && page == 1 { session.startShell() } }
    .alert(
      "Connection",
      isPresented: Binding(get: { session.error != nil }, set: { if !$0 { session.error = nil } })
    ) {
      Button("OK") { session.error = nil }
    } message: {
      Text(session.error ?? "")
    }
    .alert(
      "Trust this server?",
      isPresented: Binding(
        get: { session.trust != nil },
        set: {
          if !$0, let pending = session.trust {
            pending.answer(false)
            session.trust = nil
          }
        })
    ) {
      Button("Cancel", role: .cancel) {
        session.trust?.answer(false)
        session.trust = nil
      }
      Button("Trust and connect") {
        session.trust?.answer(true)
        session.trust = nil
      }
    } message: {
      Text(
        "Verify the fingerprint with your server administrator.\n\(session.trust?.host ?? "")\n\(session.trust?.fingerprint ?? "")"
      )
    }
  }
}
