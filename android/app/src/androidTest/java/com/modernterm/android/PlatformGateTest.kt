package com.modernterm.android

import android.view.inputmethod.EditorInfo
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PlatformGateTest {
    private fun fixture(): JSONObject =
        JSONObject(
            InstrumentationRegistry.getInstrumentation()
                .context
                .assets
                .open("ssh-fixture.json")
                .bufferedReader()
                .readText()
        )

    @Test
    fun passwordRsaSha2AtUsernameAndSftp() {
        val f = fixture()
        val server =
            Server(host = f.getString("host"), port = f.getInt("port"), user = f.getString("user"))
        SshConnection().use { c ->
            c.connect(server, Credentials(password = f.getString("password"))) {
                it == f.getString("fingerprint")
            }
            assertTrue(c.connected)
            val stream = c.openShell(80, 24)
            c.send("Android10 中文\n".toByteArray())
            val bytes = ByteArray(256)
            val out = StringBuilder()
            while (!out.contains("Android10 中文")) {
                val n = stream.read(bytes)
                assertTrue(n > 0)
                out.append(String(bytes, 0, n))
            }
            c.resize(100, 30)
            val dir = f.getString("directory")
            val path = "$dir/android-${java.util.UUID.randomUUID()}.txt"
            c.upload("file 中文".byteInputStream(), path)
            assertEquals("file 中文", String(c.read(path)))
            c.save(path, c.read(path), "changed".toByteArray())
            assertEquals("changed", String(c.read(path)))
            try {
                c.save(path, "stale".toByteArray(), "bad".toByteArray())
                fail("conflict must fail")
            } catch (_: IllegalStateException) {}
            c.delete(RemoteEntry("android.txt", path, false, 7))
        }
    }

    @Test
    fun rsaEd25519EncryptedKeysAndHostRejection() {
        val f = fixture()
        val server =
            Server(
                host = f.getString("host"),
                port = f.getInt("port"),
                user = f.getString("user"),
                keyLogin = true,
            )
        for (name in listOf("rsa", "ed25519", "rsa-encrypted", "ed25519-encrypted")) {
            SshConnection().use { c ->
                c.connect(
                    server,
                    Credentials(
                        privateKey = f.getJSONObject("keys").getString(name),
                        passphrase =
                            if (name.endsWith("encrypted")) f.getString("passphrase") else "",
                    ),
                ) {
                    it == f.getString("fingerprint")
                }
                assertTrue(name, c.connected)
            }
        }
        SshConnection().use { c ->
            try {
                c.connect(
                    server.copy(keyLogin = false),
                    Credentials(password = f.getString("password")),
                ) {
                    false
                }
                fail("untrusted key accepted")
            } catch (_: Exception) {}
            assertFalse(c.connected)
        }
        SshConnection().use { c ->
            try {
                c.connect(server.copy(keyLogin = false), Credentials(password = "wrong")) {
                    it == f.getString("fingerprint")
                }
                fail("wrong password accepted")
            } catch (_: Exception) {}
            assertFalse(c.connected)
        }
    }

    @Test
    fun terminalLoadsOfflineAndAcceptsImeComposition() {
        val ready = CountDownLatch(1)
        val input = CountDownLatch(1)
        val received = StringBuilder()
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            var terminal: TerminalPane? = null
            scenario.onActivity { activity ->
                terminal =
                    TerminalPane(
                        activity,
                        {
                            synchronized(received) {
                                received.append(it)
                                if (received.contains("中文")) input.countDown()
                            }
                        },
                        { _, _ -> },
                    )
                activity.setContentView(terminal)
                terminal!!.onReady = {
                    terminal!!.showKeyboard()
                    ready.countDown()
                }
            }
            val loaded = ready.await(20, TimeUnit.SECONDS)
            assertTrue("Offline terminal failed to load: ${terminal?.loadFailure}", loaded)
            Thread.sleep(500)
            scenario.onActivity {
                val connection = terminal!!.onCreateInputConnection(EditorInfo())
                assertNotNull("Native input connection", connection)
                connection!!.setComposingText("中", 1)
                connection.commitText("中文", 1)
                connection.finishComposingText()
            }
            assertTrue(
                "IME text never reached SSH input callback",
                input.await(10, TimeUnit.SECONDS),
            )
            synchronized(received) { assertEquals("中文", received.toString()) }
            scenario.onActivity {
                terminal!!.hideKeyboard()
                terminal!!.showKeyboard()
                assertTrue(terminal!!.hasFocus())
                terminal!!.destroy()
            }
        }
    }

    @Test
    fun refusedSubsystemAndLegacyHostDoNotWeakenSecurity() {
        val f = fixture()
        val base = Server(host = f.getString("host"), port = 22223, user = f.getString("user"))
        SshConnection().use { c ->
            c.connect(base, Credentials(password = f.getString("password"))) {
                it == f.getString("fingerprint")
            }
            val stream = c.openShell(80, 24)
            val start = System.nanoTime()
            try {
                c.list(".")
                fail("Rejected SFTP was accepted")
            } catch (_: Exception) {}
            assertTrue(
                "SFTP rejection should finish within the transport timeout",
                (System.nanoTime() - start) / 1e9 < 20,
            )
            assertTrue(c.connected)
            c.send("STILL_CONNECTED\n".toByteArray())
            val bytes = ByteArray(256)
            val result = StringBuilder()
            while (!result.contains("STILL_CONNECTED")) {
                val n = stream.read(bytes)
                assertTrue(n > 0)
                result.append(String(bytes, 0, n))
            }
        }
        SshConnection().use { c ->
            try {
                c.connect(
                    base.copy(port = 22224),
                    Credentials(password = f.getString("password")),
                ) {
                    true
                }
                fail("SHA-1 host signature fallback was enabled")
            } catch (_: Exception) {}
            assertFalse(c.connected)
        }
    }
}
