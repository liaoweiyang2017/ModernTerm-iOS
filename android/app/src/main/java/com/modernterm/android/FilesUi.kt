@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.modernterm.android

import android.content.Intent
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import java.io.File
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.UUID
import kotlinx.coroutines.*

private data class EditorDocument(val path: String, val baseline: ByteArray, val text: String)

@Composable
fun FilesScreen(vm: Workspace, s: ConnectionState, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    var selection by remember(s.server.id) { mutableStateOf<Set<String>>(emptySet()) }
    var deleteDialog by remember { mutableStateOf(false) }
    var actions by remember { mutableStateOf<RemoteEntry?>(null) }
    var edit by remember { mutableStateOf<EditorDocument?>(null) }
    var contents by remember { mutableStateOf("") }
    var jump by remember { mutableStateOf(false) }
    var target by remember { mutableStateOf("") }
    var downloadEntry by remember { mutableStateOf<RemoteEntry?>(null) }
    val scope = rememberCoroutineScope()
    fun refreshAfter(job: Job) {
        job.invokeOnCompletion { scope.launch { if (s.connected) vm.refresh(s) } }
    }
    val upload =
        rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            vm.externalFileFlow = false
            if (uri != null) {
                val directory = s.path
                refreshAfter(
                    vm.fileAction(s) { c ->
                        val name =
                            context.contentResolver
                                .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                                ?.use { cursor ->
                                    if (cursor.moveToFirst()) cursor.getString(0) else null
                                } ?: "upload-${UUID.randomUUID()}"
                        context.contentResolver.openInputStream(uri).use { input ->
                            requireNotNull(input) { "Could not read selected file." }
                            c.upload(input, remotePath(directory, name))
                        }
                    }
                )
            }
        }
    val download =
        rememberLauncherForActivityResult(
            ActivityResultContracts.CreateDocument("application/octet-stream")
        ) { uri ->
            vm.externalFileFlow = false
            val entry = downloadEntry
            downloadEntry = null
            if (uri != null && entry != null)
                vm.fileAction(s) { c ->
                    context.contentResolver.openOutputStream(uri, "wt").use { out ->
                        requireNotNull(out) { "Could not write selected file." }
                        c.download(entry.path, out)
                    }
                }
        }
    LaunchedEffect(s.connected) { if (s.connected) vm.refresh(s) }
    Column(modifier.padding(horizontal = 16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(
                onClick = {
                    vm.refresh(s, s.path.trimEnd('/').substringBeforeLast('/').ifBlank { "/" })
                },
                enabled = s.connected && !s.fileBusy,
            ) {
                Icon(Icons.Default.ArrowUpward, "Parent directory")
            }
            Text(
                s.path,
                Modifier.weight(1f).clickable {
                    target = s.path
                    jump = true
                },
                maxLines = 2,
                style = MaterialTheme.typography.bodySmall,
            )
            IconButton(onClick = { vm.refresh(s) }, enabled = s.connected && !s.fileBusy) {
                Icon(Icons.Default.Refresh, "Refresh")
            }
            IconButton(
                onClick = {
                    vm.externalFileFlow = true
                    upload.launch(arrayOf("*/*"))
                },
                enabled = s.connected && !s.fileBusy,
            ) {
                Icon(Icons.Default.UploadFile, "Upload file")
            }
        }
        if (s.fileBusy) LinearProgressIndicator(Modifier.fillMaxWidth())
        if (selection.isNotEmpty())
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("${selection.size} selected", Modifier.weight(1f))
                TextButton(onClick = { selection = emptySet() }) { Text("Clear") }
                TextButton(onClick = { deleteDialog = true }, enabled = !s.fileBusy) {
                    Text("Delete")
                }
            }
        if (!s.connected) Text("Connect to browse files.", Modifier.padding(16.dp))
        else if (s.files.isEmpty() && !s.fileBusy)
            Text("This directory is empty, or no listing has been loaded.", Modifier.padding(16.dp))
        LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(bottom = 20.dp)) {
            items(s.files, key = { it.path }) { entry ->
                ListItem(
                    headlineContent = { Text(entry.name) },
                    supportingContent = {
                        Text(if (entry.directory) "Directory" else bytes(entry.size.toDouble()))
                    },
                    leadingContent = {
                        Checkbox(
                            entry.path in selection,
                            { checked ->
                                selection =
                                    if (checked) selection + entry.path else selection - entry.path
                            },
                        )
                    },
                    trailingContent = {
                        Icon(
                            if (entry.directory) Icons.Default.Folder
                            else Icons.Default.InsertDriveFile,
                            null,
                        )
                    },
                    modifier =
                        Modifier.clickable(enabled = !s.fileBusy) {
                            if (entry.directory) {
                                selection = emptySet()
                                vm.refresh(s, entry.path)
                            } else actions = entry
                        },
                )
            }
        }
    }
    if (jump)
        AlertDialog(
            onDismissRequest = { jump = false },
            title = { Text("Go to directory") },
            text = { OutlinedTextField(target, { target = it }, label = { Text("Remote path") }) },
            confirmButton = {
                TextButton(
                    onClick = {
                        jump = false
                        selection = emptySet()
                        vm.refresh(s, target)
                    }
                ) {
                    Text("Go")
                }
            },
            dismissButton = { TextButton(onClick = { jump = false }) { Text("Cancel") } },
        )
    actions?.let { entry ->
        AlertDialog(
            onDismissRequest = { actions = null },
            title = { Text(entry.name) },
            text = {
                Column {
                    TextButton(
                        onClick = {
                            actions = null
                            downloadEntry = entry
                            vm.externalFileFlow = true
                            download.launch(entry.name)
                        }
                    ) {
                        Text("Download to device")
                    }
                    TextButton(
                        onClick = {
                            actions = null
                            val token = s.generation
                            vm.fileAction(s) { c ->
                                val folder =
                                    File(context.cacheDir, "downloads/${UUID.randomUUID()}").apply {
                                        mkdirs()
                                    }
                                val file = File(folder, entry.name.substringAfterLast('/'))
                                try {
                                    file.outputStream().use { c.download(entry.path, it) }
                                    withContext(Dispatchers.Main) {
                                        if (s.generation == token) {
                                            val uri =
                                                FileProvider.getUriForFile(
                                                    context,
                                                    "${context.packageName}.files",
                                                    file,
                                                )
                                            val intent =
                                                Intent(Intent.ACTION_SEND)
                                                    .setType("application/octet-stream")
                                                    .putExtra(Intent.EXTRA_STREAM, uri)
                                                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                            vm.externalFileFlow = true
                                            context.startActivity(
                                                Intent.createChooser(
                                                    intent,
                                                    "Share downloaded file",
                                                )
                                            )
                                            scope.launch {
                                                delay(60000)
                                                vm.externalFileFlow = false
                                            }
                                        }
                                    }
                                } catch (e: Exception) {
                                    folder.deleteRecursively()
                                    throw e
                                }
                            }
                        }
                    ) {
                        Text("Download and share")
                    }
                    TextButton(
                        onClick = {
                            actions = null
                            val token = s.generation
                            vm.fileAction(s) { c ->
                                val data = c.read(entry.path)
                                val text =
                                    try {
                                        Charsets.UTF_8.newDecoder()
                                            .onMalformedInput(CodingErrorAction.REPORT)
                                            .onUnmappableCharacter(CodingErrorAction.REPORT)
                                            .decode(ByteBuffer.wrap(data))
                                            .toString()
                                    } catch (_: Exception) {
                                        error("This file is not valid UTF-8 text.")
                                    }
                                withContext(Dispatchers.Main) {
                                    if (s.generation == token) {
                                        edit = EditorDocument(entry.path, data, text)
                                        contents = text
                                    }
                                }
                            }
                        }
                    ) {
                        Text("Edit UTF-8 text (up to 2 MiB)")
                    }
                }
            },
            confirmButton = { TextButton(onClick = { actions = null }) { Text("Close") } },
        )
    }
    if (deleteDialog)
        AlertDialog(
            onDismissRequest = { deleteDialog = false },
            title = { Text("Delete ${selection.size} remote items?") },
            text = {
                Text("This cannot be undone. Non-empty directories will be refused by the server.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val entries = s.files.filter { it.path in selection }
                        deleteDialog = false
                        selection = emptySet()
                        refreshAfter(vm.fileAction(s) { c -> entries.forEach(c::delete) })
                    }
                ) {
                    Text("Delete")
                }
            },
            dismissButton = { TextButton(onClick = { deleteDialog = false }) { Text("Cancel") } },
        )
    edit?.let { document ->
        androidx.compose.ui.window.Dialog(
            onDismissRequest = { if (!s.fileBusy) edit = null },
            properties =
                androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false),
        ) {
            Surface(Modifier.fillMaxSize()) {
                Scaffold(
                    topBar = {
                        TopAppBar(
                            title = { Text(document.path.substringAfterLast('/')) },
                            actions = {
                                TextButton(onClick = { edit = null }, enabled = !s.fileBusy) {
                                    Text("Cancel")
                                }
                                TextButton(
                                    onClick = {
                                        val token = s.generation
                                        vm.fileAction(s) { c ->
                                            c.save(
                                                document.path,
                                                document.baseline,
                                                contents.toByteArray(),
                                            )
                                            withContext(Dispatchers.Main) {
                                                if (s.generation == token) {
                                                    edit = null
                                                    vm.message =
                                                        "Saved. Baseline checks reduce conflicts but are not a multi-user transaction."
                                                }
                                            }
                                        }
                                    },
                                    enabled = !s.fileBusy,
                                ) {
                                    Text("Save")
                                }
                            },
                        )
                    }
                ) { padding ->
                    OutlinedTextField(
                        contents,
                        { contents = it },
                        modifier = Modifier.padding(padding).fillMaxSize().imePadding(),
                        enabled = !s.fileBusy,
                    )
                }
            }
        }
    }
}
