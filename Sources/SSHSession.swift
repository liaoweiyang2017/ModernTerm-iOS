import Citadel
import Combine
import Crypto
import Foundation
import NIOCore
import NIOSSH
import SwiftTerm
import UIKit

struct TrustRequest: Identifiable {
  let id = UUID()
  let host: String
  let fingerprint: String
  let answer: (Bool) -> Void
}
final class HostValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
  let host: String
  let decide: @Sendable (String, String, EventLoopPromise<Void>) -> Void
  init(host: String, decide: @escaping @Sendable (String, String, EventLoopPromise<Void>) -> Void) {
    self.host = host
    self.decide = decide
  }
  func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>)
  {
    decide(host, String(openSSHPublicKey: hostKey), validationCompletePromise)
  }
}
struct RemoteFile: Identifiable, Hashable {
  var id: String { name }
  let name: String
  let size: UInt64
  let permissions: UInt32
  var isDirectory: Bool { permissions & 0o170000 == 0o040000 }
  var isRegular: Bool { permissions & 0o170000 == 0o100000 }
}
@MainActor final class SSHSession: ObservableObject, Identifiable {
  let id = UUID()
  let server: Server
  @Published var status = "Disconnected"
  @Published var connected = false
  @Published var error: String?
  @Published var trust: TrustRequest?
  @Published var path = "."
  @Published var files: [RemoteFile] = []
  @Published var busy = false
  @Published var transferProgress: Double = 0
  @Published var snapshot: ServerSnapshot?
  @Published var history: [MetricPoint] = []
  @Published var monitorError: String?
  @Published var monitoring = false
  lazy var terminal: TerminalInputView = {
    let view = TerminalInputView(frame: .zero)
    view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    return view
  }()
  var client: SSHClient?
  var sftp: SFTPClient?
  var writer: TTYStdinWriter?
  private var connectionTask: Task<Void, Never>?
  private var monitorTask: Task<Void, Never>?
  private var shellTask: Task<Void, Never>?
  private var writeTask: Task<Void, Never>?
  private var generation = UUID()
  var cols = 80, rows = 24
  init(server: Server) {
    self.server = server
  }
  func connect(credentials: Credentials? = nil, startTerminal: Bool = false) {
    guard connectionTask == nil, !connected else { return }
    let token = UUID()
    generation = token
    status = "Connecting…"
    error = nil
    snapshot = nil
    history = []
    monitorError = nil
    connectionTask = Task {
      do {
        let creds = try credentials ?? Vault.read(server.id)
        let username = server.user
        let keyLogin = server.keyLogin
        let auth = try await Task.detached {
          if !keyLogin {
            return SSHAuthenticationMethod.passwordBased(
              username: username, password: creds.password)
          }
          let pass = creds.passphrase.isEmpty ? nil : Data(creds.passphrase.utf8)
          if let key = try? Curve25519.Signing.PrivateKey(
            sshEd25519: creds.privateKey, decryptionKey: pass)
          {
            return .ed25519(username: username, privateKey: key)
          }
          if let key = try? Insecure.RSA.PrivateKey(sshRsa: creds.privateKey, decryptionKey: pass) {
            return .rsa(username: username, privateKey: key)
          }
          throw AppError.message(
            "Unsupported key or wrong passphrase. Import an OpenSSH Ed25519 or RSA private key.")
        }.value
        let currentSession = self
        let validator = HostValidator(host: server.endpoint) {
          [weak currentSession] host, key, promise in
          Task { @MainActor in
            guard let self = currentSession, self.generation == token else {
              promise.fail(AppError.message("Connection cancelled."))
              return
            }
            let storage = "hostkey." + host
            if let saved = UserDefaults.standard.string(forKey: storage) {
              if saved == key {
                promise.succeed(())
              } else {
                promise.fail(
                  AppError.message(
                    "Server host key changed. Connection refused; verify the server before removing its saved fingerprint."
                  ))
              }
              return
            }
            let blob =
              key.split(separator: " ").dropFirst().first.flatMap {
                Data(base64Encoded: String($0))
              } ?? Data(key.utf8)
            let fingerprint =
              "SHA256:"
              + Data(SHA256.hash(data: blob)).base64EncodedString().replacingOccurrences(
                of: "=", with: "")
            self.trust = TrustRequest(host: host, fingerprint: fingerprint) { accepted in
              if accepted {
                UserDefaults.standard.set(key, forKey: storage)
                promise.succeed(())
              } else {
                promise.fail(AppError.message("Host fingerprint was not trusted."))
              }
            }
          }
        }
        let ssh = try await SSHClient.connect(
          host: server.host, port: server.port, authenticationMethod: auth,
          hostKeyValidator: .custom(validator), reconnect: .never, connectTimeout: .seconds(20))
        guard generation == token, !Task.isCancelled else {
          try? await ssh.close()
          return
        }
        client = ssh
        connected = true
        status = "Connected"
        ssh.onDisconnect { [weak currentSession] in
          Task { @MainActor in
            guard let self = currentSession, self.generation == token else { return }
            await self.finish()
          }
        }
        startMonitoring()
        connectionTask = nil
        if startTerminal { startShell() }
      } catch {
        if generation == token {
          self.error = error.localizedDescription
          await finish()
        }
      }
    }
  }
  func disconnect() {
    generation = UUID()
    trust?.answer(false)
    trust = nil
    connectionTask?.cancel()
    connectionTask = nil
    monitorTask?.cancel()
    monitorTask = nil
    shellTask?.cancel()
    shellTask = nil
    monitoring = false
    writeTask?.cancel()
    writeTask = nil
    let old = client
    client = nil
    sftp = nil
    writer = nil
    connected = false
    status = "Disconnected"
    Task { try? await old?.close() }
  }
  private func finish() async {
    monitorTask?.cancel()
    monitorTask = nil
    shellTask?.cancel()
    shellTask = nil
    monitoring = false
    writer = nil
    sftp = nil
    connected = false
    status = "Disconnected"
    connectionTask = nil
    let old = client
    client = nil
    try? await old?.close()
  }
  func send(_ data: Data) {
    guard let writer, connected else { return }
    let previous = writeTask
    writeTask = Task {
      await previous?.value
      do {
        try Task.checkCancellation()
        try await writer.write(ByteBuffer(bytes: data))
      } catch { self.error = error.localizedDescription }
    }
  }
  func resize(cols: Int, rows: Int) {
    self.cols = max(1, cols)
    self.rows = max(1, rows)
    guard let writer else { return }
    Task {
      try? await writer.changeSize(cols: self.cols, rows: self.rows, pixelWidth: 0, pixelHeight: 0)
    }
  }
  func refresh(_ directory: String? = nil) async throws {
    if sftp == nil, let client, connected { sftp = try await client.openSFTP() }
    guard let sftp else { throw AppError.message("SFTP is not connected.") }
    let target = try await sftp.getRealPath(atPath: directory ?? path)
    let listing = try await sftp.listDirectory(atPath: target)
    files = listing.flatMap(\.components).filter { $0.filename != "." && $0.filename != ".." }.map {
      RemoteFile(
        name: $0.filename, size: $0.attributes.size ?? 0,
        permissions: $0.attributes.permissions ?? 0)
    }.sorted { a, b in
      a.isDirectory != b.isDirectory
        ? a.isDirectory : a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
    path = target
  }
  func readFile(_ remote: String, limit: Int = 2 * 1024 * 1024) async throws -> Data {
    guard let sftp else { throw AppError.message("SFTP is not connected.") }
    return try await sftp.withFile(filePath: remote, flags: .read) { file in
      var data = Data()
      while true {
        let chunk = try await file.read(from: UInt64(data.count), length: 65536)
        if chunk.readableBytes == 0 { break }
        guard data.count + chunk.readableBytes <= limit else {
          throw AppError.message("File exceeds the editor's 2 MiB limit.")
        }
        data.append(contentsOf: chunk.readableBytesView)
      }
      return data
    }
  }
  func download(_ remote: String, name: String) async throws -> URL {
    guard let sftp else { throw AppError.message("SFTP is not connected.") }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let dest = directory.appendingPathComponent(URL(fileURLWithPath: name).lastPathComponent)
    FileManager.default.createFile(atPath: dest.path, contents: nil)
    let local = try FileHandle(forWritingTo: dest)
    defer { try? local.close() }
    do {
      try await sftp.withFile(filePath: remote, flags: .read) { file in
        var offset: UInt64 = 0
        while true {
          try Task.checkCancellation()
          let chunk = try await file.read(from: offset, length: 131072)
          if chunk.readableBytes == 0 { break }
          try local.write(contentsOf: Data(chunk.readableBytesView))
          offset += UInt64(chunk.readableBytes)
        }
      }
      return dest
    } catch {
      try? FileManager.default.removeItem(at: directory)
      throw error
    }
  }
  func upload(_ local: URL) async throws {
    guard let sftp else { throw AppError.message("SFTP is not connected.") }
    let target = remotePath(path, local.lastPathComponent)
    let temp = remotePath(path, ".modernterm-" + UUID().uuidString)
    let handle = try FileHandle(forReadingFrom: local)
    defer { try? handle.close() }
    do {
      try await sftp.withFile(filePath: temp, flags: [.write, .create, .forceCreate]) { file in
        var offset: UInt64 = 0
        while let chunk = try handle.read(upToCount: 131072), !chunk.isEmpty {
          try Task.checkCancellation()
          try await file.write(ByteBuffer(bytes: chunk), at: offset)
          offset += UInt64(chunk.count)
        }
      }
      // SFTP v3 rename refuses an existing destination; never silently overwrite.
      try await sftp.rename(at: temp, to: target)
      try await refresh()
    } catch {
      try? await sftp.remove(at: temp)
      throw error
    }
  }
  func saveText(_ data: Data, remote: String, baseline: Data) async throws {
    guard let sftp, let client else { throw AppError.message("SFTP is not connected.") }
    guard try await readFile(remote) == baseline else {
      throw AppError.message("Remote file changed. Reopen it before saving.")
    }
    let temp = remote + ".modernterm-" + UUID().uuidString
    let attributes = try await sftp.getAttributes(at: remote)
    do {
      try await sftp.withFile(
        filePath: temp, flags: [.write, .create, .forceCreate], attributes: attributes
      ) { file in try await file.write(ByteBuffer(bytes: data)) }
      guard try await readFile(remote) == baseline else {
        throw AppError.message("Remote file changed while saving.")
      }
      _ = try await client.executeCommand(
        "mv -f -- \(shellQuote(temp)) \(shellQuote(remote))", maxResponseSize: 8192)
    } catch {
      try? await sftp.remove(at: temp)
      throw error
    }
  }
  func delete(_ files: [RemoteFile]) async throws {
    guard let sftp else { throw AppError.message("SFTP is not connected.") }
    let directory = path
    for file in files {
      if file.isDirectory {
        try await sftp.rmdir(at: remotePath(directory, file.name))
      } else {
        try await sftp.remove(at: remotePath(directory, file.name))
      }
    }
    try await refresh()
  }
  func startShell() {
    guard connected, let client, shellTask == nil else { return }
    let token = generation
    shellTask = Task {
      defer {
        if generation == token {
          writer = nil
          shellTask = nil
        }
      }
      do {
        let request = SSHChannelRequestEvent.PseudoTerminalRequest(
          wantReply: true, term: "xterm-256color", terminalCharacterWidth: cols,
          terminalRowHeight: rows, terminalPixelWidth: 0, terminalPixelHeight: 0,
          terminalModes: .init([:]))
        try await client.withPTY(request) { input, output in
          self.writer = output
          for try await chunk in input {
            try Task.checkCancellation()
            guard self.generation == token else { break }
            switch chunk {
            case .stdout(let buffer), .stderr(let buffer):
              self.terminal.feed(byteArray: Array(buffer.readableBytesView)[...])
            }
          }
        }
      } catch {
        if generation == token, !Task.isCancelled { self.error = error.localizedDescription }
      }
    }
  }
  func prepareFiles() async throws {
    guard connected, let client else { throw AppError.message("SSH is not connected.") }
    if sftp == nil { sftp = try await client.openSFTP() }
    try await refresh()
  }
  func refreshMonitoring() async {
    guard connected, let client, !monitoring else { return }
    let token = generation
    monitoring = true
    defer { if generation == token { monitoring = false } }
    do {
      let output = try await client.executeCommand(
        MetricsCollector.command, maxResponseSize: 262144)
      guard connected, generation == token, !Task.isCancelled else { return }
      let value = MetricsParser.parse(String(buffer: output), previous: snapshot)
      guard !value.host.isEmpty else {
        throw AppError.message("Server returned incomplete monitoring data.")
      }
      if let before = snapshot?.uptime, let now = value.uptime, now < before { history.removeAll() }
      snapshot = value
      monitorError = nil
      if value.supported {
        history.append(
          MetricPoint(
            date: value.date, cpu: value.cpuPercent,
            memory: value.memoryPercent, receive: value.receiveRate, send: value.sendRate))
        if history.count > 60 { history.removeFirst(history.count - 60) }
      }
    } catch {
      if generation == token, !Task.isCancelled { monitorError = error.localizedDescription }
    }
  }
  private func startMonitoring() {
    monitorTask?.cancel()
    monitorTask = Task {
      while !Task.isCancelled, connected {
        await refreshMonitoring()
        let preference = UserDefaults.standard.integer(forKey: "monitorInterval")
        let interval = [5, 10, 30].contains(preference) ? preference : 10
        do { try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000) } catch { break }
      }
    }
  }
}
