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

    private fun capturePreview() {
        val instrument = InstrumentationRegistry.getInstrumentation()
        val resolver = instrument.targetContext.contentResolver
        val values =
            android.content.ContentValues().apply {
                put(android.provider.MediaStore.Images.Media.DISPLAY_NAME, "term-preview.png")
                put(android.provider.MediaStore.Images.Media.MIME_TYPE, "image/png")
                put(
                    android.provider.MediaStore.Images.Media.RELATIVE_PATH,
                    "Pictures/ModernTerm-tests",
                )
            }
        val uri =
            resolver.insert(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)!!
        instrument.uiAutomation.takeScreenshot()?.let { screenshot ->
            resolver.openOutputStream(uri)!!.use {
                screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
            }
        }
    }

    @Test
    fun shortPasswordHasVisibleErrorAndRetainsInput() {
        val server = Server(host = "validation.invalid", user = "test")
        compose.activityRule.scenario.onActivity { a ->
            a.workspace.store.save(server, Credentials())
            a.workspace.reload()
        }
        try {
            compose.onNodeWithContentDescription("SSH transfer").performClick()
            compose.onNodeWithText("Select all").performClick()
            compose
                .onNodeWithText("File password (12+ characters)")
                .performScrollTo()
                .performTextInput("12345678")
            compose
                .onNodeWithText("Repeat file password")
                .performScrollTo()
                .performTextInput("12345678")
            compose.onNodeWithText("Export 1 connections").performScrollTo().performClick()
            compose.waitUntil(5000) {
                compose.onAllNodesWithText("Export failed").fetchSemanticsNodes().isNotEmpty()
            }
            compose
                .onNodeWithText(
                    "Use a file password of at least 12 characters (maximum 1024 UTF-8 bytes)."
                )
                .assertIsDisplayed()
            compose.onNodeWithText("OK").performClick()
            compose.onNodeWithText("Export 1 connections").assertIsEnabled()
        } finally {
            compose.activityRule.scenario.onActivity { a ->
                a.workspace.store.delete(server)
                a.workspace.reload()
            }
        }
    }

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
            // The picker result is stubbed: use the same accessibility action to avoid
            // a touch landing during the native Dialog entrance animation.
            compose.onNodeWithText("Choose .term files…").performScrollTo().performSemanticsAction(
                androidx.compose.ui.semantics.SemanticsActions.OnClick
            ) {
                it()
            }
            repeat(2) {
                compose.waitUntil(30000) {
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
            compose.onNodeWithText("Unlock file 3 of 0").assertDoesNotExist()
            capturePreview()
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
            Intents.intending(hasAction(Intent.ACTION_CHOOSER))
                .respondWith(ActivityResult(Activity.RESULT_CANCELED, null))
            compose
                .onNodeWithText("File password (12+ characters)")
                .performScrollTo()
                .performTextInput(password)
            compose
                .onNodeWithText("Repeat file password")
                .performScrollTo()
                .performTextInput(password)
            compose.onNodeWithText("Share 2 connections").performScrollTo().performClick()
            compose.waitUntil(30000) {
                Intents.getIntents().any { it.action == Intent.ACTION_CHOOSER }
            }
            val share = Intents.getIntents().last { it.action == Intent.ACTION_CHOOSER }
            @Suppress("DEPRECATION")
            val send = share.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)!!
            @Suppress("DEPRECATION")
            val sharedUri = send.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM)!!
            val shared = context.contentResolver.openInputStream(sharedUri)!!.use { it.readBytes() }
            assertEquals(exported, TermArchive.decode(shared, password))
            assertFalse(send.hasExtra(Intent.EXTRA_TEXT))
            compose.onNodeWithText("Done").performClick()
            assertTrue(compose.activity.workspace.sessions.isEmpty())
        } catch (e: Throwable) {
            compose
                .onAllNodes(isRoot(), useUnmergedTree = true)
                .onLast()
                .printToLog("TERM_UI_FAILURE")
            val texts =
                compose
                    .onAllNodes(
                        SemanticsMatcher.keyIsDefined(
                            androidx.compose.ui.semantics.SemanticsProperties.Text
                        ),
                        useUnmergedTree = true,
                    )
                    .fetchSemanticsNodes()
                    .takeLast(40)
                    .joinToString(" | ") {
                        it.config[androidx.compose.ui.semantics.SemanticsProperties.Text]
                            .joinToString { text -> text.text }
                    }
            throw AssertionError("${e.message}; visible labels: $texts", e)
        } finally {
            Intents.release()
            TermShareFile.cleanup(context, System.currentTimeMillis() + 25 * 60 * 60 * 1000L)
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
