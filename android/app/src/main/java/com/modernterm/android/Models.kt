package com.modernterm.android

import java.util.UUID

data class Server(
    val id: String = UUID.randomUUID().toString(),
    val name: String = "",
    val host: String = "",
    val port: Int = 22,
    val user: String = "",
    val group: String = "Servers",
    val favorite: Boolean = false,
    val keyLogin: Boolean = false,
) {
    val endpoint: String
        get() = "[${host.lowercase()}]:$port"

    val title: String
        get() = name.ifBlank { host }

    fun validate() {
        require(host.isNotBlank() && !host.any { it.isWhitespace() } && !host.contains("://")) {
            "Enter a host name or IP address, without a URL or command."
        }
        require(user.isNotBlank()) { "Username is required." }
        require(port in 1..65535) { "Port must be between 1 and 65535." }
    }
}

data class Credentials(
    val password: String = "",
    val privateKey: String = "",
    val passphrase: String = "",
)

data class RemoteEntry(val name: String, val path: String, val directory: Boolean, val size: Long)

fun shellQuote(value: String): String = "'" + value.replace("'", "'\\''") + "'"

fun remotePath(parent: String, name: String): String {
    require(name.isNotBlank() && name != "." && name != ".." && '/' !in name && '\u0000' !in name) {
        "Invalid file name."
    }
    return parent.trimEnd('/') + "/" + name
}
