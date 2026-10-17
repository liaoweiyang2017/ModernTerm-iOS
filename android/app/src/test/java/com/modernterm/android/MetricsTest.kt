package com.modernterm.android

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MetricsTest {
    private val fixture =
        JSONObject(
            javaClass.classLoader!!
                .getResourceAsStream("metrics-fixtures.json")!!
                .bufferedReader()
                .readText()
        )

    @Test
    fun sameGoldenValuesAsIosAndRatesUseRemoteTime() {
        val first = Metrics.parse(fixture.getString("initial"))
        assertTrue(first.supported)
        assertNull(first.cpu)
        assertNull(first.receiveRate)
        assertEquals(60.0, first.memoryPercent!!, 0.001)
        assertEquals(600000.0 * 1024, first.memoryTotal!! - first.memoryAvailable!!, 0.001)
        assertEquals(1, first.networks.size)
        assertEquals("/data with space", first.disks.first().mount)
        assertEquals(12, first.tcpInUse)
        assertEquals(4, first.tcpTimeWait)
        assertEquals(42.0, first.temperatures.first().second, 0.001)
        assertEquals("worker", first.containers.first().name)
        assertEquals("python", first.processes.first().name)
        assertEquals(1024.0 * 1024 * 1024, first.gpus.first().used!!, 0.001)
        val next = Metrics.parse(fixture.getString("next"), first)
        assertEquals(50.0, next.cpu!!, 0.001)
        assertEquals(1000.0, next.receiveRate!!, 0.001)
        assertEquals(1024.0, next.io.first().readRate!!, 0.001)
        assertEquals(3.0, next.io.first().operations!!, 0.001)
    }

    @Test
    fun missingMalformedAndRebootDoNotInventRates() {
        val first = Metrics.parse(fixture.getString("initial"))
        assertNull(Metrics.parse(fixture.getString("reboot"), first).cpu)
        assertNull(Metrics.parse(fixture.getString("initial"), first).receiveRate)
        val other = Metrics.parse("__MT_META__\nDarwin\nmac\n27\narm64\n")
        assertFalse(other.supported)
        assertNull(other.memoryTotal)
        assertFalse(Metrics.parse("bad").supported)
    }

    @Test
    fun limitsAreEnforced() {
        try {
            Metrics.parse("x".repeat(262145))
            fail()
        } catch (_: IllegalArgumentException) {}
    }
}
