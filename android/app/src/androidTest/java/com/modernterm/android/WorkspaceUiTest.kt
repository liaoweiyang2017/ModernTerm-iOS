package com.modernterm.android

import android.graphics.Bitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class WorkspaceUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    private fun capture(name: String) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.uiAutomation.takeScreenshot()?.let { image ->
            val context = instrumentation.targetContext
            val values =
                android.content.ContentValues().apply {
                    put(android.provider.MediaStore.Images.Media.DISPLAY_NAME, "$name.png")
                    put(android.provider.MediaStore.Images.Media.MIME_TYPE, "image/png")
                    put(
                        android.provider.MediaStore.Images.Media.RELATIVE_PATH,
                        "Pictures/ModernTerm-tests",
                    )
                    put(android.provider.MediaStore.Images.Media.IS_PENDING, 1)
                }
            val uri =
                context.contentResolver.insert(
                    android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    values,
                )!!
            context.contentResolver.openOutputStream(uri)!!.use {
                image.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
            values.clear()
            values.put(android.provider.MediaStore.Images.Media.IS_PENDING, 0)
            context.contentResolver.update(uri, values, null, null)
        }
    }

    @Test
    fun materialWorkspaceConnectsSwitchesAndSurvivesRotation() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val f =
            JSONObject(
                instrumentation.context.assets.open("ssh-fixture.json").bufferedReader().readText()
            )
        val server =
            Server(
                name = "UI fixture",
                host = f.getString("host"),
                port = f.getInt("port"),
                user = f.getString("user"),
            )
        val saved = CountDownLatch(1)
        compose.activityRule.scenario.onActivity { a ->
            a.workspace.store.trust(server.endpoint, f.getString("fingerprint"))
            a.workspace.save(server, Credentials(password = f.getString("password"))) {
                saved.countDown()
            }
        }
        assertTrue(saved.await(10, TimeUnit.SECONDS))
        try {
            compose.onNodeWithText("UI fixture").performClick()
            compose.waitUntil(20000) {
                compose.activity.workspace.sessions.any {
                    it.server.id == server.id && it.connected
                }
            }
            compose.onNodeWithText("Connected").assertIsDisplayed()
            capture("monitor")
            compose.onNodeWithText("Terminal", useUnmergedTree = true).performClick()
            compose.waitUntil(10000) {
                compose.activity.workspace.sessions.first { it.server.id == server.id }.shellStarted
            }
            compose.onNodeWithText("Keyboard").assertIsDisplayed().performClick()
            capture("terminal-light")
            compose.activityRule.scenario.recreate()
            compose.waitForIdle()
            assertTrue(
                compose.activity.workspace.sessions.first { it.server.id == server.id }.connected
            )
            compose.onNodeWithText("SFTP", useUnmergedTree = true).performClick()
            compose.waitUntil(10000) {
                val s = compose.activity.workspace.sessions.first { it.server.id == server.id }
                !s.fileBusy && s.path.startsWith("/")
            }
            capture("sftp")
            compose.onNodeWithContentDescription("Back to servers").performClick()
            compose.onNodeWithText("Settings", useUnmergedTree = true).performClick()
            compose.onNodeWithText("Make it yours").assertIsDisplayed()
            capture("settings")
            compose.activityRule.scenario.onActivity {
                it.workspace.settings(it.workspace.preferences.copy(appearance = "dark"))
            }
            compose.waitForIdle()
            capture("settings-dark")
        } finally {
            compose.activityRule.scenario.onActivity { a ->
                a.workspace.remove(server)
                a.workspace.settings(Preferences())
            }
        }
    }

    @Test
    fun addServerSheetAndSearchAreAccessible() {
        compose.onNodeWithContentDescription("Add server").performClick()
        compose.onNodeWithText("New server").assertIsDisplayed()
        compose.onNodeWithText("Host name or IP").assertIsDisplayed()
        capture("add-server")
    }
}
