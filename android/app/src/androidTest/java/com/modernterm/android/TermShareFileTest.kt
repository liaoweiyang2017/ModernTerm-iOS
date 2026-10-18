package com.modernterm.android

import android.content.Intent
import android.net.Uri
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.*
import org.junit.Test

class TermShareFileTest {
    @Test
    fun sharesEncryptedFileWithReadOnlyGrantAndDelayedScopedCleanup() {
        val i = InstrumentationRegistry.getInstrumentation()
        val context = i.targetContext
        val bytes = i.context.assets.open("reference.term").use { it.readBytes() }
        val chooser = TermShareFile.chooser(context, bytes)
        assertEquals(Intent.ACTION_CHOOSER, chooser.action)
        @Suppress("DEPRECATION")
        val send = chooser.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)!!
        assertEquals(Intent.ACTION_SEND, send.action)
        assertEquals("application/octet-stream", send.type)
        assertEquals(Intent.FLAG_GRANT_READ_URI_PERMISSION, send.flags)
        assertFalse(send.hasExtra(Intent.EXTRA_TEXT))
        @Suppress("DEPRECATION") val uri = send.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)!!
        assertEquals("content", uri.scheme)
        assertEquals(uri, send.clipData!!.getItemAt(0).uri)
        assertEquals(
            2,
            TermArchive.decode(
                    context.contentResolver.openInputStream(uri)!!.use { it.readBytes() },
                    "互通测试-café-🔐-2026",
                )
                .size,
        )
        TermShareFile.cleanup(context)
        assertArrayEquals(
            bytes,
            context.contentResolver.openInputStream(uri)!!.use { it.readBytes() },
        )
        val unrelated =
            File(context.cacheDir, "downloads/do-not-delete.txt").apply { writeText("fixture") }
        try {
            TermShareFile.cleanup(context, System.currentTimeMillis() + 25 * 60 * 60 * 1000L)
            assertTrue(unrelated.exists())
            assertTrue(File(context.cacheDir, "downloads/term-shares").listFiles().isNullOrEmpty())
        } finally {
            unrelated.delete()
        }
    }
}
