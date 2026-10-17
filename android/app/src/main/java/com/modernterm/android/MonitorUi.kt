@file:OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)

package com.modernterm.android

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import java.util.Locale
import kotlin.math.*

fun percent(value: Double?): String = value?.let { String.format(Locale.ROOT, "%.1f%%", it) } ?: "—"

fun bytes(value: Double?): String {
    if (value == null) return "—"
    if (value < 1024) return "${value.toLong()} B"
    val exp = (ln(value) / ln(1024.0)).toInt().coerceIn(1, 4)
    return String.format(
        Locale.ROOT,
        "%.1f %s",
        value / 1024.0.pow(exp),
        listOf("B", "KiB", "MiB", "GiB", "TiB")[exp],
    )
}

private fun rate(v: Double?) = v?.let { bytes(it) + "/s" } ?: "—"

@Composable
private fun MetricCard(
    title: String,
    value: String,
    detail: String,
    modifier: Modifier = Modifier,
) {
    ElevatedCard(modifier) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                title,
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
            Text(value, style = MaterialTheme.typography.headlineMedium)
            Text(detail, style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun MetricSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                title,
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.primary,
            )
            content()
        }
    }
}

@Composable
fun MonitorScreen(s: ConnectionState, modifier: Modifier = Modifier) {
    val data = s.snapshot
    LazyColumn(
        modifier.padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = PaddingValues(vertical = 16.dp),
    ) {
        if (s.monitorError != null)
            item {
                Card(
                    colors =
                        CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.errorContainer
                        )
                ) {
                    Text("Monitoring unavailable: ${s.monitorError}", Modifier.padding(16.dp))
                }
            }
        if (data == null) {
            item {
                MetricSection(
                    if (s.connected) "Collecting first sample" else "Connect to monitor"
                ) {
                    Text(
                        "CPU, memory, storage and network data are read over SSH. No agent or root access is required."
                    )
                }
            }
            return@LazyColumn
        }
        item {
            Text(
                data.host.ifBlank { s.server.title },
                style = MaterialTheme.typography.headlineSmall,
            )
            Text(
                "${data.os} · ${data.architecture}\n${data.kernel}",
                style = MaterialTheme.typography.bodySmall,
            )
        }
        if (!data.supported) {
            item {
                Text(
                    "Linux monitoring is not available on this host. Terminal and SFTP remain available."
                )
            }
            return@LazyColumn
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                MetricCard(
                    "CPU",
                    percent(data.cpu),
                    "${data.cores.size} logical cores",
                    Modifier.weight(1f),
                )
                MetricCard(
                    "Memory",
                    percent(data.memoryPercent),
                    "${bytes(data.memoryTotal?.let{t->data.memoryAvailable?.let{t-it}})} / ${bytes(data.memoryTotal)}",
                    Modifier.weight(1f),
                )
            }
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                MetricCard(
                    "Network ↓",
                    rate(data.receiveRate),
                    "↑ ${rate(data.sendRate)}",
                    Modifier.weight(1f),
                )
                MetricCard(
                    "Uptime",
                    data.uptime?.let { "${(it/86400).toInt()}d ${(it%86400/3600).toInt()}h" }
                        ?: "—",
                    "Load ${data.load.joinToString(" / "){String.format(Locale.ROOT,"%.2f",it)}}",
                    Modifier.weight(1f),
                )
            }
        }
        item {
            MetricSection("Recent CPU and memory") {
                HistoryChart(s.history)
                Text(
                    "Last ${s.history.size} of 60 samples · ${if(data.cpu==null)"rates need two valid samples"else "live session only"}",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
        item {
            MetricSection("CPU details") {
                Text(data.model.ifBlank { "Model unavailable" })
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    data.cores.forEach { (name, value) ->
                        Surface(
                            shape = MaterialTheme.shapes.small,
                            color = MaterialTheme.colorScheme.surfaceContainerHigh,
                        ) {
                            Column(Modifier.padding(8.dp)) {
                                Text(name, style = MaterialTheme.typography.labelSmall)
                                Text(percent(value), style = MaterialTheme.typography.bodySmall)
                            }
                        }
                    }
                }
            }
        }
        item {
            MetricSection("Memory and swap") {
                Text("Available ${bytes(data.memoryAvailable)}")
                Text("Swap ${bytes(data.swapUsed)} / ${bytes(data.swapTotal)}")
            }
        }
        item {
            MetricSection("Local filesystems") {
                if (data.disks.isEmpty()) Text("No filesystem data returned.")
                data.disks.forEach { disk ->
                    Text("${disk.mount} · ${disk.device}")
                    LinearProgressIndicator(
                        progress = {
                            if (disk.total > 0) (disk.used / disk.total).toFloat().coerceIn(0f, 1f)
                            else 0f
                        },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Text(
                        "${bytes(disk.used)} used · ${bytes(disk.available)} available / ${bytes(disk.total)}",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        }
        item {
            MetricSection("Disk I/O") {
                if (data.io.isEmpty()) Text("No disk counters available.")
                data.io.forEach { io ->
                    Text(io.name)
                    Text(
                        "Read ${rate(io.readRate)} · Write ${rate(io.writeRate)} · ${io.operations?.let{String.format(Locale.ROOT,"%.1f IOPS",it)}?:"—"}",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        }
        item {
            MetricSection("Network interfaces") {
                data.networks.forEach { n ->
                    Text(n.name)
                    Text(
                        "↓ ${rate(n.rx)} · ↑ ${rate(n.tx)}\nTotal ${bytes(n.received)} received · ${bytes(n.sent)} sent",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                Text("TCP in use ${data.tcpInUse?:"—"} · TIME_WAIT ${data.tcpTimeWait?:"—"}")
                Text(
                    "Loopback and common container bridges excluded; other overlays may overlap.",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
        item {
            MetricSection("Temperature") {
                if (data.temperatures.isEmpty()) Text("No readable thermal sensors.")
                data.temperatures.forEach { (name, value) ->
                    Text("$name · ${String.format(Locale.ROOT,"%.1f °C",value)}")
                }
            }
        }
        item {
            MetricSection("NVIDIA GPUs") {
                if (data.gpus.isEmpty())
                    Text("Unavailable. Requires nvidia-smi and existing permission.")
                data.gpus.forEach { gpu ->
                    Text(gpu.name)
                    Text(
                        "${percent(gpu.percent)} · VRAM ${bytes(gpu.used)} / ${bytes(gpu.total)} · ${gpu.temperature?.let{"$it °C"}?:"—"}"
                    )
                }
            }
        }
        item {
            MetricSection("Docker · read only") {
                if (data.containers.isEmpty())
                    Text("No accessible container statistics. Permissions are not changed.")
                data.containers.forEach { c ->
                    Text(c.name)
                    Text(
                        "CPU ${c.cpu} · ${c.memory}\nNetwork ${c.network} · Disk ${c.block}",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        }
        item {
            MetricSection("Processes") {
                data.processes.forEach { p ->
                    Row {
                        Column(Modifier.weight(1f)) {
                            Text(p.name)
                            Text("PID ${p.pid}", style = MaterialTheme.typography.bodySmall)
                        }
                        Text(
                            "${percent(p.cpu)} CPU\n${percent(p.memory)} RAM",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
                Text(
                    "Top 12 by lifetime-average CPU; command names only.",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }
}

@Composable
private fun HistoryChart(history: List<Snapshot>) {
    val cpuColor = MaterialTheme.colorScheme.primary
    val memoryColor = MaterialTheme.colorScheme.tertiary
    val grid = MaterialTheme.colorScheme.outlineVariant
    Canvas(
        Modifier.fillMaxWidth().height(140.dp).semantics {
            contentDescription = "CPU and memory history over ${history.size} samples"
        }
    ) {
        for (i in 0..4) drawLine(
            grid,
            androidx.compose.ui.geometry.Offset(0f, size.height * i / 4),
            androidx.compose.ui.geometry.Offset(size.width, size.height * i / 4),
            1f,
        )
        fun line(values: List<Double?>, color: androidx.compose.ui.graphics.Color) {
            if (values.size < 2) return
            val path = Path()
            var active = false
            values.forEachIndexed { i, v ->
                if (v == null) active = false
                else {
                    val x = size.width * i / (values.size - 1)
                    val y = size.height * (1 - v.coerceIn(0.0, 100.0).toFloat() / 100)
                    if (active) path.lineTo(x, y) else path.moveTo(x, y)
                    active = true
                }
            }
            drawPath(path, color, style = Stroke(2.dp.toPx()))
        }
        line(history.map { it.cpu }, cpuColor)
        line(history.map { it.memoryPercent }, memoryColor)
    }
}
