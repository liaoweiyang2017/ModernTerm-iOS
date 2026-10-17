package com.modernterm.android

import java.nio.ByteBuffer
import java.security.SecureRandom
import java.text.Normalizer
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec
import org.json.JSONArray
import org.json.JSONObject

data class TermEntry(val server: Server, val credentials: Credentials? = null)

object TermArchive {
    const val MAXIMUM = 16 * 1024 * 1024
    private val prefix = byteArrayOf(77, 84, 69, 82, 77, 0, 13, 10, 0, 1, 1, 1, 0, 9, 39, -64)

    private fun key(password: String, salt: ByteArray): SecretKeySpec {
        val p = Normalizer.normalize(password, Normalizer.Form.NFC)
        require(p.codePointCount(0, p.length) >= 12 && p.toByteArray().size <= 1024) {
            "Use a file password of at least 12 characters (maximum 1024 UTF-8 bytes)."
        }
        val chars = p.toCharArray()
        val spec = PBEKeySpec(chars, salt, 600000, 256)
        try {
            val bytes =
                SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
            return try {
                SecretKeySpec(bytes, "AES")
            } finally {
                bytes.fill(0)
            }
        } finally {
            chars.fill('\u0000')
            spec.clearPassword()
        }
    }

    fun validate(entries: List<TermEntry>) {
        require(entries.isNotEmpty() && entries.size <= 200) {
            "Archive requires 1–200 connections."
        }
        entries.forEach {
            it.server.validate()
            require((it.credentials?.privateKey?.toByteArray()?.size ?: 0) <= 1024 * 1024) {
                "Private key exceeds 1 MiB."
            }
        }
    }

    // Stop reading secrets as soon as the file budget is exhausted.
    fun collect(
        servers: List<Server>,
        includeCredentials: Boolean,
        read: (String) -> Credentials,
    ): List<TermEntry> {
        require(servers.isNotEmpty() && servers.size <= 200) { "Choose 1–200 connections." }
        var size = 64
        val entries = mutableListOf<TermEntry>()
        for (server in servers) {
            val entry = TermEntry(server, if (includeCredentials) read(server.id) else null)
            validate(listOf(entry))
            size += entryJson(entry).toString().toByteArray().size + 1
            require(size <= MAXIMUM - 64) { "Archive exceeds 16 MiB. Select fewer connections." }
            entries.add(entry)
        }
        return entries
    }

    private fun entryJson(entry: TermEntry): JSONObject =
        JSONObject().put("server", entry.server.json()).apply {
            entry.credentials?.let { put("credentials", it.json()) }
        }

    fun encode(entries: List<TermEntry>, password: String): ByteArray {
        validate(entries)
        val plain =
            JSONObject()
                .put("schemaVersion", 1)
                .put(
                    "entries",
                    JSONArray(
                        entries.map {
                            JSONObject().put("server", it.server.json()).apply {
                                it.credentials?.let { c -> put("credentials", c.json()) }
                            }
                        }
                    ),
                )
                .toString()
                .toByteArray()
        require(plain.size <= MAXIMUM - 64) { "Archive exceeds 16 MiB." }
        val random = SecureRandom()
        val salt = ByteArray(16).also(random::nextBytes)
        val nonce = ByteArray(12).also(random::nextBytes)
        val header =
            ByteBuffer.allocate(48).put(prefix).put(salt).put(nonce).putInt(plain.size).array()
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key(password, salt), GCMParameterSpec(128, nonce))
            cipher.updateAAD(header)
            return header + cipher.doFinal(plain)
        } finally {
            plain.fill(0)
        }
    }

    fun decode(bytes: ByteArray, password: String): List<TermEntry> {
        require(bytes.size in 64..MAXIMUM && bytes.copyOfRange(0, 16).contentEquals(prefix)) {
            "Invalid, oversized or unsupported .term file."
        }
        require(ByteBuffer.wrap(bytes, 44, 4).int == bytes.size - 64) {
            "Invalid .term file length."
        }
        val key = key(password, bytes.copyOfRange(16, 32))
        val plain =
            try {
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(
                    Cipher.DECRYPT_MODE,
                    key,
                    GCMParameterSpec(128, bytes.copyOfRange(32, 44)),
                )
                cipher.updateAAD(bytes.copyOfRange(0, 48))
                cipher.doFinal(bytes.copyOfRange(48, bytes.size))
            } catch (_: java.security.GeneralSecurityException) {
                error("Wrong password or damaged file.")
            }
        try {
            val doc = JSONObject(String(plain, Charsets.UTF_8))
            require(doc.getInt("schemaVersion") == 1) { "Unsupported payload version." }
            val a = doc.getJSONArray("entries")
            require(a.length() in 1..200)
            return (0 until a.length())
                .map { i ->
                    val j = a.getJSONObject(i)
                    val s = j.getJSONObject("server")
                    for (field in listOf("id", "name", "host", "user", "group")) require(
                        s.get(field) is String
                    ) {
                        "Invalid connection field."
                    }
                    for (field in listOf("favorite", "keyLogin")) require(s.get(field) is Boolean) {
                        "Invalid connection field."
                    }
                    require(s.getString("host") == s.getString("host").trim()) { "Invalid host." }
                    if (s.has("distribution")) require(s.get("distribution") is String)
                    if (j.has("credentials")) {
                        val c = j.getJSONObject("credentials")
                        for (field in listOf("password", "privateKey", "passphrase")) require(
                            c.get(field) is String
                        ) {
                            "Invalid credentials."
                        }
                    }
                    require(
                        s.has("port") &&
                            s.get("port") is Number &&
                            s.getDouble("port") == s.getInt("port").toDouble()
                    )
                    TermEntry(
                        serverFromJson(s),
                        j.optJSONObject("credentials")?.let(::credentialsFromJson),
                    )
                }
                .also(::validate)
        } catch (_: Exception) {
            error("Invalid or unsupported connection data.")
        } finally {
            plain.fill(0)
        }
    }

    fun grouped(entries: List<TermEntry>): List<List<TermEntry>> =
        entries.groupBy { it.server.id.lowercase() }.values.map { it.distinct() }
}
