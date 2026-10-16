import Foundation

// One bounded, read-only SSH command. No sudo, package installation, or background agent.
enum MetricsCollector {
  static let script = #"""
    export LC_ALL=C
    printf '__MT_META__\n'; uname -s; hostname; uname -r; uname -m
    if [ "$(uname -s)" != Linux ]; then exit 0; fi
    printf '__MT_OS__\n'; sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null | head -1
    printf '__MT_UPTIME__\n'; cat /proc/uptime
    printf '__MT_LOAD__\n'; cat /proc/loadavg
    printf '__MT_CPU__\n'; sed -n '/^cpu[ 0-9]/p' /proc/stat | head -513
    printf '__MT_MODEL__\n'; sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo | head -1
    printf '__MT_MEMORY__\n'; cat /proc/meminfo
    printf '__MT_NETWORK__\n'; cat /proc/net/dev
    printf '__MT_SOCKETS__\n'; cat /proc/net/sockstat
    printf '__MT_DISKS__\n'; df -lPk -x tmpfs -x devtmpfs 2>/dev/null | head -33
    printf '__MT_IO__\n'; cat /proc/diskstats | head -256
    printf '__MT_TEMPERATURE__\n'
    for zone in /sys/class/thermal/thermal_zone*; do
      [ -r "$zone/temp" ] && printf '%s\t%s\n' "$(cat "$zone/type" 2>/dev/null)" "$(cat "$zone/temp" 2>/dev/null)"
    done
    printf '__MT_PROCESSES__\n'; ps -eo pid=,pcpu=,pmem=,comm= --sort=-pcpu 2>/dev/null | head -12
    printf '__MT_GPU__\n'
    if command -v timeout >/dev/null 2>&1 && command -v nvidia-smi >/dev/null 2>&1; then
      timeout 3 nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null || printf 'unavailable\n'
    else printf 'unavailable\n'; fi
    printf '__MT_DOCKER__\n'
    if command -v timeout >/dev/null 2>&1 && command -v docker >/dev/null 2>&1; then
      timeout 3 docker stats --no-stream --format '{{json .}}' 2>/dev/null | head -32
    else printf 'unavailable\n'; fi
    """#
  static var command: String {
    // Linux coreutils timeout bounds a stalled filesystem or optional command.
    "if command -v timeout >/dev/null 2>&1; then timeout 9 sh -c \(shellQuote(script)); else sh -c \(shellQuote(script)); fi"
  }
}
struct CPUCounter {
  let busy: Double
  let total: Double
}
struct NetworkCounter {
  let received: Double
  let sent: Double
}
struct IOCounter {
  let reads: Double
  let writes: Double
  let readBytes: Double
  let writeBytes: Double
}
struct CoreUsage: Identifiable {
  let id: String
  let percent: Double?
}
struct NetworkUsage: Identifiable {
  let id: String
  let received: Double
  let sent: Double
  let receiveRate: Double?
  let sendRate: Double?
}
struct DiskUsage: Identifiable {
  var id: String { device + mount }
  let device: String
  let mount: String
  let total: Double
  let used: Double
  let available: Double
  var percent: Double { total > 0 ? min(100, max(0, used / total * 100)) : 0 }
}
struct DiskIO: Identifiable {
  let id: String
  let readRate: Double?
  let writeRate: Double?
  let operations: Double?
}
struct GPUUsage: Identifiable {
  let id: Int
  let name: String
  let percent: Double?
  let used: Double?
  let total: Double?
  let temperature: Double?
}
struct ProcessUsage: Identifiable {
  let id: Int
  let cpu: Double
  let memory: Double
  let name: String
}
struct ThermalReading: Identifiable {
  let id: String
  let celsius: Double
}
struct ContainerUsage: Identifiable, Decodable {
  let id: String
  let name: String
  let cpu: String
  let memory: String
  let network: String
  let block: String
  enum CodingKeys: String, CodingKey {
    case id = "ID"
    case name = "Name"
    case cpu = "CPUPerc"
    case memory = "MemUsage"
    case network = "NetIO"
    case block = "BlockIO"
  }
}
struct MetricPoint: Identifiable {
  let id = UUID()
  let date: Date
  let cpu: Double?
  let memory: Double?
  let receive: Double?
  let send: Double?
}
struct ServerSnapshot {
  let date: Date
  var supported = false
  var host = "", os = "", kernel = "", architecture = "", cpuModel = ""
  var uptime: Double?
  var load: [Double] = []
  var cpus: [String: CPUCounter] = [:]
  var cpuPercent: Double?
  var cores: [CoreUsage] = []
  var memoryTotal: Double?, memoryUsed: Double?, memoryAvailable: Double?, swapTotal: Double?,
    swapUsed: Double?
  var networks: [NetworkUsage] = []
  var networkCounters: [String: NetworkCounter] = [:]
  var disks: [DiskUsage] = []
  var ioCounters: [String: IOCounter] = [:]
  var io: [DiskIO] = []
  var gpus: [GPUUsage] = []
  var containers: [ContainerUsage] = []
  var processes: [ProcessUsage] = []
  var temperatures: [ThermalReading] = []
  var tcpInUse: Int?, tcpTimeWait: Int?
  var memoryPercent: Double? {
    guard let memoryUsed, let memoryTotal, memoryTotal > 0 else { return nil }
    return memoryUsed / memoryTotal * 100
  }
  var receiveRate: Double? { sumRates(networks.map(\.receiveRate)) }
  var sendRate: Double? { sumRates(networks.map(\.sendRate)) }
  private func sumRates(_ values: [Double?]) -> Double? {
    let available = values.compactMap { $0 }
    return available.isEmpty ? nil : available.reduce(0, +)
  }
}

enum MetricsParser {
  static func number(_ value: Substring) -> Double? {
    guard let n = Double(value), n.isFinite, n >= 0 else { return nil }
    return n
  }
  static func parse(_ text: String, previous: ServerSnapshot? = nil, date: Date = Date())
    -> ServerSnapshot
  {
    var sections: [String: [String]] = [:]
    var section = ""
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      if line.hasPrefix("__MT_"), line.hasSuffix("__") {
        section = String(line.dropFirst(5).dropLast(2))
        continue
      }
      sections[section, default: []].append(String(line))
    }
    var result = ServerSnapshot(date: date)
    let meta = sections["META"] ?? []
    guard meta.count >= 4 else { return result }
    result.supported = meta[0] == "Linux"
    result.host = meta[1]
    result.kernel = meta[2]
    result.architecture = meta[3]
    result.os = (sections["OS"]?.first ?? meta[0]).trimmingCharacters(
      in: CharacterSet(charactersIn: "\""))
    guard result.supported else { return result }
    result.cpuModel = sections["MODEL"]?.first ?? ""
    result.uptime = sections["UPTIME"]?.first?.split(separator: " ").first.flatMap(number)
    result.load = sections["LOAD"]?.first?.split(separator: " ").prefix(3).compactMap(number) ?? []
    var old = previous
    if old?.host != result.host || old?.kernel != result.kernel
      || (result.uptime ?? 0) < (old?.uptime ?? 0)
    {
      old = nil
    }
    let elapsed: Double? = {
      guard let now = result.uptime, let before = old?.uptime, now > before else { return nil }
      return now - before
    }()
    for line in sections["CPU"] ?? [] {
      let parts = line.split(whereSeparator: { $0.isWhitespace })
      guard let name = parts.first, parts.count >= 5 else { continue }
      let rawTicks = parts.dropFirst().prefix(8)
      let ticks = rawTicks.compactMap(number)
      guard ticks.count >= 4, ticks.count == rawTicks.count else { continue }
      let total = ticks.reduce(0, +)
      let idle = ticks[3] + (ticks.count > 4 ? ticks[4] : 0)
      let counter = CPUCounter(busy: total - idle, total: total)
      result.cpus[String(name)] = counter
      var percent: Double?
      if elapsed != nil, let prior = old?.cpus[String(name)], total > prior.total,
        counter.busy >= prior.busy
      {
        percent = min(100, max(0, (counter.busy - prior.busy) / (total - prior.total) * 100))
      }
      if name == "cpu" {
        result.cpuPercent = percent
      } else {
        result.cores.append(CoreUsage(id: String(name), percent: percent))
      }
    }
    result.cores.sort { (Int($0.id.dropFirst(3)) ?? 0) < (Int($1.id.dropFirst(3)) ?? 0) }
    var memory: [String: Double] = [:]
    for line in sections["MEMORY"] ?? [] {
      let parts = line.split(whereSeparator: { $0.isWhitespace })
      if parts.count >= 2, let value = number(parts[1]) {
        memory[String(parts[0].dropLast())] = value * 1024
      }
    }
    result.memoryTotal = memory["MemTotal"]
    if let total = result.memoryTotal, total > 0 {
      let available =
        memory["MemAvailable"]
        ?? memory["MemFree"].map {
          $0 + (memory["Cached"] ?? 0) + (memory["Buffers"] ?? 0) + (memory["SReclaimable"] ?? 0)
            - (memory["Shmem"] ?? 0)
        }
      if let available {
        result.memoryAvailable = min(total, max(0, available))
        result.memoryUsed = total - result.memoryAvailable!
      }
    }
    result.swapTotal = memory["SwapTotal"]
    if let total = result.swapTotal, let free = memory["SwapFree"] {
      result.swapUsed = max(0, total - free)
    }
    for line in sections["NETWORK"] ?? [] {
      let pair = line.split(separator: ":", maxSplits: 1)
      guard pair.count == 2 else { continue }
      let name = pair[0].trimmingCharacters(in: .whitespaces)
      // Show interface rates rather than summing virtual bridge/loopback traffic twice.
      if name == "lo" || name.hasPrefix("veth") || name.hasPrefix("docker") || name.hasPrefix("br-")
      {
        continue
      }
      let fields = pair[1].split(whereSeparator: { $0.isWhitespace })
      guard fields.count >= 9, let rx = number(fields[0]), let tx = number(fields[8]) else {
        continue
      }
      result.networkCounters[name] = NetworkCounter(received: rx, sent: tx)
      let prior = old?.networkCounters[name]
      result.networks.append(
        NetworkUsage(
          id: name, received: rx, sent: tx, receiveRate: delta(rx, prior?.received, elapsed),
          sendRate: delta(tx, prior?.sent, elapsed)))
    }
    result.networks.sort { $0.id < $1.id }
    for line in sections["DISKS"] ?? [] {
      let f = line.split(maxSplits: 5, whereSeparator: { $0.isWhitespace })
      guard f.count == 6, let total = number(f[1]), let used = number(f[2]),
        let available = number(f[3])
      else { continue }
      result.disks.append(
        DiskUsage(
          device: String(f[0]), mount: String(f[5]), total: total * 1024, used: used * 1024,
          available: available * 1024))
    }
    for line in sections["IO"] ?? [] {
      let f = line.split(whereSeparator: { $0.isWhitespace })
      guard f.count >= 14 else { continue }
      let name = String(f[2])
      if name.hasPrefix("loop") || name.hasPrefix("ram") { continue }
      guard let reads = number(f[3]), let writes = number(f[7]), let readSectors = number(f[5]),
        let writeSectors = number(f[9])
      else { continue }
      let c = IOCounter(
        reads: reads, writes: writes, readBytes: readSectors * 512, writeBytes: writeSectors * 512)
      result.ioCounters[name] = c
      let before = old?.ioCounters[name]
      result.io.append(
        DiskIO(
          id: name, readRate: delta(c.readBytes, before?.readBytes, elapsed),
          writeRate: delta(c.writeBytes, before?.writeBytes, elapsed),
          operations: delta(reads + writes, before.map { $0.reads + $0.writes }, elapsed)))
    }
    for line in sections["SOCKETS"] ?? [] where line.hasPrefix("TCP:") {
      let f = line.split(whereSeparator: { $0.isWhitespace })
      if let i = f.firstIndex(of: "inuse"), i + 1 < f.count { result.tcpInUse = Int(f[i + 1]) }
      if let i = f.firstIndex(of: "tw"), i + 1 < f.count { result.tcpTimeWait = Int(f[i + 1]) }
    }
    for line in sections["GPU"] ?? [] {
      let f = line.split(separator: ",", omittingEmptySubsequences: false).map {
        $0.trimmingCharacters(in: .whitespaces)
      }
      guard f.count == 5, f[0] != "unavailable" else { continue }
      result.gpus.append(
        GPUUsage(
          id: result.gpus.count, name: f[0], percent: number(f[1][...]),
          used: number(f[2][...]).map { $0 * 1024 * 1024 },
          total: number(f[3][...]).map { $0 * 1024 * 1024 },
          temperature: number(f[4][...])))
    }
    for line in sections["DOCKER"] ?? [] {
      if let c = try? JSONDecoder().decode(ContainerUsage.self, from: Data(line.utf8)) {
        result.containers.append(c)
      }
    }
    for line in sections["PROCESSES"] ?? [] {
      let f = line.split(maxSplits: 3, whereSeparator: { $0.isWhitespace })
      guard f.count == 4, let pid = Int(f[0]), let cpu = number(f[1]), let memory = number(f[2])
      else { continue }
      result.processes.append(ProcessUsage(id: pid, cpu: cpu, memory: memory, name: String(f[3])))
    }
    for line in sections["TEMPERATURE"] ?? [] {
      let f = line.split(separator: "\t")
      if f.count == 2, let value = number(f[1]), value < 200000 {
        result.temperatures.append(
          ThermalReading(id: String(f[0]) + "-\(result.temperatures.count)", celsius: value / 1000))
      }
    }
    return result
  }
  static func delta(_ now: Double, _ previous: Double?, _ seconds: Double?) -> Double? {
    guard let previous, let seconds, seconds > 0, now >= previous else { return nil }
    return (now - previous) / seconds
  }
}
