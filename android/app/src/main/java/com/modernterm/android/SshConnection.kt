package com.modernterm.android

import java.io.Closeable
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.security.PublicKey
import java.security.Security
import java.util.Base64
import java.util.EnumSet
import java.util.concurrent.TimeUnit
import net.schmizz.sshj.DefaultConfig
import net.schmizz.sshj.SSHClient
import net.schmizz.sshj.common.Buffer
import net.schmizz.sshj.common.SecurityUtils
import net.schmizz.sshj.connection.channel.direct.Session
import net.schmizz.sshj.sftp.OpenMode
import net.schmizz.sshj.sftp.SFTPClient
import net.schmizz.sshj.userauth.password.PasswordUtils
import org.bouncycastle.jce.provider.BouncyCastleProvider

class SshConnection : Closeable {
    companion object {
        private var initialized = false

        @Synchronized
        private fun initializeCrypto() {
            if (!initialized) {
                // Android's built-in BC is incomplete. This replacement is local to our process.
                Security.removeProvider("BC")
                Security.addProvider(BouncyCastleProvider())
                SecurityUtils.setSecurityProvider("BC")
                initialized = true
            }
        }

        fun fingerprint(key: PublicKey): String =
            "SHA256:" +
                Base64.getEncoder()
                    .withoutPadding()
                    .encodeToString(
                        MessageDigest.getInstance("SHA-256")
                            .digest(Buffer.PlainBuffer().putPublicKey(key).compactData)
                    )
    }

    @Volatile private var client: SSHClient? = null
    private var terminalSession: Session? = null
    @Volatile private var shell: Session.Shell? = null
    private var files: SFTPClient? = null
    val connected: Boolean
        get() = client?.isAuthenticated == true && client?.isConnected == true

    fun connect(server: Server, credentials: Credentials, verifier: (String) -> Boolean) {
        server.validate()
        initializeCrypto()
        val config =
            DefaultConfig().apply {
                keyAlgorithms =
                    keyAlgorithms.filterNot {
                        it.name.startsWith("ssh-rsa") || it.name.startsWith("ssh-dss")
                    }
                keyExchangeFactories = keyExchangeFactories.filterNot { it.name.contains("sha1") }
            }
        val ssh = SSHClient(config)
        client = ssh
        ssh.connectTimeout = 15_000
        ssh.timeout = 75_000 // Allow the explicit fingerprint prompt to complete.
        ssh.addHostKeyVerifier(
            object : net.schmizz.sshj.transport.verification.HostKeyVerifier {
                override fun verify(hostname: String, port: Int, key: PublicKey) =
                    verifier(fingerprint(key))

                override fun findExistingAlgorithms(hostname: String, port: Int): List<String> =
                    emptyList()
            }
        )
        try {
            ssh.connect(server.host, server.port)
            if (server.keyLogin) {
                val finder =
                    credentials.passphrase
                        .takeIf { it.isNotEmpty() }
                        ?.let { PasswordUtils.createOneOff(it.toCharArray()) }
                ssh.authPublickey(server.user, ssh.loadKeys(credentials.privateKey, null, finder))
            } else ssh.authPassword(server.user, credentials.password)
            ssh.timeout = 15_000
        } catch (e: Exception) {
            close()
            throw e
        }
    }

    @Synchronized
    fun openShell(cols: Int, rows: Int): InputStream {
        shell
            ?.takeIf { it.isOpen }
            ?.let {
                return it.inputStream
            }
        val session = requireClient().startSession()
        try {
            session.allocatePTY(
                "xterm-256color",
                cols.coerceAtLeast(1),
                rows.coerceAtLeast(1),
                0,
                0,
                emptyMap(),
            )
            val channel = session.startShell()
            terminalSession = session
            shell = channel
            return channel.inputStream
        } catch (e: Exception) {
            session.close()
            throw e
        }
    }

    @Synchronized
    fun send(bytes: ByteArray) {
        shell?.outputStream?.let {
            it.write(bytes)
            it.flush()
        }
    }

    fun resize(cols: Int, rows: Int) {
        shell?.changeWindowDimensions(cols.coerceAtLeast(1), rows.coerceAtLeast(1), 0, 0)
    }

    fun execute(command: String, maxBytes: Int = 262144): String =
        requireClient().startSession().use { session ->
            val cmd = session.exec(command)
            val output = cmd.inputStream.readLimited(maxBytes)
            cmd.join(12, TimeUnit.SECONDS)
            check(!cmd.isOpen) { "Remote command timed out." }
            check(cmd.exitStatus == 0) { "Remote command was rejected or failed." }
            output.toString(Charsets.UTF_8)
        }

    @Synchronized
    private fun sftp(): SFTPClient = files ?: requireClient().newSFTPClient().also { files = it }

    @Synchronized
    fun list(path: String): Pair<String, List<RemoteEntry>> {
        val s = sftp()
        val real = s.canonicalize(path)
        return real to
            s.ls(real)
                .filter { it.name != "." && it.name != ".." }
                .map { RemoteEntry(it.name, it.path, it.isDirectory, it.attributes.size) }
                .sortedWith(
                    compareByDescending<RemoteEntry> { it.directory }.thenBy { it.name.lowercase() }
                )
    }

    @Synchronized
    fun read(path: String, limit: Int = 2 * 1024 * 1024): ByteArray =
        sftp().open(path).use { f ->
            val out = java.io.ByteArrayOutputStream()
            val buf = ByteArray(32768)
            var offset = 0L
            while (true) {
                val n = f.read(offset, buf, 0, buf.size)
                if (n < 0) break
                require(offset + n <= limit) { "File exceeds the 2 MiB editor limit." }
                out.write(buf, 0, n)
                offset += n
            }
            out.toByteArray()
        }

    @Synchronized
    fun upload(input: InputStream, path: String) {
        sftp().open(path, EnumSet.of(OpenMode.WRITE, OpenMode.CREAT, OpenMode.EXCL)).use { f ->
            val buf = ByteArray(32768)
            var offset = 0L
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                f.write(offset, buf, 0, n)
                offset += n
            }
        }
    }

    @Synchronized
    fun download(path: String, output: OutputStream) {
        sftp().open(path).use { f ->
            val buf = ByteArray(32768)
            var offset = 0L
            while (true) {
                val n = f.read(offset, buf, 0, buf.size)
                if (n < 0) break
                output.write(buf, 0, n)
                offset += n
            }
        }
    }

    @Synchronized
    fun save(path: String, baseline: ByteArray, updated: ByteArray) {
        require(updated.size <= 2 * 1024 * 1024) { "File exceeds the 2 MiB editor limit." }
        check(read(path).contentEquals(baseline)) {
            "The remote file changed. Reopen it before saving."
        }
        val temp = "$path.modernterm-${java.util.UUID.randomUUID()}"
        try {
            upload(updated.inputStream(), temp)
            check(read(path).contentEquals(baseline)) { "The remote file changed while saving." }
            execute("mv -f -- ${shellQuote(temp)} ${shellQuote(path)}")
        } finally {
            runCatching { sftp().rm(temp) }
        }
    }

    @Synchronized
    fun delete(entry: RemoteEntry) {
        if (entry.directory) sftp().rmdir(entry.path) else sftp().rm(entry.path)
    }

    private fun requireClient(): SSHClient =
        client?.takeIf { connected } ?: error("SSH is not connected.")

    override fun close() {
        // Closing transport also unblocks pending reads; do not wait on the SFTP operation lock.
        val old = client
        client = null
        shell = null
        terminalSession = null
        files = null
        runCatching { old?.disconnect() }
        runCatching { old?.close() }
    }
}

fun InputStream.readLimited(limit: Int): ByteArray {
    val result = java.io.ByteArrayOutputStream()
    val bytes = ByteArray(8192)
    while (true) {
        val n = read(bytes)
        if (n < 0) break
        require(result.size() + n <= limit) { "Remote response exceeds limit." }
        result.write(bytes, 0, n)
    }
    return result.toByteArray()
}

fun connectionError(error: Throwable): String {
    val type = error.javaClass.simpleName
    return when {
        error is java.net.UnknownHostException -> "Host name could not be resolved."
        error is java.net.SocketTimeoutException ->
            "Connection timed out. Check the network and server."
        type.contains("UserAuth") -> "Authentication failed. Check the username and credentials."
        type.contains("Transport") ->
            "SSH negotiation or host verification failed. Check compatible algorithms and the saved fingerprint."
        error is IllegalArgumentException || error is IllegalStateException ->
            error.message ?: "Operation could not be completed."
        else -> "Operation failed ($type). Check connectivity and server permissions."
    }
}
