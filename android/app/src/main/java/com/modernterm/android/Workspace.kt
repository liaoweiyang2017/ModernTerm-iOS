package com.modernterm.android

import android.app.Application
import android.net.Uri
import androidx.compose.runtime.*
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import java.net.URI
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel

class ConnectionState(val server: Server) {
    var connected by mutableStateOf(false)
    var connecting by mutableStateOf(false)
    var error by mutableStateOf<String?>(null)
    var monitorError by mutableStateOf<String?>(null)
    var snapshot by mutableStateOf<Snapshot?>(null)
    var history by mutableStateOf<List<Snapshot>>(emptyList())
    var terminalBytes = ByteArray(0)
    var terminal: TerminalPane? = null
    var shellStarted = false
    var columns = 80
    var rows = 24
    var files by mutableStateOf<List<RemoteEntry>>(emptyList())
    var path by mutableStateOf(".")
    var fileBusy by mutableStateOf(false)
    @Volatile var generation = UUID.randomUUID()
    var connection: SshConnection? = null
    var job: Job? = null
    var monitor: Job? = null
    var shell: Job? = null
    val writes = Channel<ByteArray>(64)
    var writer: Job? = null
}

data class TrustPrompt(
    val id: String = UUID.randomUUID().toString(),
    val sessionId: String,
    val endpoint: String,
    val fingerprint: String,
    val response: CompletableFuture<Boolean>,
)

class Workspace(app: Application) : AndroidViewModel(app) {
    val store = LocalStore(app)
    var servers by mutableStateOf<List<Server>>(emptyList())
        private set

    var preferences by mutableStateOf(Preferences())
        private set

    var macros by mutableStateOf<List<Macro>>(emptyList())
        private set

    val sessions = mutableStateListOf<ConnectionState>()
    val trust = mutableStateListOf<TrustPrompt>()
    var selected by mutableStateOf<String?>(null)
    var message by mutableStateOf<String?>(null)
    var externalFileFlow = false

    init {
        runCatching { reload() }
            .onFailure {
                message = "Saved configuration could not be loaded; files were preserved."
            }
        store.loadError?.let { message = it }
    }

    private fun reload() {
        servers = store.servers()
        preferences = store.preferences()
        macros = store.macros()
    }

    fun save(server: Server, credentials: Credentials, onSuccess: () -> Unit = {}) =
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) { store.save(server, credentials) }
                reload()
                onSuccess()
            } catch (e: Exception) {
                message = connectionError(e)
            }
        }

    fun remove(server: Server) =
        viewModelScope.launch {
            try {
                sessions.find { it.server.id == server.id }?.let { close(it) }
                withContext(Dispatchers.IO) { store.delete(server) }
                reload()
            } catch (e: Exception) {
                message = connectionError(e)
            }
        }

    fun favorite(server: Server) =
        viewModelScope.launch {
            try {
                val c = withContext(Dispatchers.IO) { store.credentials(server.id) }
                save(server.copy(favorite = !server.favorite), c)
            } catch (e: Exception) {
                message = connectionError(e)
            }
        }

    fun settings(p: Preferences) =
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) { store.savePreferences(p) }
                preferences = p
            } catch (e: Exception) {
                message = connectionError(e)
            }
        }

    fun saveMacros(values: List<Macro>) =
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) { store.saveMacros(values) }
                macros = values
            } catch (e: Exception) {
                message = connectionError(e)
            }
        }

    suspend fun credentials(server: Server) =
        withContext(Dispatchers.IO) { store.credentials(server.id) }

    fun open(server: Server) {
        val session =
            sessions.find { it.server.id == server.id }
                ?: run {
                    if (sessions.size >= 8) {
                        message = "Up to 8 sessions can be open. Close one before adding another."
                        return
                    }
                    ConnectionState(server).also { sessions.add(it) }
                }
        selected = server.id
        if (!session.connected && !session.connecting) connect(session)
    }

    fun connect(session: ConnectionState) {
        if (session.connected || session.connecting) return
        val token = UUID.randomUUID()
        session.generation = token
        session.connecting = true
        session.error = null
        session.monitorError = null
        session.snapshot = null
        session.history = emptyList()
        session.terminalBytes = ByteArray(0)
        val connection = SshConnection()
        session.connection = connection
        session.job =
            viewModelScope.launch {
                var verificationError: String? = null
                try {
                    val credentials =
                        withContext(Dispatchers.IO) { store.credentials(session.server.id) }
                    withContext(Dispatchers.IO) {
                        connection.connect(session.server, credentials) verifier@{ fingerprint ->
                            if (session.generation != token) return@verifier false
                            val saved = store.pin(session.server.endpoint)
                            if (saved != null) {
                                if (saved != fingerprint)
                                    verificationError =
                                        "Server fingerprint changed. Connection refused. Verify the server before forgetting the saved fingerprint."
                                saved == fingerprint
                            } else {
                                val response = CompletableFuture<Boolean>()
                                val prompt =
                                    TrustPrompt(
                                        sessionId = session.server.id,
                                        endpoint = session.server.endpoint,
                                        fingerprint = fingerprint,
                                        response = response,
                                    )
                                viewModelScope.launch {
                                    if (session.generation == token) trust.add(prompt)
                                    else response.complete(false)
                                }
                                try {
                                    val accepted = response.get(60, TimeUnit.SECONDS)
                                    if (accepted && session.generation == token) {
                                        store.trust(session.server.endpoint, fingerprint)
                                        true
                                    } else false
                                } finally {
                                    viewModelScope.launch { trust.removeAll { it.id == prompt.id } }
                                }
                            }
                        }
                    }
                    if (session.generation != token) {
                        withContext(Dispatchers.IO) { connection.close() }
                        return@launch
                    }
                    session.connected = true
                    session.connecting = false
                    session.writer =
                        viewModelScope.launch {
                            for (bytes in session.writes) {
                                if (session.generation != token) break
                                try {
                                    withContext(Dispatchers.IO) { connection.send(bytes) }
                                } catch (e: Exception) {
                                    if (session.generation == token)
                                        session.error = connectionError(e)
                                }
                            }
                        }
                    monitor(session, token)
                } catch (e: Exception) {
                    if (session.generation == token) {
                        session.error = verificationError ?: connectionError(e)
                        session.connecting = false
                        session.connected = false
                        withContext(NonCancellable + Dispatchers.IO) { connection.close() }
                    }
                }
            }
    }

    fun trustReply(prompt: TrustPrompt, accept: Boolean) {
        prompt.response.complete(accept)
        trust.removeAll { it.id == prompt.id }
    }

    fun disconnect(session: ConnectionState) {
        session.generation = UUID.randomUUID()
        session.job?.cancel()
        session.monitor?.cancel()
        session.shell?.cancel()
        session.writer?.cancel()
        trust
            .filter { it.sessionId == session.server.id }
            .toList()
            .forEach { trustReply(it, false) }
        session.connected = false
        session.connecting = false
        session.shellStarted = false
        session.fileBusy = false
        while (session.writes.tryReceive().isSuccess) {
            /* drop stale keystrokes */
        }
        val old = session.connection
        session.connection = null
        session.terminal?.hideKeyboard()
        viewModelScope.launch(Dispatchers.IO) { old?.close() }
    }

    fun close(session: ConnectionState) {
        disconnect(session)
        sessions.remove(session)
        session.terminal?.destroy()
        session.terminal = null
        if (selected == session.server.id) selected = null
    }

    fun background() {
        if (!externalFileFlow) sessions.toList().forEach(::disconnect)
        else
            viewModelScope.launch {
                delay(60000)
                if (externalFileFlow) {
                    externalFileFlow = false
                    sessions.toList().forEach(::disconnect)
                }
            }
    }

    fun shell(session: ConnectionState) {
        if (!session.connected || session.shellStarted) return
        session.shellStarted = true
        val token = session.generation
        val c = session.connection ?: return
        session.shell =
            viewModelScope.launch {
                try {
                    withContext(Dispatchers.IO) {
                        val stream = c.openShell(session.columns, session.rows)
                        val buffer = ByteArray(8192)
                        while (isActive && session.generation == token) {
                            val n = stream.read(buffer)
                            if (n < 0) break
                            val bytes = buffer.copyOf(n)
                            withContext(Dispatchers.Main) {
                                if (session.generation == token) {
                                    val combined = session.terminalBytes + bytes
                                    session.terminalBytes =
                                        if (combined.size > 262144)
                                            combined.copyOfRange(
                                                combined.size - 262144,
                                                combined.size,
                                            )
                                        else combined
                                    session.terminal?.write(bytes)
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    if (session.generation == token && isActive) session.error = connectionError(e)
                } finally {
                    if (session.generation == token) session.shellStarted = false
                }
            }
    }

    fun send(session: ConnectionState, text: String) {
        if (session.connected && !session.writes.trySend(text.toByteArray()).isSuccess)
            session.error = "Input queue is busy. Wait before sending more text."
    }

    fun resize(session: ConnectionState, cols: Int, rows: Int) {
        viewModelScope.launch {
            session.columns = cols
            session.rows = rows
            try {
                withContext(Dispatchers.IO) { session.connection?.resize(cols, rows) }
            } catch (_: Exception) {}
        }
    }

    fun oscDirectory(session: ConnectionState, value: String) {
        if (!preferences.followDirectory) return
        val uri = runCatching { URI(value) }.getOrNull() ?: return
        if (uri.scheme == "file" && uri.host.equals(session.server.host, true) && uri.path != null)
            refresh(session, uri.path)
    }

    private fun monitor(session: ConnectionState, token: UUID) {
        session.monitor =
            viewModelScope.launch {
                val script =
                    getApplication<Application>().assets.open("monitor.sh").bufferedReader().use {
                        it.readText()
                    }
                val command =
                    "if command -v timeout >/dev/null 2>&1; then timeout 9 sh -c ${shellQuote(script)}; else sh -c ${shellQuote(script)}; fi"
                while (isActive && session.generation == token && session.connected) {
                    try {
                        val next =
                            withContext(Dispatchers.IO) {
                                Metrics.parse(
                                    session.connection!!.execute(command),
                                    session.snapshot,
                                )
                            }
                        if (session.generation == token) {
                            session.snapshot = next
                            session.history = (session.history + next).takeLast(60)
                            session.monitorError =
                                if (next.host.isBlank()) "No monitoring data returned." else null
                        }
                    } catch (e: Exception) {
                        if (session.generation == token && isActive) {
                            session.monitorError = connectionError(e)
                            if (session.connection?.connected != true) {
                                session.connected = false
                                break
                            }
                        }
                    }
                    delay(preferences.interval * 1000L)
                }
            }
    }

    fun refresh(session: ConnectionState, path: String = session.path): Job {
        val token = session.generation
        return fileAction(session) { c ->
            val (real, entries) = c.list(path)
            withContext(Dispatchers.Main) {
                if (session.generation == token) {
                    session.path = real
                    session.files = entries
                }
            }
        }
    }

    fun fileAction(session: ConnectionState, operation: suspend (SshConnection) -> Unit): Job =
        viewModelScope.launch {
            if (session.fileBusy) return@launch
            val token = session.generation
            val c = session.connection
            if (c == null || !session.connected) {
                session.error = "Connect before using SFTP."
                return@launch
            }
            session.fileBusy = true
            try {
                withContext(Dispatchers.IO) { operation(c) }
            } catch (e: Exception) {
                if (session.generation == token) session.error = connectionError(e)
            } finally {
                if (session.generation == token) session.fileBusy = false
            }
        }

    fun importMigration(uri: Uri) =
        viewModelScope.launch {
            try {
                val result =
                    withContext(Dispatchers.IO) {
                        getApplication<Application>().contentResolver.openInputStream(uri).use {
                            input ->
                            requireNotNull(input) { "Could not read the selected file." }
                            store.importMigration(input.readLimited(4 * 1024 * 1024))
                        }
                    }
                reload()
                message =
                    "Imported ${result.imported} sessions; ${result.skipped} existing entries preserved. The source file was not deleted."
            } catch (e: Exception) {
                message = connectionError(e)
            }
        }

    fun forgetPin(server: Server) =
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) { store.forgetPin(server.endpoint) }
                message =
                    "Saved fingerprint removed. Verify the next fingerprint before connecting."
            } catch (e: Exception) {
                message = connectionError(e)
            }
        }

    override fun onCleared() {
        sessions.forEach { it.connection?.close() }
        trust.forEach { it.response.complete(false) }
        super.onCleared()
    }
}
