package com.modernterm.android

import org.junit.Assert.*
import org.junit.Test

class TermArchiveTest {
    @Test
    fun exportStopsReadingAtLimitAndConfigurationOnlyNeverReadsSecrets() {
        val servers = (0 until 40).map { Server(host = "limit.invalid", user = "test") }
        val key = "x".repeat(1024 * 1024)
        var reads = 0
        try {
            TermArchive.collect(servers, true) {
                reads++
                Credentials(privateKey = key)
            }
            fail("Expected size limit")
        } catch (_: IllegalArgumentException) {}
        assertTrue(reads in 15..17)
        val entries =
            TermArchive.collect(servers, false) { error("Credential store must not be read") }
        assertEquals(40, entries.size)
        assertTrue(entries.all { it.credentials == null })
    }
}
