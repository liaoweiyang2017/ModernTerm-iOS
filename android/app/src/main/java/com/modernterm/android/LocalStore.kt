package com.modernterm.android

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.File
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONArray
import org.json.JSONObject

fun Server.json(): JSONObject =
    JSONObject()
        .put("id", id)
        .put("name", name)
        .put("host", host)
        .put("port", port)
        .put("user", user)
        .put("group", group)
        .put("favorite", favorite)
        .put("keyLogin", keyLogin)
        .put("distribution", distribution)

fun serverFromJson(j: JSONObject): Server =
    Server(
            id = UUID.fromString(j.getString("id")).toString(),
            name = j.optString("name"),
            host = j.getString("host").trim(),
            port = j.optInt("port", 22),
            user = j.getString("user"),
            group = j.optString("group", "Servers"),
            favorite = j.optBoolean("favorite"),
            keyLogin = j.optBoolean("keyLogin"),
            distribution = j.optString("distribution", "Ubuntu"),
        )
        .also { it.validate() }

fun Credentials.json(): JSONObject =
    JSONObject()
        .put("password", password)
        .put("privateKey", privateKey)
        .put("passphrase", passphrase)

fun credentialsFromJson(j: JSONObject) =
    Credentials(j.optString("password"), j.optString("privateKey"), j.optString("passphrase"))

data class Preferences(
    val appearance: String = "system",
    val palette: String = "ubuntu-neo",
    val fontSize: Int = 13,
    val interval: Int = 10,
    val followDirectory: Boolean = false,
    val dynamicColor: Boolean = true,
)

data class Macro(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val command: String,
)

data class ImportResult(val imported: Int, val skipped: Int)

class LocalStore(private val context: Context) {
    private val config = AtomicFile(File(context.filesDir, "configuration.json"))
    private val secretDir = File(context.noBackupFilesDir, "credentials").apply { mkdirs() }
    private val transferJournal = File(context.noBackupFilesDir, "term-import-journal.json")
    private var root = JSONObject()
    var loadError: String? = null
        private set

    init {
        if (atomicExists(config.baseFile))
            try {
                root = JSONObject(String(config.readFully()))
                servers()
                preferences()
                macros()
            } catch (_: Exception) {
                loadError =
                    "Saved configuration could not be read. It has been preserved; no changes will overwrite it."
            }
        if (loadError == null)
            runCatching { recoverTransfer() }
                .onFailure { loadError = "Import recovery failed; saved files preserved." }
    }

    @Synchronized
    fun servers(): List<Server> {
        val a = root.optJSONArray("servers") ?: JSONArray()
        return (0 until a.length()).map { serverFromJson(a.getJSONObject(it)) }
    }

    @Synchronized
    fun preferences(): Preferences {
        val p = root.optJSONObject("preferences") ?: JSONObject()
        return Preferences(
            p.optString("appearance", "system"),
            p.optString("palette", "ubuntu-neo"),
            p.optInt("fontSize", 13).coerceIn(10, 24),
            p.optInt("interval", 10).takeIf { it in listOf(5, 10, 30) } ?: 10,
            p.optBoolean("followDirectory"),
            p.optBoolean("dynamicColor", true),
        )
    }

    @Synchronized
    fun savePreferences(p: Preferences) {
        mutate {
            it.put(
                "preferences",
                JSONObject()
                    .put("appearance", p.appearance)
                    .put("palette", p.palette)
                    .put("fontSize", p.fontSize)
                    .put("interval", p.interval)
                    .put("followDirectory", p.followDirectory)
                    .put("dynamicColor", p.dynamicColor),
            )
        }
    }

    @Synchronized
    fun macros(): List<Macro> {
        val a = root.optJSONArray("macros") ?: JSONArray()
        return (0 until a.length()).map {
            a.getJSONObject(it).let { j ->
                Macro(j.getString("id"), j.getString("name"), j.getString("command"))
            }
        }
    }

    @Synchronized
    fun saveMacros(values: List<Macro>) {
        mutate {
            it.put(
                "macros",
                JSONArray(
                    values.map { v ->
                        JSONObject().put("id", v.id).put("name", v.name).put("command", v.command)
                    }
                ),
            )
        }
    }

    @Synchronized
    fun pin(endpoint: String): String? =
        root.optJSONObject("pins")?.optString(endpoint)?.takeIf { it.isNotEmpty() }

    @Synchronized
    fun trust(endpoint: String, fingerprint: String) {
        mutate {
            val pins = it.optJSONObject("pins") ?: JSONObject()
            pins.put(endpoint, fingerprint)
            it.put("pins", pins)
        }
    }

    @Synchronized
    fun forgetPin(endpoint: String) {
        mutate { it.optJSONObject("pins")?.remove(endpoint) }
    }

    @Synchronized
    fun save(server: Server, credentials: Credentials) {
        server.validate()
        check(loadError == null) { loadError!! }
        val old =
            secretFile(server.id).takeIf { atomicExists(it) }?.let { AtomicFile(it).readFully() }
        writeCredentials(server.id, credentials)
        try {
            val values = servers().toMutableList()
            val index = values.indexOfFirst { it.id == server.id }
            if (index < 0) values.add(server) else values[index] = server
            mutate { it.put("servers", JSONArray(values.map { s -> s.json() })) }
        } catch (e: Exception) {
            if (old == null) AtomicFile(secretFile(server.id)).delete()
            else atomicWrite(secretFile(server.id), old)
            throw e
        }
    }

    @Synchronized
    fun delete(server: Server) {
        mutate {
            it.put(
                "servers",
                JSONArray(servers().filter { s -> s.id != server.id }.map { s -> s.json() }),
            )
        }
        AtomicFile(secretFile(server.id)).delete()
    }

    private fun secretFile(id: String) = File(secretDir, UUID.fromString(id).toString() + ".bin")

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("modernterm-v1", null) as? SecretKey)?.let {
            return it
        }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                    "modernterm-v1",
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setUnlockedDeviceRequired(true)
                .build()
        )
        return generator.generateKey()
    }

    private fun writeCredentials(id: String, value: Credentials) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD(id.toByteArray())
        atomicWrite(
            secretFile(id),
            cipher.iv + cipher.doFinal(value.json().toString().toByteArray()),
        )
    }

    @Synchronized
    fun credentials(id: String): Credentials {
        val file = secretFile(id)
        if (!atomicExists(file)) return Credentials()
        try {
            val bytes = AtomicFile(file).readFully()
            require(bytes.size >= 28)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
            cipher.updateAAD(id.toByteArray())
            return credentialsFromJson(
                JSONObject(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size))))
            )
        } catch (_: Exception) {
            error(
                "Saved credentials could not be unlocked. Unlock the device or re-enter credentials; existing encrypted data was preserved."
            )
        }
    }

    @Synchronized
    fun importMigration(data: ByteArray): ImportResult {
        check(loadError == null) { loadError!! }
        require(data.size <= 4 * 1024 * 1024) { "Import exceeds 4 MiB." }
        val doc = JSONObject(String(data))
        require(doc.getInt("version") == 1) { "Unsupported migration version." }
        val array = doc.getJSONArray("sessions")
        require(array.length() <= 200) { "Too many sessions." }
        val entries =
            (0 until array.length()).map {
                array.getJSONObject(it).let { j ->
                    serverFromJson(j.getJSONObject("server")) to
                        credentialsFromJson(j.getJSONObject("credentials"))
                }
            }
        require(entries.map { it.first.id }.distinct().size == entries.size) {
            "Duplicate session identifiers."
        }
        require(entries.all { it.second.privateKey.toByteArray().size <= 1024 * 1024 }) {
            "Private key exceeds 1 MiB."
        }
        val existing = servers()
        val additions = entries.filter { e -> existing.none { it.id == e.first.id } }
        try {
            additions.forEach { writeCredentials(it.first.id, it.second) }
            mutate {
                it.put(
                    "servers",
                    JSONArray((existing + additions.map { e -> e.first }).map { s -> s.json() }),
                )
            }
        } catch (e: Exception) {
            additions.forEach { AtomicFile(secretFile(it.first.id)).delete() }
            throw e
        }
        return ImportResult(additions.size, entries.size - additions.size)
    }

    internal var transferCheckpoint: ((String) -> Unit)? = null

    private fun recoverTransfer() {
        if (!atomicExists(transferJournal)) return
        require(
            maxOf(transferJournal.length(), File(transferJournal.path + ".bak").length()) <= 10000
        )
        val ids = JSONArray(AtomicFile(transferJournal).readFully().toString(Charsets.UTF_8))
        require(ids.length() <= 200)
        val committed = servers().map { it.id }.toSet()
        for (i in 0 until ids.length()) {
            val id = UUID.fromString(ids.getString(i)).toString()
            if (id !in committed) {
                val f = secretFile(id)
                AtomicFile(f).delete()
                check(!atomicExists(f) && !File(f.path + ".new").exists()) {
                    "Could not recover credentials."
                }
            }
        }
        AtomicFile(transferJournal).delete()
        check(!atomicExists(transferJournal)) { "Could not clean import journal." }
    }

    @Synchronized
    fun importTerm(entries: List<TermEntry>): Int {
        check(loadError == null) { loadError!! }
        TermArchive.validate(entries)
        val existing = servers()
        require(
            entries.map { it.server.id }.distinct().size == entries.size &&
                entries.none { e -> existing.any { it.id == e.server.id } } &&
                existing.size + entries.size <= 200
        ) {
            "Connections changed or capacity exceeded. Reopen the import preview."
        }
        atomicWrite(
            transferJournal,
            JSONArray(entries.map { it.server.id }).toString().toByteArray(),
        )
        try {
            entries.forEach {
                writeCredentials(it.server.id, it.credentials ?: Credentials())
                transferCheckpoint?.invoke("credential")
            }
            transferCheckpoint?.invoke("configuration")
            mutate {
                it.put(
                    "servers",
                    JSONArray((existing + entries.map { e -> e.server }).map { s -> s.json() }),
                )
            }
        } catch (e: Exception) {
            runCatching { recoverTransfer() }
                .onFailure {
                    loadError =
                        "Import recovery failed. Restart to retry; further writes are blocked."
                }
            throw e
        }
        runCatching { recoverTransfer() }
            .onFailure { loadError = "Import saved, but journal cleanup failed. Restart to retry." }
        return entries.size
    }

    private fun mutate(change: (JSONObject) -> Unit) {
        check(loadError == null) { loadError!! }
        val copy = JSONObject(root.toString())
        change(copy)
        atomicWrite(config.baseFile, copy.toString().toByteArray())
        root = copy
    }

    // API29 can leave only .bak after interruption; let AtomicFile restore it.
    private fun atomicExists(file: File) = file.exists() || File(file.path + ".bak").exists()

    private fun atomicWrite(file: File, bytes: ByteArray) {
        val atomic = AtomicFile(file)
        val stream = atomic.startWrite()
        try {
            stream.write(bytes)
            atomic.finishWrite(stream)
        } catch (e: Exception) {
            atomic.failWrite(stream)
            throw e
        }
    }
}
