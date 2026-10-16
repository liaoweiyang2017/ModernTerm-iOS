import XCTest

@testable import ModerntermIOS

final class MetricsTests: XCTestCase {
  static func sample(
    uptime: Double = 100, cpu: String = "100 0 100 800 0 0 0 0 900 900", rx: Int = 1000,
    tx: Int = 2000, reads: Int = 10, writes: Int = 30, sectors: Int = 20
  ) -> String {
    """
    __MT_META__
    Linux
    fixture-host
    6.8.0
    aarch64
    __MT_OS__
    "Ubuntu 26.04 LTS"
    __MT_UPTIME__
    \(uptime) 500
    __MT_LOAD__
    1.20 2.30 3.40 1/123 1234
    __MT_CPU__
    cpu \(cpu)
    cpu0 \(cpu)
    __MT_MODEL__
    Test CPU
    __MT_MEMORY__
    MemTotal: 1000000 kB
    MemAvailable: 400000 kB
    MemFree: 200000 kB
    SwapTotal: 100000 kB
    SwapFree: 60000 kB
    __MT_NETWORK__
      eth0: \(rx) 0 0 0 0 0 0 0 \(tx) 0 0 0 0 0 0 0
      lo: 999999 0 0 0 0 0 0 0 999999 0 0 0 0 0 0 0
      veth123: 999999 0 0 0 0 0 0 0 999999 0 0 0 0 0 0 0
    __MT_SOCKETS__
    TCP: inuse 12 orphan 0 tw 4 alloc 15 mem 3
    __MT_DISKS__
    Filesystem 1024-blocks Used Available Capacity Mounted on
    /dev/sda1 1000 600 400 60% /data with space
    __MT_IO__
    8 0 sda \(reads) 0 \(sectors) 0 \(writes) 0 40 0 0 0 0
    __MT_TEMPERATURE__
    cpu_thermal\t42000
    __MT_PROCESSES__
    42 12.5 3.0 python
    __MT_GPU__
    NVIDIA RTX 4090, 20, 1024, 24576, 52
    __MT_DOCKER__
    {"ID":"abc","Name":"worker","CPUPerc":"3.0%","MemUsage":"10MiB / 2GiB","NetIO":"1MB / 2MB","BlockIO":"0B / 0B"}
    """
  }
  func testSnapshotAndMissingFirstRates() {
    let sample = MetricsParser.parse(Self.sample())
    XCTAssertTrue(sample.supported)
    XCTAssertEqual(sample.host, "fixture-host")
    XCTAssertEqual(sample.os, "Ubuntu 26.04 LTS")
    XCTAssertNil(sample.cpuPercent)
    XCTAssertNil(sample.receiveRate)
    XCTAssertEqual(sample.memoryPercent, 60)
    XCTAssertEqual(sample.memoryUsed, 600000 * 1024)
    XCTAssertEqual(sample.swapUsed, 40000 * 1024)
    XCTAssertEqual(sample.networks.count, 1)
    XCTAssertEqual(sample.disks.first?.mount, "/data with space")
    XCTAssertEqual(sample.disks.first?.percent, 60)
    XCTAssertEqual(sample.tcpInUse, 12)
    XCTAssertEqual(sample.tcpTimeWait, 4)
    XCTAssertEqual(sample.gpus.first?.used, 1024 * 1024 * 1024)
    XCTAssertEqual(sample.containers.first?.name, "worker")
    XCTAssertEqual(sample.processes.first?.name, "python")
    XCTAssertEqual(sample.temperatures.first?.celsius, 42)
  }
  func testCounterDeltasExcludeGuestAndUseRemoteElapsedTime() {
    let first = MetricsParser.parse(Self.sample())
    let next = MetricsParser.parse(
      Self.sample(
        uptime: 102, cpu: "150 0 150 900 0 0 0 0 9999 9999", rx: 3000, tx: 4000, reads: 12,
        writes: 34, sectors: 24), previous: first)
    XCTAssertEqual(next.cpuPercent, 50)
    XCTAssertEqual(next.cores.first?.percent, 50)
    XCTAssertEqual(next.receiveRate, 1000)
    XCTAssertEqual(next.sendRate, 1000)
    XCTAssertEqual(next.io.first?.readRate, 1024)
    XCTAssertEqual(next.io.first?.operations, 3)
  }
  func testRebootCounterResetAndUnsupportedHosts() {
    let first = MetricsParser.parse(Self.sample())
    let reboot = MetricsParser.parse(Self.sample(uptime: 1), previous: first)
    XCTAssertNil(reboot.cpuPercent)
    XCTAssertNil(reboot.receiveRate)
    let reset = MetricsParser.parse(Self.sample(uptime: 102, rx: 1), previous: first)
    XCTAssertNil(reset.receiveRate)
    let unchanged = MetricsParser.parse(Self.sample(), previous: first)
    XCTAssertNil(unchanged.cpuPercent)
    XCTAssertNil(unchanged.receiveRate)
    let mac = MetricsParser.parse("__MT_META__\nDarwin\nmac-test\n27.0\narm64\n")
    XCTAssertFalse(mac.supported)
    XCTAssertEqual(mac.host, "mac-test")
    XCTAssertNil(mac.memoryTotal)
  }
  func testMalformedAndOptionalMetrics() {
    XCTAssertFalse(MetricsParser.parse("permission denied").supported)
    let brokenCPU = MetricsParser.parse(Self.sample(cpu: "100 invalid 100 800 0 0 0 0"))
    XCTAssertTrue(brokenCPU.cpus.isEmpty)
    let raw = Self.sample().replacingOccurrences(
      of: "MemAvailable: 400000 kB", with: "MemAvailable: invalid kB"
    )
    .replacingOccurrences(of: "NVIDIA RTX 4090, 20, 1024, 24576, 52", with: "unavailable")
    let sample = MetricsParser.parse(raw)
    XCTAssertTrue(sample.gpus.isEmpty)
    XCTAssertEqual(sample.memoryAvailable, 200000 * 1024)
    XCTAssertNil(MetricsParser.number("NaN"))
    XCTAssertNil(MetricsParser.number("-1"))
    XCTAssertFalse(MetricsCollector.command.contains("sudo"))
    XCTAssertTrue(MetricsCollector.command.contains("timeout 9"))
  }
}
