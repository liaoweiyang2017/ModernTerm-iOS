package com.modernterm.android

import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class StoreTest {
    @Test
    fun backupOnlyFilesSurviveInterruptedAtomicWrites() {
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        val folder =
            java.io.File(base.cacheDir, "backup-store-${java.util.UUID.randomUUID()}").apply {
                mkdirs()
            }
        val wrapped =
            object : android.content.ContextWrapper(base) {
                override fun getFilesDir() = folder

                override fun getNoBackupFilesDir() =
                    java.io.File(folder, "no-backup").apply { mkdirs() }
            }
        val server = Server(host = "backup.invalid", user = "test")
        val secret = Credentials(password = "synthetic-backup-secret")
        try {
            LocalStore(wrapped).save(server, secret)
            val config = java.io.File(folder, "configuration.json")
            val credential = java.io.File(wrapped.noBackupFilesDir, "credentials/${server.id}.bin")
            assertTrue(config.renameTo(java.io.File(config.path + ".bak")))
            assertTrue(credential.renameTo(java.io.File(credential.path + ".bak")))
            val journal = java.io.File(wrapped.noBackupFilesDir, "term-import-journal.json.bak")
            journal.writeText(JSONArray(listOf(server.id)).toString())
            val recovered = LocalStore(wrapped)
            assertNull(recovered.loadError)
            assertEquals(listOf(server), recovered.servers())
            assertEquals(secret, recovered.credentials(server.id))
            assertFalse(journal.exists())
            recovered.savePreferences(Preferences(appearance = "dark"))
            val reopened = LocalStore(wrapped)
            assertEquals(listOf(server), reopened.servers())
            assertEquals(secret, reopened.credentials(server.id))
        } finally {
            folder.deleteRecursively()
        }
    }

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

    @Test
    fun corruptConfigurationIsPreservedAndCannotBeOverwritten() {
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        val folder =
            java.io.File(base.cacheDir, "invalid-store-${java.util.UUID.randomUUID()}").apply {
                mkdirs()
            }
        val wrapped =
            object : android.content.ContextWrapper(base) {
                override fun getFilesDir() = folder

                override fun getNoBackupFilesDir() =
                    java.io.File(folder, "no-backup").apply { mkdirs() }
            }
        val file = java.io.File(folder, "configuration.json")
        val original = "{\"servers\":[{\"id\":\"not-a-uuid\"}]}"
        file.writeText(original)
        try {
            val store = LocalStore(wrapped)
            assertNotNull(store.loadError)
            try {
                store.savePreferences(Preferences(appearance = "dark"))
                fail("Corrupt data was overwritten")
            } catch (_: IllegalStateException) {}
            assertEquals(original, file.readText())
        } finally {
            folder.deleteRecursively()
        }
    }
}
