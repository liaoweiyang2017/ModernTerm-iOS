package com.modernterm.android

import org.json.JSONObject

data class CpuCounter(val busy: Double, val total: Double)

data class NetworkUsage(
    val name: String,
    val received: Double,
    val sent: Double,
    val rx: Double?,
    val tx: Double?,
)

data class DiskUsage(
    val device: String,
    val mount: String,
    val total: Double,
    val used: Double,
    val available: Double,
)

data class IoCounter(
    val reads: Double,
    val writes: Double,
    val readBytes: Double,
    val writeBytes: Double,
)

data class IoUsage(
    val name: String,
    val readRate: Double?,
    val writeRate: Double?,
    val operations: Double?,
)

data class GpuUsage(
    val name: String,
    val percent: Double?,
    val used: Double?,
    val total: Double?,
    val temperature: Double?,
)

data class ProcessUsage(val pid: Int, val cpu: Double, val memory: Double, val name: String)

data class ContainerUsage(
    val name: String,
    val cpu: String,
    val memory: String,
    val network: String,
    val block: String,
)

data class Snapshot(
    val host: String = "",
    val os: String = "",
    val kernel: String = "",
    val architecture: String = "",
    val supported: Boolean = false,
    val model: String = "",
    val uptime: Double? = null,
    val load: List<Double> = emptyList(),
    val cpu: Double? = null,
    val cores: List<Pair<String, Double?>> = emptyList(),
    val counters: Map<String, CpuCounter> = emptyMap(),
    val memoryTotal: Double? = null,
    val memoryAvailable: Double? = null,
    val swapTotal: Double? = null,
    val swapUsed: Double? = null,
    val networks: List<NetworkUsage> = emptyList(),
    val disks: List<DiskUsage> = emptyList(),
    val io: List<IoUsage> = emptyList(),
    val ioCounters: Map<String, IoCounter> = emptyMap(),
    val gpus: List<GpuUsage> = emptyList(),
    val containers: List<ContainerUsage> = emptyList(),
    val processes: List<ProcessUsage> = emptyList(),
    val temperatures: List<Pair<String, Double>> = emptyList(),
    val tcpInUse: Int? = null,
    val tcpTimeWait: Int? = null,
) {
    val memoryPercent: Double?
        get() =
            memoryTotal
                ?.takeIf { it > 0 }
                ?.let { total -> memoryAvailable?.let { (total - it) / total * 100 } }

    val receiveRate: Double?
        get() = networks.mapNotNull { it.rx }.takeIf { it.isNotEmpty() }?.sum()

    val sendRate: Double?
        get() = networks.mapNotNull { it.tx }.takeIf { it.isNotEmpty() }?.sum()
}

object Metrics {
    private fun number(s: String) = s.toDoubleOrNull()?.takeIf { it.isFinite() && it >= 0 }

    private fun words(s: String) = s.trim().split(Regex("\\s+"))

    private fun delta(now: Double, old: Double?, elapsed: Double?): Double? =
        if (old != null && elapsed != null && elapsed > 0 && now >= old) (now - old) / elapsed
        else null

    fun parse(text: String, previous: Snapshot? = null): Snapshot {
        require(text.toByteArray().size <= 262144) { "Monitoring response exceeds limit." }
        val sections = linkedMapOf<String, MutableList<String>>()
        var name = ""
        text.lineSequence().forEach { line ->
            if (line.startsWith("__MT_") && line.endsWith("__"))
                name = line.removePrefix("__MT_").removeSuffix("__")
            else sections.getOrPut(name) { mutableListOf() }.add(line)
        }
        fun lines(key: String) = sections[key].orEmpty().filter { it.isNotBlank() }
        fun first(key: String) = lines(key).firstOrNull().orEmpty()
        val meta = lines("META")
        if (meta.size < 4) return Snapshot()
        var result =
            Snapshot(
                host = meta[1],
                os = first("OS").ifBlank { meta[0] }.trim('"'),
                kernel = meta[2],
                architecture = meta[3],
                supported = meta[0] == "Linux",
            )
        if (!result.supported) return result
        val uptime = number(words(first("UPTIME")).first())
        val old =
            previous?.takeIf {
                it.host == result.host &&
                    it.kernel == result.kernel &&
                    uptime != null &&
                    it.uptime != null &&
                    uptime >= it.uptime
            }
        val elapsed =
            uptime?.let { now -> old?.uptime?.let { before -> (now - before).takeIf { it > 0 } } }
        val counters = linkedMapOf<String, CpuCounter>()
        val percentages = linkedMapOf<String, Double?>()
        lines("CPU").take(513).forEach { line ->
            val f = words(line)
            val values = f.drop(1).take(8).mapNotNull(::number)
            if (values.size >= 4 && values.size == f.drop(1).take(8).size) {
                val total = values.sum()
                val busy = total - values[3] - values.getOrElse(4) { 0.0 }
                val c = CpuCounter(busy, total)
                counters[f[0]] = c
                val before = old?.counters?.get(f[0])
                percentages[f[0]] =
                    if (
                        elapsed != null &&
                            before != null &&
                            total > before.total &&
                            busy >= before.busy
                    )
                        ((busy - before.busy) / (total - before.total) * 100).coerceIn(0.0, 100.0)
                    else null
            }
        }
        val memory =
            lines("MEMORY")
                .mapNotNull { line ->
                    val f = words(line)
                    if (f.size >= 2) number(f[1])?.let { f[0].trimEnd(':') to it * 1024 } else null
                }
                .toMap()
        val total = memory["MemTotal"]
        val available =
            (memory["MemAvailable"]
                    ?: memory["MemFree"]?.let {
                        it +
                            (memory["Cached"] ?: 0.0) +
                            (memory["Buffers"] ?: 0.0) +
                            (memory["SReclaimable"] ?: 0.0) - (memory["Shmem"] ?: 0.0)
                    })
                ?.let { if (total != null) it.coerceIn(0.0, total) else it }
        val networks =
            lines("NETWORK")
                .mapNotNull { line ->
                    val split = line.split(':', limit = 2)
                    if (split.size != 2) return@mapNotNull null
                    val n = split[0].trim()
                    if (n == "lo" || listOf("veth", "docker", "br-").any { n.startsWith(it) })
                        return@mapNotNull null
                    val f = words(split[1])
                    if (f.size < 9) return@mapNotNull null
                    val rx = number(f[0]) ?: return@mapNotNull null
                    val tx = number(f[8]) ?: return@mapNotNull null
                    val before = old?.networks?.find { it.name == n }
                    NetworkUsage(
                        n,
                        rx,
                        tx,
                        delta(rx, before?.received, elapsed),
                        delta(tx, before?.sent, elapsed),
                    )
                }
                .sortedBy { it.name }
        val disks =
            lines("DISKS")
                .mapNotNull { line ->
                    val f = line.trim().split(Regex("\\s+"), limit = 6)
                    if (f.size != 6) return@mapNotNull null
                    val t = number(f[1]) ?: return@mapNotNull null
                    val u = number(f[2]) ?: return@mapNotNull null
                    val a = number(f[3]) ?: return@mapNotNull null
                    DiskUsage(f[0], f[5], t * 1024, u * 1024, a * 1024)
                }
                .take(32)
        val ioCounters = linkedMapOf<String, IoCounter>()
        val io = mutableListOf<IoUsage>()
        lines("IO").take(256).forEach { line ->
            val f = words(line)
            if (f.size >= 14 && !f[2].startsWith("loop") && !f[2].startsWith("ram")) {
                val reads = number(f[3])
                val writes = number(f[7])
                val r = number(f[5])
                val w = number(f[9])
                if (reads != null && writes != null && r != null && w != null) {
                    val c = IoCounter(reads, writes, r * 512, w * 512)
                    ioCounters[f[2]] = c
                    val b = old?.ioCounters?.get(f[2])
                    io.add(
                        IoUsage(
                            f[2],
                            delta(c.readBytes, b?.readBytes, elapsed),
                            delta(c.writeBytes, b?.writeBytes, elapsed),
                            delta(reads + writes, b?.let { it.reads + it.writes }, elapsed),
                        )
                    )
                }
            }
        }
        val sockets = words(lines("SOCKETS").find { it.startsWith("TCP:") }.orEmpty())
        fun socketCount(key: String): Int? =
            sockets
                .indexOf(key)
                .takeIf { it >= 0 }
                ?.let { sockets.getOrNull(it + 1)?.toIntOrNull() }
        val gpus =
            lines("GPU").mapNotNull { line ->
                val f = line.split(',').map { it.trim() }
                if (f.size != 5) null
                else
                    GpuUsage(
                        f[0],
                        number(f[1]),
                        number(f[2])?.times(1048576),
                        number(f[3])?.times(1048576),
                        number(f[4]),
                    )
            }
        val containers =
            lines("DOCKER").take(32).mapNotNull { line ->
                runCatching {
                        JSONObject(line).let {
                            ContainerUsage(
                                it.getString("Name"),
                                it.getString("CPUPerc"),
                                it.getString("MemUsage"),
                                it.getString("NetIO"),
                                it.getString("BlockIO"),
                            )
                        }
                    }
                    .getOrNull()
            }
        val processes =
            lines("PROCESSES").take(12).mapNotNull { line ->
                val f = line.trim().split(Regex("\\s+"), limit = 4)
                if (f.size != 4) return@mapNotNull null
                ProcessUsage(
                    f[0].toIntOrNull() ?: return@mapNotNull null,
                    number(f[1]) ?: return@mapNotNull null,
                    number(f[2]) ?: return@mapNotNull null,
                    f[3],
                )
            }
        val temps =
            lines("TEMPERATURE").mapNotNull { line ->
                val f = line.split('\t')
                if (f.size == 2) number(f[1])?.takeIf { it < 200000 }?.let { f[0] to it / 1000 }
                else null
            }
        result =
            result.copy(
                model = first("MODEL"),
                uptime = uptime,
                load = words(first("LOAD")).take(3).mapNotNull(::number),
                cpu = percentages["cpu"],
                cores =
                    percentages
                        .filterKeys { it != "cpu" }
                        .toList()
                        .sortedBy { it.first.removePrefix("cpu").toIntOrNull() ?: 0 },
                counters = counters,
                memoryTotal = total,
                memoryAvailable = available,
                swapTotal = memory["SwapTotal"],
                swapUsed =
                    memory["SwapTotal"]?.let { t ->
                        memory["SwapFree"]?.let { (t - it).coerceAtLeast(0.0) }
                    },
                networks = networks,
                disks = disks,
                io = io,
                ioCounters = ioCounters,
                gpus = gpus,
                containers = containers,
                processes = processes,
                temperatures = temps,
                tcpInUse = socketCount("inuse"),
                tcpTimeWait = socketCount("tw"),
            )
        return result
    }
}
