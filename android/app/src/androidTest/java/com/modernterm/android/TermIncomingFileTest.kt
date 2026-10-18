package com.modernterm.android

import android.content.Intent
import android.net.Uri
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.core.content.FileProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class TermIncomingFileTest {
    @get:Rule val compose = createEmptyComposeRule()
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private fun fixture(): File =
        File(context.cacheDir, "downloads/incoming-fixture.term").apply {
            parentFile!!.mkdirs()
            writeBytes(
                InstrumentationRegistry.getInstrumentation()
                    .context
                    .assets
                    .open("reference.term")
                    .use { it.readBytes() }
            )
        }

    private fun uri(file: File) =
        FileProvider.getUriForFile(context, context.packageName + ".files", file)

    @Test
    fun coldSendOpensPasswordAndCancelDoesNotSave() {
        val file = fixture()
        val intent =
            Intent(context, MainActivity::class.java)
                .setAction(Intent.ACTION_SEND)
                .setType("application/octet-stream")
                .putExtra(Intent.EXTRA_STREAM, uri(file))
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        val before = LocalStore(context).servers().size
        ActivityScenario.launch<MainActivity>(intent).use {
            compose.waitUntil(8000) {
                compose.onAllNodesWithText("Unlock and continue").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText("Cancel import").performClick()
            assertEquals(before, LocalStore(context).servers().size)
        }
        file.delete()
    }

    @Test
    fun multipleAttachmentsAndInvalidInputs() {
        val file = fixture()
        try {
            val u = uri(file)
            val second =
                File(file.parentFile, "incoming-second.term").apply { writeBytes(file.readBytes()) }
            try {
                val intent =
                    Intent(Intent.ACTION_SEND_MULTIPLE)
                        .setType("application/octet-stream")
                        .putParcelableArrayListExtra(
                            Intent.EXTRA_STREAM,
                            arrayListOf(u, uri(second)),
                        )
                assertTrue(
                    context.packageManager.queryIntentActivities(intent, 0).any {
                        it.activityInfo.packageName == context.packageName
                    }
                )
                val read = TermIncomingFiles.read(context, TermIncomingFiles.uris(intent))
                assertEquals(2, read.size)
                assertEquals(2, TermArchive.decode(read[0].bytes, "互通测试-café-🔐-2026").size)
                assertThrows(IllegalArgumentException::class.java) {
                    TermIncomingFiles.uris(
                        Intent(Intent.ACTION_VIEW, Uri.parse("https://example.invalid/file.term"))
                    )
                }
                file.writeText("not an archive")
                assertThrows(IllegalArgumentException::class.java) {
                    TermIncomingFiles.read(context, listOf(u))
                }
                file.writeBytes(ByteArray(TermArchive.MAXIMUM + 1))
                assertThrows(IllegalArgumentException::class.java) {
                    TermIncomingFiles.read(context, listOf(u))
                }
                assertThrows(Exception::class.java) {
                    TermIncomingFiles.read(
                        context,
                        listOf(Uri.parse("content://unavailable.invalid/file")),
                    )
                }
                assertThrows(IllegalArgumentException::class.java) {
                    TermIncomingFiles.read(context, List(21) { u })
                }
            } finally {
                second.delete()
            }
        } finally {
            file.delete()
        }
    }
}
