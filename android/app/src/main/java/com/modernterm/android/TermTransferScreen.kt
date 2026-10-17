@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.modernterm.android

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import java.util.UUID
import kotlinx.coroutines.*

@Composable
fun TermTransferScreen(vm: Workspace, dismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var selected by remember { mutableStateOf(emptySet<String>()) }
    var includeSecrets by remember { mutableStateOf(false) }
    var password by remember { mutableStateOf("") }
    var repeat by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var critical by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var output by remember { mutableStateOf<ByteArray?>(null) }
    var files by remember { mutableStateOf(emptyList<ByteArray>()) }
    var fileNames by remember { mutableStateOf(emptyList<String>()) }
    var mergedDuplicates by remember { mutableStateOf(0) }
    var fileIndex by remember { mutableStateOf(0) }
    var decoded by remember { mutableStateOf(emptyList<TermEntry>()) }
    var groups by remember { mutableStateOf(emptyList<List<TermEntry>>()) }
    var choices by remember { mutableStateOf(emptyMap<String, Int>()) }
    var copies by remember { mutableStateOf(emptySet<String>()) }
    val listState = rememberLazyListState()
    LaunchedEffect(files.size, fileIndex, groups.size) { listState.scrollToItem(0) }
    fun reset() {
        password = ""
        repeat = ""
        files = emptyList()
        fileNames = emptyList()
        mergedDuplicates = 0
        decoded = emptyList()
        groups = emptyList()
        choices = emptyMap()
        copies = emptySet()
        fileIndex = 0
        message = null
    }
    fun ready(): List<TermEntry> =
        groups.mapNotNull { group ->
            val id = group[0].server.id
            val index = choices[id] ?: if (group.size == 1) 0 else -1
            val entry = group.getOrNull(index) ?: return@mapNotNull null
            if (vm.servers.any { it.id == id }) {
                if (id in copies)
                    entry.copy(server = entry.server.copy(id = UUID.randomUUID().toString()))
                else null
            } else entry
        }
    val writer =
        rememberLauncherForActivityResult(
            ActivityResultContracts.CreateDocument("application/octet-stream")
        ) { uri ->
            vm.externalFileFlow = false
            val data = output
            output = null
            if (uri != null && data != null)
                scope.launch {
                    busy = true
                    critical = true
                    try {
                        withContext(Dispatchers.IO) {
                            context.contentResolver.openOutputStream(uri, "wt")?.use {
                                it.write(data)
                            } ?: error("Could not write selected file.")
                        }
                        message = "Encrypted file exported."
                    } catch (e: Exception) {
                        message = "Export failed. Remove any incomplete destination file and retry."
                    } finally {
                        critical = false
                        busy = false
                    }
                }
        }
    val picker =
        rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
            vm.externalFileFlow = false
            if (uris.isNotEmpty())
                scope.launch {
                    busy = true
                    reset()
                    try {
                        require(uris.size <= 20) { "Choose up to 20 files." }
                        fileNames =
                            withContext(Dispatchers.IO) {
                                uris.map { uri ->
                                    context.contentResolver
                                        .query(
                                            uri,
                                            arrayOf(android.provider.OpenableColumns.DISPLAY_NAME),
                                            null,
                                            null,
                                            null,
                                        )
                                        ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
                                        ?: "Encrypted connections"
                                }
                            }
                        files =
                            withContext(Dispatchers.IO) {
                                var total = 0
                                uris.map { uri ->
                                    val bytes =
                                        context.contentResolver.openInputStream(uri)?.use { input ->
                                            val out = java.io.ByteArrayOutputStream()
                                            val buffer = ByteArray(8192)
                                            while (true) {
                                                val n = input.read(buffer)
                                                if (n < 0) break
                                                total += n
                                                require(total <= TermArchive.MAXIMUM) {
                                                    "Selected files exceed 16 MiB."
                                                }
                                                out.write(buffer, 0, n)
                                            }
                                            out.toByteArray()
                                        } ?: error("Could not read selected file.")
                                    bytes
                                }
                            }
                    } catch (e: Exception) {
                        reset()
                        message = e.message ?: "Could not read files."
                    } finally {
                        busy = false
                    }
                }
        }
    Dialog(
        onDismissRequest = { if (!critical) dismiss() },
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("SSH transfer") },
                    actions = {
                        TextButton(onClick = { dismiss() }, enabled = !critical) {
                            Text(if (busy) "Cancel" else "Done")
                        }
                    },
                )
            }
        ) { padding ->
            LazyColumn(
                state = listState,
                modifier =
                    Modifier.fillMaxSize()
                        .padding(padding)
                        .imePadding()
                        .padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                contentPadding = PaddingValues(bottom = 24.dp),
            ) {
                if (files.isEmpty() && groups.isEmpty()) {
                    item {
                        Text(
                            "Export saved SSH connections",
                            style = MaterialTheme.typography.titleLarge,
                        )
                    }
                    item {
                        TextButton(
                            onClick = {
                                selected =
                                    if (selected.size == vm.servers.size) emptySet()
                                    else vm.servers.map { it.id }.toSet()
                            },
                            enabled = !busy,
                        ) {
                            Text(
                                if (selected.size == vm.servers.size) "Deselect all"
                                else "Select all"
                            )
                        }
                    }
                    items(vm.servers, key = { it.id }) { server ->
                        Row {
                            Checkbox(
                                server.id in selected,
                                { checked ->
                                    selected =
                                        if (checked) selected + server.id else selected - server.id
                                },
                                enabled = !busy,
                            )
                            Column {
                                Text(server.title)
                                Text(
                                    "${server.user}@${server.host}:${server.port}",
                                    style = MaterialTheme.typography.bodySmall,
                                )
                            }
                        }
                    }
                    item {
                        Row {
                            Checkbox(includeSecrets, { includeSecrets = it }, enabled = !busy)
                            Text("Include saved passwords and private keys")
                        }
                    }
                    item {
                        Text(
                            "The entire file is encrypted. Use a separate long password; a forgotten file password cannot be recovered."
                        )
                    }
                    item {
                        FilePassword("File password (12+ characters)", password, !busy) {
                            password = it
                        }
                    }
                    item { FilePassword("Repeat file password", repeat, !busy) { repeat = it } }
                    item {
                        Button(
                            enabled =
                                !busy &&
                                    selected.isNotEmpty() &&
                                    password.isNotEmpty() &&
                                    password == repeat,
                            onClick = {
                                val secret = password
                                val ids = selected
                                val secrets = includeSecrets
                                busy = true
                                message = null
                                scope.launch {
                                    try {
                                        output =
                                            withContext(Dispatchers.IO) {
                                                val entries =
                                                    vm.store
                                                        .servers()
                                                        .filter { it.id in ids }
                                                        .map {
                                                            TermEntry(
                                                                it,
                                                                if (secrets)
                                                                    vm.store.credentials(it.id)
                                                                else null,
                                                            )
                                                        }
                                                TermArchive.encode(entries, secret)
                                            }
                                        vm.externalFileFlow = true
                                        writer.launch("ModernTerm-connections.term")
                                    } catch (e: Exception) {
                                        message = e.message ?: "Export failed."
                                    } finally {
                                        password = ""
                                        repeat = ""
                                        busy = false
                                    }
                                }
                            },
                        ) {
                            Text("Export ${selected.size} connections")
                        }
                    }
                    item { HorizontalDivider() }
                    item {
                        OutlinedButton(
                            enabled = !busy,
                            onClick = {
                                password = ""
                                repeat = ""
                                vm.externalFileFlow = true
                                picker.launch(arrayOf("*/*"))
                            },
                        ) {
                            Text("Choose .term files…")
                        }
                    }
                    item {
                        Text(
                            "Select up to 20 files / 16 MiB total. Preview before saving. Host trust is not transferred."
                        )
                    }
                } else if (files.isNotEmpty()) {
                    item {
                        Text("Unlock file ${fileIndex + 1} of ${files.size}")
                        Text(fileNames.getOrNull(fileIndex) ?: "Encrypted connections")
                    }
                    item { FilePassword("File password", password, !busy) { password = it } }
                    item {
                        Button(
                            enabled = !busy,
                            onClick = {
                                val data = files[fileIndex]
                                val secret = password
                                busy = true
                                message = null
                                scope.launch {
                                    try {
                                        val entries =
                                            withContext(Dispatchers.Default) {
                                                TermArchive.decode(data, secret)
                                            }
                                        require(decoded.size + entries.size <= 200) {
                                            "Import exceeds 200 connections."
                                        }
                                        decoded = decoded + entries
                                        fileIndex++
                                        password = ""
                                        if (fileIndex == files.size) {
                                            groups = TermArchive.grouped(decoded)
                                            mergedDuplicates =
                                                decoded.size - groups.sumOf { it.size }
                                            decoded = emptyList()
                                            files = emptyList()
                                        }
                                    } catch (e: Exception) {
                                        message = e.message ?: "Invalid connection data."
                                    } finally {
                                        busy = false
                                    }
                                }
                            },
                        ) {
                            Text("Unlock and continue")
                        }
                    }
                    item {
                        TextButton(enabled = !busy, onClick = { reset() }) { Text("Cancel import") }
                    }
                } else {
                    item {
                        Text("Import preview", style = MaterialTheme.typography.titleLarge)
                        Text(
                            "${ready().size} new connections; ${groups.size - ready().size} skipped. Nothing connects automatically."
                        )
                    }
                    item {
                        Text(
                            "${groups.count { group -> vm.servers.any { it.id == group[0].server.id } }} already saved; ${groups.count { it.size > 1 }} conflicting IDs; $mergedDuplicates identical entries merged. Versions follow selected file order.",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    items(groups, key = { it[0].server.id }) { group ->
                        val id = group[0].server.id
                        val choice = choices[id] ?: if (group.size == 1) 0 else -1
                        ElevatedCard {
                            Column(Modifier.padding(12.dp)) {
                                Text(group[0].server.title)
                                if (group.size > 1) Text("Conflicting versions — choose one")
                                Row {
                                    RadioButton(
                                        choice == -1,
                                        { choices = choices + (id to -1) },
                                        enabled = !busy,
                                    )
                                    Text("Skip")
                                }
                                group.forEachIndexed { i, entry ->
                                    Row {
                                        RadioButton(
                                            choice == i,
                                            { choices = choices + (id to i) },
                                            enabled = !busy,
                                        )
                                        Text(
                                            "${i+1}: ${entry.server.user}@${entry.server.host}:${entry.server.port} · ${if (entry.credentials == null) "configuration only" else "with credentials"}"
                                        )
                                    }
                                }
                                if (vm.servers.any { it.id == id })
                                    Row {
                                        Checkbox(
                                            id in copies,
                                            { copies = if (it) copies + id else copies - id },
                                            enabled = !busy,
                                        )
                                        Text("Already saved — import as a new copy")
                                    }
                            }
                        }
                    }
                    item {
                        Text(
                            "Configuration-only connections may need credentials before connecting."
                        )
                    }
                    item {
                        Button(
                            enabled = !busy && ready().isNotEmpty(),
                            onClick = {
                                val entries = ready()
                                busy = true
                                critical = true
                                scope.launch {
                                    try {
                                        val count =
                                            withContext(Dispatchers.IO) {
                                                vm.store.importTerm(entries)
                                            }
                                        vm.reload()
                                        reset()
                                        message = "Imported $count connections."
                                    } catch (e: Exception) {
                                        message = e.message ?: "Import failed."
                                    } finally {
                                        critical = false
                                        busy = false
                                    }
                                }
                            },
                        ) {
                            Text("Import ${ready().size} connections")
                        }
                    }
                    item {
                        TextButton(enabled = !busy, onClick = { reset() }) { Text("Cancel import") }
                    }
                }
                if (busy) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
                message?.let { item { Text(it) } }
            }
        }
    }
}

@Composable
private fun FilePassword(label: String, value: String, enabled: Boolean, change: (String) -> Unit) {
    OutlinedTextField(
        value,
        change,
        label = { Text(label) },
        enabled = enabled,
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
        visualTransformation = PasswordVisualTransformation(),
        keyboardOptions =
            KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false),
    )
}
