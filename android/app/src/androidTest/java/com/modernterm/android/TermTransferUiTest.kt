package com.modernterm.android

import android.app.Activity
import android.app.Instrumentation.ActivityResult
import android.content.ClipData
import android.content.Intent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.core.content.FileProvider
import androidx.test.espresso.intent.Intents
import androidx.test.espresso.intent.matcher.IntentMatchers.hasAction
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class TermTransferUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test
    fun batchImportPreviewAndEncryptedConfigurationExport() {
        val instrument = InstrumentationRegistry.getInstrumentation()
        val context = instrument.targetContext
        val password = "互通测试-café-🔐-2026"
        val entries =
            TermArchive.decode(
                instrument.context.assets.open("reference.term").use { it.readBytes() },
                password,
            )
        val dir = File(context.cacheDir, "downloads").apply { mkdirs() }
        val input =
            File(dir, "test-input.term").apply {
                writeBytes(instrument.context.assets.open("reference.term").use { it.readBytes() })
            }
        val input2 = File(dir, "test-input2.term").apply { writeBytes(input.readBytes()) }
        val output = File(dir, "test-output.term")
        fun uri(file: File) =
            FileProvider.getUriForFile(context, context.packageName + ".files", file)
        val result =
            Intent().apply {
                clipData =
                    ClipData.newRawUri("fixture", uri(input)).apply {
                        addItem(ClipData.Item(uri(input2)))
                    }
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        Intents.init()
        try {
            compose.activityRule.scenario.onActivity { a ->
                entries.forEach { a.workspace.store.delete(it.server) }
                a.workspace.reload()
            }
            Intents.intending(hasAction(Intent.ACTION_OPEN_DOCUMENT))
                .respondWith(ActivityResult(Activity.RESULT_OK, result))
            Intents.intending(hasAction(Intent.ACTION_CREATE_DOCUMENT))
                .respondWith(ActivityResult(Activity.RESULT_OK, Intent().setData(uri(output))))
            compose.onNodeWithContentDescription("SSH transfer").performClick()
            compose.onNodeWithText("Choose .term files…").performScrollTo().performClick()
            repeat(2) {
                compose.waitUntil(5000) {
                    compose
                        .onAllNodesWithText("Unlock file ${it+1} of 2")
                        .fetchSemanticsNodes()
                        .isNotEmpty()
                }
                compose.onNodeWithText("File password").performTextInput(password)
                compose.onNodeWithText("Unlock and continue").performClick()
            }
            compose.waitUntil(10000) {
                compose.onAllNodesWithText("Import preview").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText("Import 2 connections").performScrollTo().performClick()
            compose.waitUntil(5000) {
                compose.activity.workspace.servers.any { it.id == entries[0].server.id }
            }
            compose.onNodeWithText("Select all").performScrollTo().performClick()
            compose
                .onNodeWithText("File password (12+ characters)")
                .performScrollTo()
                .performTextInput(password)
            compose
                .onNodeWithText("Repeat file password")
                .performScrollTo()
                .performTextInput(password)
            compose.onNodeWithText("Export 2 connections").performScrollTo().performClick()
            compose.waitUntil(15000) { output.exists() && output.length() > 64 }
            val exported = TermArchive.decode(output.readBytes(), password)
            assertEquals(2, exported.size)
            assertTrue(exported.all { it.credentials == null })
            compose.onNodeWithText("Done").performClick()
            assertTrue(compose.activity.workspace.sessions.isEmpty())
        } catch (e: Throwable) {
            compose
                .onAllNodes(isRoot(), useUnmergedTree = true)
                .onLast()
                .printToLog("TERM_UI_FAILURE")
            throw e
        } finally {
            Intents.release()
            compose.activityRule.scenario.onActivity { a ->
                entries.forEach { a.workspace.store.delete(it.server) }
                a.workspace.reload()
            }
            input.delete()
            input2.delete()
            output.delete()
        }
    }
}
