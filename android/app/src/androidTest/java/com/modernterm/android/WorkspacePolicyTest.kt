package com.modernterm.android

import android.app.Application
import androidx.test.platform.app.InstrumentationRegistry
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WorkspacePolicyTest {
    @Test
    fun sessionLimitAndBackgroundCancellation() {
        val instrument = InstrumentationRegistry.getInstrumentation()
        val vm = Workspace(instrument.targetContext.applicationContext as Application)
        instrument.runOnMainSync {
            repeat(9) {
                vm.open(Server(name = "policy-$it", host = "127.0.0.1", port = 9, user = "test"))
            }
            assertEquals(8, vm.sessions.size)
            assertTrue(vm.message!!.contains("8 sessions"))
            vm.background()
            assertTrue(vm.sessions.all { !it.connected && !it.connecting })
            assertTrue(vm.trust.isEmpty())
            vm.sessions.toList().forEach(vm::close)
        }
    }

    @Test
    fun changedStoredFingerprintIsRejectedWithoutTrustPrompt() {
        val instrument = InstrumentationRegistry.getInstrumentation()
        val context = instrument.targetContext
        val f =
            JSONObject(
                instrument.context.assets.open("ssh-fixture.json").bufferedReader().readText()
            )
        val server =
            Server(host = f.getString("host"), port = f.getInt("port"), user = f.getString("user"))
        val vm = Workspace(context.applicationContext as Application)
        val previous = vm.store.pin(server.endpoint)
        vm.store.save(server, Credentials(password = f.getString("password")))
        vm.store.trust(server.endpoint, "SHA256:intentionally-wrong-test-fingerprint")
        try {
            instrument.runOnMainSync { vm.open(server) }
            val ended = CountDownLatch(1)
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(20)
            while (System.nanoTime() < deadline) {
                var done = false
                instrument.runOnMainSync { done = !vm.sessions.first().connecting }
                if (done) {
                    ended.countDown()
                    break
                }
                Thread.sleep(50)
            }
            assertTrue(ended.await(1, TimeUnit.SECONDS))
            instrument.runOnMainSync {
                assertFalse(vm.sessions.first().connected)
                assertTrue(vm.sessions.first().error!!.contains("fingerprint changed"))
                assertTrue(vm.trust.isEmpty())
            }
        } finally {
            instrument.runOnMainSync { vm.sessions.toList().forEach(vm::close) }
            vm.store.delete(server)
            if (previous == null) vm.store.forgetPin(server.endpoint)
            else vm.store.trust(server.endpoint, previous)
        }
    }

    @Test
    fun reconnectAfterTransportLossDoesNotLoseFirstInput() {
        val instrument = InstrumentationRegistry.getInstrumentation()
        val context = instrument.targetContext
        val f =
            JSONObject(
                instrument.context.assets.open("ssh-fixture.json").bufferedReader().readText()
            )
        val server =
            Server(host = f.getString("host"), port = f.getInt("port"), user = f.getString("user"))
        val vm = Workspace(context.applicationContext as Application)
        vm.store.save(server, Credentials(password = f.getString("password")))
        val previous = vm.store.pin(server.endpoint)
        vm.store.trust(server.endpoint, f.getString("fingerprint"))
        fun awaitCondition(check: () -> Boolean) {
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(15)
            while (System.nanoTime() < deadline) {
                var done = false
                instrument.runOnMainSync { done = check() }
                if (done) return
                Thread.sleep(50)
            }
            fail("Session condition timed out")
        }
        try {
            instrument.runOnMainSync { vm.open(server) }
            awaitCondition { vm.sessions.first().connected }
            instrument.runOnMainSync { vm.shell(vm.sessions.first()) }
            awaitCondition { String(vm.sessions.first().terminalBytes).contains("READY") }
            val s = vm.sessions.first()
            s.connection!!
                .close() // Simulate transport loss, without the explicit Disconnect UI action.
            instrument.runOnMainSync {
                s.connected = false
                vm.connect(s)
            }
            awaitCondition { s.connected }
            instrument.runOnMainSync { vm.shell(s) }
            awaitCondition { String(s.terminalBytes).contains("READY") }
            instrument.runOnMainSync { vm.send(s, "FIRST_RECONNECT_INPUT\n") }
            awaitCondition { String(s.terminalBytes).contains("FIRST_RECONNECT_INPUT") }
        } finally {
            instrument.runOnMainSync { vm.sessions.toList().forEach(vm::close) }
            vm.store.delete(server)
            if (previous == null) vm.store.forgetPin(server.endpoint)
            else vm.store.trust(server.endpoint, previous)
        }
    }
}
