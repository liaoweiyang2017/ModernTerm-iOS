import Charts
import SwiftUI

private func percent(_ value: Double?) -> String {
  value.map { String(format: "%.1f%%", $0) } ?? "—"
}
private func bytes(_ value: Double?) -> String {
  guard let value, value.isFinite, value >= 0, value < Double(Int64.max) else { return "—" }
  return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary)
}
private func rate(_ value: Double?) -> String { value.map { bytes($0) + "/s" } ?? "—" }
private func uptime(_ value: Double?) -> String {
  guard let value, value.isFinite, value >= 0, value < Double(Int.max) else { return "—" }
  let minutes = Int(value) / 60
  return minutes >= 1440
    ? "\(minutes/1440)d \((minutes%1440)/60)h" : "\(minutes/60)h \(minutes%60)m"
}
private struct MetricTile: View {
  let title: String
  let icon: String
  let value: String
  let detail: String
  let color: Color
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: icon).font(.caption).foregroundStyle(color)
      Text(value).font(.title2.weight(.semibold)).monospacedDigit().minimumScaleFactor(0.65)
        .lineLimit(1)
      Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
      .background(
        Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
  }
}
struct MonitoringScreen: View {
  @ObservedObject var session: SSHSession
  @State private var allCores = false
  @State private var showIO = false
  private let columns = [GridItem(.flexible()), GridItem(.flexible())]
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        header
        if let snapshot = session.snapshot {
          if snapshot.supported {
            summary(snapshot)
            trend
            cpuCores(snapshot)
            memory(snapshot)
            network(snapshot)
            disks(snapshot)
            gpu(snapshot)
            containers(snapshot)
            processes(snapshot)
          } else {
            ContentUnavailableView(
              "Linux metrics unavailable", systemImage: "server.rack",
              description: Text(
                "This server reports \(snapshot.os). SSH and SFTP remain available; detailed monitoring currently requires Linux /proc."
              ))
          }
        } else {
          ContentUnavailableView(
            session.connected ? "Collecting server data…" : "Connect to monitor",
            systemImage: "waveform.path.ecg",
            description: Text(
              "CPU, memory, storage and network data are collected over SSH. No agent or root access is required."
            ))
          if !session.connected {
            Button("Connect", systemImage: "bolt.fill") { session.connect() }.buttonStyle(
              .borderedProminent
            ).frame(maxWidth: .infinity)
          }
        }
      }.padding()
    }.background(Color(uiColor: .systemGroupedBackground))
      .refreshable { await session.refreshMonitoring() }
  }
  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Label(
          session.connected ? "Live SSH monitoring" : "Disconnected",
          systemImage: session.connected ? "checkmark.circle.fill" : "pause.circle.fill"
        )
        .foregroundStyle(session.connected ? Color.green : Color.orange).font(
          .subheadline.weight(.medium))
        Spacer()
        if session.monitoring { ProgressView().controlSize(.small) }
      }
      if let snapshot = session.snapshot {
        Text(snapshot.host).font(.title3.bold())
        Text("\(snapshot.os) · \(snapshot.architecture)").font(.caption).foregroundStyle(.secondary)
        Text("Updated \(snapshot.date,style:.relative) ago").font(.caption2).foregroundStyle(
          .secondary)
        if !session.connected {
          Text("Last snapshot only — reconnect to refresh.").font(.caption).foregroundStyle(.orange)
        }
      }
      if let error = session.monitorError {
        Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(
          .orange)
      }
    }
  }
  private func summary(_ s: ServerSnapshot) -> some View {
    LazyVGrid(columns: columns, spacing: 12) {
      MetricTile(
        title: "CPU", icon: "cpu", value: percent(s.cpuPercent),
        detail:
          "\(s.cores.count) cores · \(s.cpuPercent == nil ? "Waiting for second sample":"Total utilization")",
        color: .green)
      MetricTile(
        title: "Memory", icon: "memorychip", value: percent(s.memoryPercent),
        detail: "\(bytes(s.memoryUsed)) / \(bytes(s.memoryTotal))", color: .purple)
      MetricTile(
        title: "Network", icon: "network", value: "↓ " + rate(s.receiveRate),
        detail: "↑ " + rate(s.sendRate), color: .cyan)
      MetricTile(
        title: "Uptime", icon: "clock", value: uptime(s.uptime),
        detail: "Load " + s.load.map { String(format: "%.2f", $0) }.joined(separator: " / "),
        color: .orange)
    }
  }
  private var trend: some View {
    GroupBox("Recent CPU & memory") {
      if session.history.count < 2 {
        Text("Trends appear after the next sample.").font(.caption).foregroundStyle(.secondary)
          .frame(height: 100)
      } else {
        Chart {
          ForEach(session.history) { point in
            if let value = point.cpu {
              LineMark(x: .value("Time", point.date), y: .value("%", value)).foregroundStyle(
                by: .value("Metric", "CPU"))
            }
            if let value = point.memory {
              LineMark(x: .value("Time", point.date), y: .value("%", value)).foregroundStyle(
                by: .value("Metric", "Memory"))
            }
          }
        }.chartYScale(domain: 0...100).chartForegroundStyleScale([
          "CPU": Color.green, "Memory": Color.purple,
        ]).frame(height: 130)
      }
      Text("Last 60 samples, kept only while this connection is open.").font(.caption2)
        .foregroundStyle(.secondary)
    }
  }
  private func cpuCores(_ s: ServerSnapshot) -> some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 10) {
        Text(s.cpuModel.isEmpty ? "CPU model unavailable" : s.cpuModel).font(.caption)
          .foregroundStyle(.secondary)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 58))], spacing: 8) {
          ForEach(Array(s.cores.prefix(allCores ? 512 : 32))) { core in
            VStack(spacing: 4) {
              Text(core.id).font(.caption2)
              Text(percent(core.percent)).font(.caption.monospacedDigit()).bold()
            }
            .frame(maxWidth: .infinity).padding(7).background(
              Color.green.opacity((core.percent ?? 0) / 500 + 0.06),
              in: RoundedRectangle(cornerRadius: 8))
          }
        }
        if s.cores.count > 32 {
          Button(allCores ? "Show fewer cores" : "Show all \(s.cores.count) cores") {
            allCores.toggle()
          }.font(.caption)
        }
        if !s.temperatures.isEmpty {
          Text(
            s.temperatures.map { String(format: "%@ %.1f°C", $0.id, $0.celsius) }.joined(
              separator: " · ")
          ).font(.caption).foregroundStyle(.secondary)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      Label("CPU cores & temperature", systemImage: "cpu").foregroundStyle(.green)
    }
  }
  private func memory(_ s: ServerSnapshot) -> some View {
    GroupBox {
      VStack(spacing: 10) {
        if let used = s.memoryPercent {
          ProgressView(value: min(100, max(0, used)), total: 100).tint(.purple)
        }
        LabeledContent("Available", value: bytes(s.memoryAvailable))
        LabeledContent("Swap used / total", value: "\(bytes(s.swapUsed)) / \(bytes(s.swapTotal))")
        Text("Used memory excludes MemAvailable, including reclaimable cache.").font(.caption2)
          .foregroundStyle(.secondary)
      }.font(.caption)
    } label: {
      Label("Memory & swap", systemImage: "memorychip").foregroundStyle(.purple)
    }
  }
  private func network(_ s: ServerSnapshot) -> some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        ForEach(s.networks) { nic in
          VStack(alignment: .leading, spacing: 4) {
            Text(nic.id).font(.subheadline.bold())
            HStack {
              Text("↓ " + rate(nic.receiveRate))
              Spacer()
              Text("↑ " + rate(nic.sendRate))
            }.monospacedDigit()
            Text("Total ↓ \(bytes(nic.received)) · ↑ \(bytes(nic.sent))").foregroundStyle(
              .secondary)
          }.font(.caption)
        }
        if s.networks.isEmpty { Text("Network counters unavailable.").font(.caption) }
        if session.history.count > 1 {
          Chart(session.history) { point in
            if let rx = point.receive {
              LineMark(x: .value("Time", point.date), y: .value("B/s", rx)).foregroundStyle(
                by: .value("Direction", "Download"))
            }
            if let tx = point.send {
              LineMark(x: .value("Time", point.date), y: .value("B/s", tx)).foregroundStyle(
                by: .value("Direction", "Upload"))
            }
          }.frame(height: 90).chartXAxis(.hidden)
        }
        Text(
          "TCP sockets: \(s.tcpInUse.map(String.init) ?? "—") · TIME_WAIT: \(s.tcpTimeWait.map(String.init) ?? "—")"
        ).font(.caption)
        Text(
          "Rates use consecutive counters. Loopback, Docker bridges and veth are excluded; other stacked interfaces may overlap."
        ).font(.caption2).foregroundStyle(.secondary)
      }
    } label: {
      Label("Network", systemImage: "network").foregroundStyle(.cyan)
    }
  }
  private func disks(_ s: ServerSnapshot) -> some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        ForEach(s.disks) { disk in
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(disk.mount).bold()
              Spacer()
              Text(percent(disk.percent))
            }
            ProgressView(value: disk.percent, total: 100).tint(disk.percent > 90 ? .orange : .blue)
            Text("\(bytes(disk.used)) / \(bytes(disk.total)) · \(bytes(disk.available)) available")
              .foregroundStyle(.secondary)
          }.font(.caption)
        }
        if s.disks.isEmpty { Text("Local filesystem data unavailable.").font(.caption) }
        DisclosureGroup("Disk I/O by device", isExpanded: $showIO) {
          ForEach(s.io) { disk in
            VStack(alignment: .leading) {
              Text(disk.id).bold()
              Text("Read \(rate(disk.readRate)) · Write \(rate(disk.writeRate))")
              Text("IOPS: \(disk.operations.map{String(format:"%.1f",$0)} ?? "—")")
            }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
          }
          Text("Devices and partitions are listed separately; do not sum them.").font(.caption2)
            .foregroundStyle(.secondary)
        }.font(.caption)
      }
    } label: {
      Label("Storage", systemImage: "internaldrive").foregroundStyle(.blue)
    }
  }
  private func gpu(_ s: ServerSnapshot) -> some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        if s.gpus.isEmpty {
          Text(
            "No NVIDIA data. Requires an existing nvidia-smi command and permission to read GPU status."
          ).font(.caption).foregroundStyle(.secondary)
        }
        ForEach(s.gpus) { gpu in
          VStack(alignment: .leading, spacing: 6) {
            Text(gpu.name).font(.subheadline.bold())
            LabeledContent("Utilization", value: percent(gpu.percent))
            LabeledContent("VRAM", value: "\(bytes(gpu.used)) / \(bytes(gpu.total))")
            LabeledContent(
              "Temperature", value: gpu.temperature.map { String(format: "%.0f°C", $0) } ?? "—")
          }.font(.caption)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      Label("GPU", systemImage: "rectangle.3.group").foregroundStyle(.indigo)
    }
  }
  private func containers(_ s: ServerSnapshot) -> some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        if s.containers.isEmpty {
          Text(
            "No container metrics. Docker may be absent, inaccessible, stopped, or have no running containers. No permissions are changed."
          ).font(.caption).foregroundStyle(.secondary)
        }
        ForEach(s.containers) { container in
          VStack(alignment: .leading, spacing: 4) {
            Text(container.name).font(.subheadline.bold())
            Text("CPU \(container.cpu) · RAM \(container.memory)")
            Text("Network total \(container.network) · Disk total \(container.block)")
              .foregroundStyle(.secondary)
          }.font(.caption)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      Label("Docker · read only", systemImage: "shippingbox").foregroundStyle(.teal)
    }
  }
  private func processes(_ s: ServerSnapshot) -> some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(s.processes) { process in
          HStack {
            VStack(alignment: .leading) {
              Text(process.name).lineLimit(1)
              Text("PID \(process.id)").foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
              Text("CPU " + percent(process.cpu))
              Text("RAM " + percent(process.memory)).foregroundStyle(.secondary)
            }
          }.font(.caption).monospacedDigit()
        }
        Text(
          "Top 12 by ps CPU average over process lifetime, not instantaneous sampling. Command names only; arguments are not collected."
        ).font(.caption2).foregroundStyle(.secondary)
      }
    } label: {
      Label("Processes", systemImage: "list.bullet.rectangle").foregroundStyle(.orange)
    }
  }
}
struct MonitoringSessionRow: View {
  @ObservedObject var session: SSHSession
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Circle().fill(session.connected ? .green : .gray).frame(width: 7, height: 7)
        Text(session.server.name.isEmpty ? session.server.host : session.server.name).font(
          .headline)
      }
      if let sample = session.snapshot {
        HStack {
          Text("CPU " + percent(sample.cpuPercent))
          Text("RAM " + percent(sample.memoryPercent))
          Spacer()
          Text("↓ " + rate(sample.receiveRate))
        }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
      } else {
        Text(session.status).font(.caption).foregroundStyle(.secondary)
      }
    }.padding(.vertical, 5)
  }
}
struct MonitoringOverview: View {
  @EnvironmentObject var store: ServerStore
  @EnvironmentObject var workspace: Workspace
  var open: (Server) -> Void
  var body: some View {
    List {
      Section("Connected workspaces") {
        ForEach(workspace.sessions) { session in
          Button {
            open(session.server)
          } label: {
            MonitoringSessionRow(session: session)
          }.tint(.primary)
        }
        if workspace.sessions.isEmpty {
          Text("Choose a server below to begin monitoring.").foregroundStyle(.secondary)
        }
      }
      Section("Saved servers") {
        ForEach(store.servers.filter { s in !workspace.sessions.contains { $0.server.id == s.id } })
        { server in
          Button {
            open(server)
          } label: {
            Label(server.name.isEmpty ? server.host : server.name, systemImage: "server.rack")
          }.disabled(workspace.sessions.count >= 8)
        }
      }
      Section {
        Text(
          "Up to 8 live connections. Monitoring pauses when the app is backgrounded. No server agents are installed."
        ).font(.caption).foregroundStyle(.secondary)
      }
    }.navigationTitle("Server overview")
  }
}
