#if DEBUG
  import SwiftUI

  // Explicit developer preview only. No credentials, SSH connection or persisted session.
  struct MonitoringPreview: View {
    @StateObject private var session: SSHSession = {
      var server = Server()
      server.name = "Preview server"
      server.host = "example.invalid"
      let session = SSHSession(server: server)
      var sample = ServerSnapshot(date: Date())
      sample.supported = true
      sample.host = "Sample Linux server"
      sample.os = "Ubuntu · simulated data"
      sample.architecture = "arm64"
      sample.cpuModel = "16-core demonstration CPU"
      sample.uptime = 251000
      sample.load = [1.2, 0.9, 0.8]
      sample.cpuPercent = 42
      sample.cores = (0..<16).map { CoreUsage(id: "cpu\($0)", percent: Double(20 + $0 * 3)) }
      sample.memoryTotal = 64 * 1024 * 1024 * 1024
      sample.memoryAvailable = 40 * 1024 * 1024 * 1024
      sample.memoryUsed = 24 * 1024 * 1024 * 1024
      sample.swapTotal = 8 * 1024 * 1024 * 1024
      sample.swapUsed = 0
      sample.networks = [
        NetworkUsage(id: "eth0", received: 28e9, sent: 14e9, receiveRate: 3.2e6, sendRate: 1.1e6)
      ]
      sample.disks = [
        DiskUsage(
          device: "/dev/nvme0n1p1", mount: "/", total: 1e12, used: 4.2e11, available: 5.8e11)
      ]
      sample.io = [DiskIO(id: "nvme0n1", readRate: 8e6, writeRate: 2e6, operations: 84)]
      sample.tcpInUse = 42
      sample.tcpTimeWait = 8
      sample.gpus = [
        GPUUsage(
          id: 0, name: "Example NVIDIA GPU", percent: 35, used: 4e9, total: 24e9, temperature: 54)
      ]
      sample.containers = [
        ContainerUsage(
          id: "demo", name: "demo-worker", cpu: "4.2%", memory: "256 MiB / 4 GiB",
          network: "8 MB / 2 MB", block: "1 MB / 0 MB")
      ]
      sample.processes = [ProcessUsage(id: 123, cpu: 12, memory: 1.2, name: "example-worker")]
      sample.temperatures = [ThermalReading(id: "CPU", celsius: 48)]
      session.snapshot = sample
      var history: [MetricPoint] = []
      for index in 0..<20 {
        let date = Date().addingTimeInterval(Double(index - 20) * 10)
        let cpu = 30.0 + Double(index % 6) * 4.0
        let memory = 35.0 + Double(index % 4)
        let receive = Double(1 + index % 5) * 1_000_000.0
        let send = Double(1 + index % 3) * 400_000.0
        history.append(
          MetricPoint(date: date, cpu: cpu, memory: memory, receive: receive, send: send))
      }
      session.history = history
      return session
    }()
    var body: some View {
      NavigationStack {
        VStack(spacing: 0) {
          Text("PREVIEW · SIMULATED DATA · NO SSH CONNECTION").font(.caption2.bold())
            .foregroundStyle(.orange).padding(8)
          MonitoringScreen(session: session)
        }.navigationTitle("Hardware preview").navigationBarTitleDisplayMode(.inline)
      }
    }
  }
#endif
