package com.modernterm.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TermTransferTest {
    private val instrument = InstrumentationRegistry.getInstrumentation()
    private val password = "互通测试-café-🔐-2026"

    private fun fixture() = instrument.context.assets.open("reference.term").use { it.readBytes() }

    private fun rejects(block: () -> Unit) {
        try {
            block()
            fail("Expected rejection")
        } catch (_: IllegalArgumentException) {} catch (_: IllegalStateException) {}
    }

    @Test
    fun referenceUnicodeAndRandomRoundTrip() {
        val start = System.nanoTime()
        val entries = TermArchive.decode(fixture(), password)
        println("TERM_KDF_AND_DECODE_MS=" + (System.nanoTime() - start) / 1_000_000)
        assertEquals(2, entries.size)
        assertEquals("test@ZC-M6", entries[0].server.user)
        assertEquals("Debian", entries[0].server.distribution)
        assertEquals("TEST KEY\nnot-a-real-key\n", entries[0].credentials?.privateKey)
        assertNull(entries[1].credentials)
        val a = TermArchive.encode(entries, password)
        val b = TermArchive.encode(entries, password)
        assertFalse(a.contentEquals(b))
        assertFalse(String(a).contains("ssh.example.invalid"))
        assertEquals(
            entries,
            TermArchive.decode(
                a,
                java.text.Normalizer.normalize(password, java.text.Normalizer.Form.NFD),
            ),
        )
        val values =
            android.content.ContentValues().apply {
                put(android.provider.MediaStore.Downloads.DISPLAY_NAME, "android-export.term")
                put(android.provider.MediaStore.Downloads.MIME_TYPE, "application/octet-stream")
                put(
                    android.provider.MediaStore.Downloads.RELATIVE_PATH,
                    "Download/ModernTerm-tests",
                )
            }
        val resolver = instrument.targetContext.contentResolver
        val uri =
            resolver.insert(android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)!!
        resolver.openOutputStream(uri)!!.use { it.write(a) }
    }

    @Test
    fun rejectsDamageAndPasswords() {
        val data = fixture()
        rejects { TermArchive.decode(data, "wrong-password-123") }
        for (index in listOf(8, 15, 16, 32, 44, 48, data.lastIndex)) {
            val changed = data.clone()
            changed[index] = (changed[index].toInt() xor 1).toByte()
            rejects { TermArchive.decode(changed, password) }
        }
        rejects { TermArchive.decode(data.copyOf(data.size - 1), password) }
        rejects { TermArchive.decode(data + byteArrayOf(0), password) }
        rejects { TermArchive.decode(ByteArray(TermArchive.MAXIMUM + 1), password) }
        rejects { TermArchive.encode(TermArchive.decode(data, password), "short") }
    }

    @Test
    fun importRollbackRecoveryAndConflicts() {
        val context = instrument.targetContext
        val store = LocalStore(context)
        val original = store.servers()
        val entries =
            TermArchive.decode(fixture(), password).map {
                it.copy(server = it.server.copy(id = UUID.randomUUID().toString()))
            }
        try {
            for (stage in listOf("credential", "configuration")) {
                store.transferCheckpoint = { if (it == stage) error("Injected failure") }
                rejects { store.importTerm(entries) }
                assertEquals(original, store.servers())
                assertEquals("", store.credentials(entries[0].server.id).password)
            }
            store.transferCheckpoint = null
            assertEquals(2, store.importTerm(entries))
            rejects { store.importTerm(entries) }
            rejects {
                store.importTerm(
                    (0 until 199).map {
                        TermEntry(Server(host = "capacity.invalid", user = "test"))
                    }
                )
            }
            val changed = entries[0].copy(server = entries[0].server.copy(host = "changed.invalid"))
            assertEquals(
                listOf(2, 1),
                TermArchive.grouped(entries + entries[0] + changed).map { it.size },
            )
            File(context.noBackupFilesDir, "term-import-journal.json")
                .writeText(org.json.JSONArray(entries.map { it.server.id }).toString())
            val recovered = LocalStore(context)
            assertNull(recovered.loadError)
            assertEquals("synthetic-only", recovered.credentials(entries[0].server.id).password)
            assertFalse(File(context.noBackupFilesDir, "term-import-journal.json").exists())
        } finally {
            entries.forEach { store.delete(it.server) }
        }
    }

    @Test
    fun iosExportWhenProvided() {
        val asset = instrument.context.assets.open("ios-export.term").use { it.readBytes() }
        assertEquals(TermArchive.decode(fixture(), password), TermArchive.decode(asset, password))
    }
}
