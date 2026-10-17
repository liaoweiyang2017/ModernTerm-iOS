package com.modernterm.android

import org.junit.Assert.*
import org.junit.Test

class ModelTest {
    @Test
    fun usernameAndEndpointRemainSeparate() {
        val server =
            Server(host = "ssh.region-1.example.com", user = "test-account@ZONE-M6", port = 2222)
        server.validate()
        assertEquals("test-account@ZONE-M6", server.user)
        assertEquals("[ssh.region-1.example.com]:2222", server.endpoint)
    }

    @Test
    fun invalidInputsFailBeforeNetwork() {
        for (s in
            listOf(
                Server(),
                Server(host = "https://example.com", user = "u"),
                Server(host = "host", user = "u", port = 0),
            )) {
            try {
                s.validate()
                fail("invalid input accepted")
            } catch (_: IllegalArgumentException) {}
        }
    }

    @Test
    fun remoteFileNamesAndShellArgumentsAreBounded() {
        assertEquals("'a'\\''b'", shellQuote("a'b"))
        assertEquals("/a b", remotePath("/", "a b"))
        try {
            remotePath("/", "../escape")
            fail()
        } catch (_: IllegalArgumentException) {}
        try {
            ByteArray(5).inputStream().readLimited(4)
            fail()
        } catch (_: IllegalArgumentException) {}
    }
}
