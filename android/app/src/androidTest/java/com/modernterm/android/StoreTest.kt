package com.modernterm.android

import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class StoreTest {
    @Test
    fun keystoreRoundtripAndMigrationAreIdempotent() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val store = LocalStore(context)
        val server = Server(host = "test.invalid", user = "test@ZONE-M6")
        val secret =
            Credentials(
                password = "test-only-secret",
                privateKey = "test-only-key",
                passphrase = "test-only-passphrase",
            )
        try {
            store.save(server, secret)
            assertEquals(secret, store.credentials(server.id))
            assertFalse(
                java.io
                    .File(context.filesDir, "configuration.json")
                    .readText()
                    .contains(secret.password)
            )
            val encrypted =
                java.io.File(context.noBackupFilesDir, "credentials/${server.id}.bin").readBytes()
            assertFalse(String(encrypted).contains(secret.password))
            val entry = JSONObject().put("server", server.json()).put("credentials", secret.json())
            val doc =
                JSONObject()
                    .put("version", 1)
                    .put("sessions", JSONArray().put(entry))
                    .toString()
                    .toByteArray()
            assertEquals(ImportResult(0, 1), store.importMigration(doc))
            assertEquals(secret, store.credentials(server.id))
            val duplicate =
                JSONObject()
                    .put("version", 1)
                    .put("sessions", JSONArray().put(entry).put(entry))
                    .toString()
                    .toByteArray()
            try {
                store.importMigration(duplicate)
                fail("Duplicate ID accepted")
            } catch (_: IllegalArgumentException) {}
            assertEquals(secret, LocalStore(context).credentials(server.id))
        } finally {
            store.delete(server)
        }
    }
}
