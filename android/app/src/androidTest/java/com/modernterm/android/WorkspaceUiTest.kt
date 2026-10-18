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
        Thread.sleep(500) // Allow Android window/IME transitions to reach the compositor.
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
            if (f.optString("platform") == "linux") {
                compose.waitUntil(15000) {
                    compose.activity.workspace.sessions
                        .first { it.server.id == server.id }
                        .snapshot
                        ?.memoryTotal != null
                }
                assertTrue(
                    compose.activity.workspace.sessions
                        .first { it.server.id == server.id }
                        .snapshot!!
                        .supported
                )
            }
            capture("monitor")
            compose.onNodeWithText("Terminal", useUnmergedTree = true).performClick()
            compose.waitUntil(10000) {
                compose.activity.workspace.sessions.first { it.server.id == server.id }.shellStarted
            }
            compose.waitUntil(10000) {
                compose.activity.workspace.sessions
                    .first { it.server.id == server.id }
                    .terminal
                    ?.isReady == true
            }
            compose
                .onAllNodes(
                    SemanticsMatcher.keyIsDefined(
                        androidx.compose.ui.semantics.SemanticsProperties.HorizontalScrollAxisRange
                    )
                )
                .onLast()
                .performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.ScrollBy) {
                    it(2000f, 0f)
                }
            compose.onNodeWithText("Keyboard").assertIsDisplayed().performClick()
            val screen = java.util.concurrent.atomic.AtomicReference("")
            compose.waitUntil(10000) {
                compose.activity.runOnUiThread {
                    compose.activity.workspace.sessions
                        .first { it.server.id == server.id }
                        .terminal
                        ?.evaluateJavascript(
                            "JSON.stringify({text:term.buffer.active.getLine(0).translateToString(true),second:term.buffer.active.getLine(1).translateToString(true),height:document.body.clientHeight,cols:term.cols,rows:term.rows})"
                        ) {
                            screen.set(it)
                        }
                }
                screen.get().contains("READY")
            }
            val render = JSONObject(org.json.JSONArray("[${screen.get()}]").getString(0))
            assertTrue(
                "Terminal viewport collapsed after IME opened: $render; native height=${compose.activity.workspace.sessions.first { it.server.id == server.id }.terminal?.height}",
                render.getInt("height") > 80,
            )
            assertTrue(render.getInt("rows") >= 3)
            assertEquals(
                "Buffered server output must appear exactly once",
                "",
                render.getString("second"),
            )
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

    @Test
    fun linuxDashboardSupportsLandscape() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val fixtures =
            JSONObject(
                instrumentation.context.assets
                    .open("metrics-fixtures.json")
                    .bufferedReader()
                    .readText()
            )
        val state =
            ConnectionState(
                Server(
                    name = "UI fixture · simulated metrics",
                    host = "fixture.invalid",
                    user = "test",
                )
            )
        state.connected = true
        state.snapshot =
            Metrics.parse(fixtures.getString("next"), Metrics.parse(fixtures.getString("initial")))
        state.history = listOf(Metrics.parse(fixtures.getString("initial")), state.snapshot!!)
        compose.activityRule.scenario.onActivity { a ->
            a.workspace.sessions.add(state)
            a.workspace.selected = state.server.id
        }
        compose.onNodeWithText("fixture-host").assertIsDisplayed()
        capture("linux-monitor-fixture")
        // Android 16 ignores app-requested orientation on large screens. Rotate the
        // disposable emulator display instead, as a user would rotate the device.
        val resolver = instrumentation.targetContext.contentResolver
        val previousAuto =
            android.provider.Settings.System.getInt(resolver, "accelerometer_rotation", 1)
        val previousRotation = android.provider.Settings.System.getInt(resolver, "user_rotation", 0)
        fun shell(command: String) {
            android.os.ParcelFileDescriptor.AutoCloseInputStream(
                    instrumentation.uiAutomation.executeShellCommand(command)
                )
                .use { it.readBytes() }
        }
        try {
            shell("settings put system accelerometer_rotation 0")
            shell("settings put system user_rotation 1")
            compose.waitUntil(10000) {
                compose.activity.resources.configuration.orientation ==
                    android.content.res.Configuration.ORIENTATION_LANDSCAPE
            }
            capture("landscape-monitor-fixture")
        } finally {
            compose.activityRule.scenario.onActivity { a -> a.workspace.close(state) }
            shell("settings put system user_rotation $previousRotation")
            shell("settings put system accelerometer_rotation $previousAuto")
        }
    }
}
