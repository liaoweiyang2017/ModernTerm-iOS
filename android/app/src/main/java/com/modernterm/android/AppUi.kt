@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.modernterm.android

import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject

@Composable
fun ModernTermApp(vm: Workspace) {
    val systemDark = isSystemInDarkTheme()
    val dark =
        when (vm.preferences.appearance) {
            "dark" -> true
            "light" -> false
            else -> systemDark
        }
    val context = LocalContext.current
    val colors =
        if (vm.preferences.dynamicColor && Build.VERSION.SDK_INT >= 31) {
            if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        } else if (dark)
            darkColorScheme(
                primary = androidx.compose.ui.graphics.Color(0xFFFFB68D),
                secondary = androidx.compose.ui.graphics.Color(0xFFD7C2AF),
            )
        else
            lightColorScheme(
                primary = androidx.compose.ui.graphics.Color(0xFF934600),
                secondary = androidx.compose.ui.graphics.Color(0xFF725943),
            )
    MaterialTheme(colorScheme = colors) {
        var section by remember { mutableStateOf(0) }
        var editing by remember { mutableStateOf<Server?>(null) }
        var delete by remember { mutableStateOf<Server?>(null) }
        var query by remember { mutableStateOf("") }
        val selected = vm.sessions.find { it.server.id == vm.selected }
        BackHandler(selected != null) { vm.selected = null }
        BoxWithConstraints(Modifier.fillMaxSize().statusBarsPadding()) {
            val wide = maxWidth >= 840.dp
            Scaffold(
                topBar = {
                    TopAppBar(
                        windowInsets = WindowInsets(0, 0, 0, 0),
                        title = {
                            Column {
                                Text(selected?.server?.title ?: "ModernTerm", maxLines = 1)
                                if (selected == null)
                                    Text(
                                        "Your servers, in one place",
                                        style = MaterialTheme.typography.labelMedium,
                                    )
                            }
                        },
                        navigationIcon = {
                            if (selected != null)
                                IconButton(onClick = { vm.selected = null }) {
                                    Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back to servers")
                                }
                        },
                        actions = {
                            if (selected != null) {
                                TextButton(
                                    onClick = {
                                        if (selected.connected || selected.connecting)
                                            vm.disconnect(selected)
                                        else vm.connect(selected)
                                    }
                                ) {
                                    Text(
                                        if (selected.connected) "Disconnect"
                                        else if (selected.connecting) "Cancel" else "Connect"
                                    )
                                }
                            }
                        },
                    )
                },
                floatingActionButton = {
                    if (selected == null && section == 0)
                        FloatingActionButton(onClick = { editing = Server() }) {
                            Icon(Icons.Default.Add, "Add server")
                        }
                },
                bottomBar = {
                    if (selected == null && !wide)
                        NavigationBar {
                            listOf(
                                    "Servers" to Icons.Default.Dns,
                                    "Overview" to Icons.Default.Dashboard,
                                    "Settings" to Icons.Default.Settings,
                                )
                                .forEachIndexed { i, p ->
                                    NavigationBarItem(
                                        selected = section == i,
                                        onClick = { section = i },
                                        icon = { Icon(p.second, p.first) },
                                        label = { Text(p.first) },
                                    )
                                }
                        }
                },
            ) { padding ->
                Row(Modifier.padding(padding).fillMaxSize()) {
                    if (wide)
                        NavigationRail {
                            listOf(
                                    "Servers" to Icons.Default.Dns,
                                    "Overview" to Icons.Default.Dashboard,
                                    "Settings" to Icons.Default.Settings,
                                )
                                .forEachIndexed { i, p ->
                                    NavigationRailItem(
                                        selected = section == i && selected == null,
                                        onClick = {
                                            section = i
                                            vm.selected = null
                                        },
                                        icon = { Icon(p.second, p.first) },
                                        label = { Text(p.first) },
                                    )
                                }
                        }
                    if (selected != null) {
                        if (wide)
                            Column(
                                Modifier.width(280.dp)
                                    .fillMaxHeight()
                                    .background(MaterialTheme.colorScheme.surfaceContainer)
                            ) {
                                ServerList(
                                    vm,
                                    query,
                                    { query = it },
                                    { editing = it },
                                    { delete = it },
                                    Modifier.fillMaxSize(),
                                )
                            }
                        SessionContent(vm, selected, dark, Modifier.weight(1f))
                    } else
                        when (section) {
                            0 ->
                                ServerList(
                                    vm,
                                    query,
                                    { query = it },
                                    { editing = it },
                                    { delete = it },
                                    Modifier.weight(1f),
                                )
                            1 -> Overview(vm, Modifier.weight(1f))
                            else -> SettingsScreen(vm, Modifier.weight(1f))
                        }
                }
            }
        }
        editing?.let { server -> ServerEditor(vm, server) { editing = null } }
        delete?.let { server ->
            AlertDialog(
                onDismissRequest = { delete = null },
                title = { Text("Delete ${server.title}?") },
                text = {
                    Text("This removes its saved configuration and credentials from this device.")
                },
                confirmButton = {
                    TextButton(
                        onClick = {
                            vm.remove(server)
                            delete = null
                        }
                    ) {
                        Text("Delete")
                    }
                },
                dismissButton = { TextButton(onClick = { delete = null }) { Text("Cancel") } },
            )
        }
        vm.message?.let { message ->
            AlertDialog(
                onDismissRequest = { vm.message = null },
                title = { Text("ModernTerm") },
                text = { Text(message) },
                confirmButton = { TextButton(onClick = { vm.message = null }) { Text("OK") } },
            )
        }
        vm.trust.firstOrNull()?.let { prompt ->
            AlertDialog(
                onDismissRequest = { vm.trustReply(prompt, false) },
                title = { Text("Trust this server?") },
                text = {
                    Text(
                        "Verify this SHA-256 fingerprint with your administrator before continuing.\n\n${prompt.endpoint}\n\n${prompt.fingerprint}"
                    )
                },
                confirmButton = {
                    TextButton(onClick = { vm.trustReply(prompt, true) }) {
                        Text("Trust and connect")
                    }
                },
                dismissButton = {
                    TextButton(onClick = { vm.trustReply(prompt, false) }) { Text("Reject") }
                },
            )
        }
    }
}

@Composable
private fun ServerList(
    vm: Workspace,
    query: String,
    onQuery: (String) -> Unit,
    edit: (Server) -> Unit,
    delete: (Server) -> Unit,
    modifier: Modifier,
) {
    val filtered =
        vm.servers
            .filter { (it.name + it.host + it.user + it.group).contains(query, true) }
            .sortedWith(
                compareByDescending<Server> { it.favorite }
                    .thenBy { it.group }
                    .thenBy { it.title.lowercase() }
            )
    LazyColumn(
        modifier.padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = PaddingValues(bottom = 100.dp),
    ) {
        item {
            OutlinedTextField(
                query,
                onQuery,
                label = { Text("Search servers") },
                leadingIcon = { Icon(Icons.Default.Search, null) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().testTag("server-search"),
            )
        }
        if (vm.servers.isEmpty())
            item {
                Card(Modifier.fillMaxWidth()) {
                    Column(
                        Modifier.padding(24.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Icon(Icons.Default.Terminal, null, Modifier.size(40.dp))
                        Text(
                            "A workspace for every server",
                            style = MaterialTheme.typography.headlineSmall,
                        )
                        Text(
                            "Add a server to open a secure terminal, browse files and monitor its health."
                        )
                        Button(onClick = { edit(Server()) }) { Text("Add your first server") }
                    }
                }
            }
        items(filtered, key = { it.id }) { server ->
            ElevatedCard(onClick = { vm.open(server) }, modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Dns, null, tint = MaterialTheme.colorScheme.primary)
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(
                                server.title,
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Text(
                                "${server.user}@${server.host}:${server.port}",
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                        IconButton(onClick = { vm.favorite(server) }) {
                            Icon(
                                if (server.favorite) Icons.Default.Star
                                else Icons.Default.StarBorder,
                                "Toggle favorite",
                            )
                        }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            server.group,
                            style = MaterialTheme.typography.labelMedium,
                            modifier = Modifier.weight(1f),
                        )
                        TextButton(onClick = { edit(server) }) { Text("Edit") }
                        IconButton(onClick = { delete(server) }) {
                            Icon(Icons.Default.DeleteOutline, "Delete server")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Overview(vm: Workspace, modifier: Modifier) {
    LazyColumn(modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Text(
                "Open sessions · ${vm.sessions.size}/8",
                style = MaterialTheme.typography.titleLarge,
            )
        }
        if (vm.sessions.isEmpty())
            item { Text("Open a server to see its connection and health here.") }
        items(vm.sessions, key = { it.server.id }) { s ->
            Card(onClick = { vm.selected = s.server.id }, modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp)) {
                    Text(s.server.title, style = MaterialTheme.typography.titleMedium)
                    Text(
                        if (s.connected) "Connected"
                        else if (s.connecting) "Connecting…" else "Disconnected"
                    )
                    Text(
                        "CPU ${percent(s.snapshot?.cpu)}  ·  Memory ${percent(s.snapshot?.memoryPercent)}"
                    )
                    Row {
                        TextButton(
                            onClick = { if (s.connected) vm.disconnect(s) else vm.connect(s) }
                        ) {
                            Text(if (s.connected) "Disconnect" else "Connect")
                        }
                        TextButton(onClick = { vm.close(s) }) { Text("Close session") }
                    }
                }
            }
        }
    }
}

@Composable
private fun ServerEditor(vm: Workspace, initial: Server, dismiss: () -> Unit) {
    var name by remember { mutableStateOf(initial.name) }
    var host by remember { mutableStateOf(initial.host) }
    var port by remember { mutableStateOf(initial.port.toString()) }
    var user by remember { mutableStateOf(initial.user) }
    var group by remember { mutableStateOf(initial.group) }
    var keyLogin by remember { mutableStateOf(initial.keyLogin) }
    var password by remember { mutableStateOf("") }
    var privateKey by remember { mutableStateOf("") }
    var passphrase by remember { mutableStateOf("") }
    var ready by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val keyPicker =
        rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            vm.externalFileFlow = false
            if (uri != null)
                scope.launch {
                    try {
                        privateKey =
                            withContext(Dispatchers.IO) {
                                context.contentResolver.openInputStream(uri).use {
                                    requireNotNull(it)
                                        .readLimited(1024 * 1024)
                                        .toString(Charsets.UTF_8)
                                }
                            }
                    } catch (e: Exception) {
                        vm.message = connectionError(e)
                    }
                }
        }
    LaunchedEffect(initial.id) {
        try {
            val c = vm.credentials(initial)
            password = c.password
            privateKey = c.privateKey
            passphrase = c.passphrase
            ready = true
        } catch (e: Exception) {
            vm.message = connectionError(e)
            dismiss()
        }
    }

    ModalBottomSheet(
        onDismissRequest = { if (!saving) dismiss() },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(
            Modifier.fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .imePadding()
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                if (vm.servers.any { it.id == initial.id }) "Edit server" else "New server",
                style = MaterialTheme.typography.headlineSmall,
            )
            OutlinedTextField(
                name,
                { name = it },
                label = { Text("Name") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                host,
                { host = it },
                label = { Text("Host name or IP") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            )
            Row {
                OutlinedTextField(
                    user,
                    { user = it },
                    label = { Text("Username") },
                    singleLine = true,
                    modifier = Modifier.weight(2f),
                )
                Spacer(Modifier.width(8.dp))
                OutlinedTextField(
                    port,
                    { port = it.filter(Char::isDigit) },
                    label = { Text("Port") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
            }
            OutlinedTextField(
                group,
                { group = it },
                label = { Text("Group") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Use private key", modifier = Modifier.weight(1f))
                Switch(keyLogin, { keyLogin = it })
            }
            if (keyLogin) {
                OutlinedButton(
                    onClick = {
                        vm.externalFileFlow = true
                        keyPicker.launch(arrayOf("*/*"))
                    }
                ) {
                    Text(
                        if (privateKey.isBlank()) "Import OpenSSH private key"
                        else "Replace imported key"
                    )
                }
                OutlinedTextField(
                    passphrase,
                    { passphrase = it },
                    label = { Text("Key passphrase (optional)") },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            } else
                OutlinedTextField(
                    password,
                    { password = it },
                    label = { Text("Password") },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            Text(
                "Credentials are encrypted on this device with Android Keystore. They are not synced or backed up.",
                style = MaterialTheme.typography.bodySmall,
            )
            Button(
                onClick = {
                    val value =
                        initial.copy(
                            name = name.trim(),
                            host = host.trim(),
                            port = port.toIntOrNull() ?: 0,
                            user = user,
                            group = group.ifBlank { "Servers" },
                            keyLogin = keyLogin,
                        )
                    try {
                        value.validate()
                        saving = true
                        vm.save(value, Credentials(password, privateKey, passphrase)) { dismiss() }
                            .invokeOnCompletion { saving = false }
                    } catch (e: Exception) {
                        vm.message = connectionError(e)
                    }
                },
                enabled = ready && !saving,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (saving) "Saving…" else "Save server")
            }
            Spacer(Modifier.height(20.dp))
        }
    }
}

@Composable
fun SessionContent(
    vm: Workspace,
    s: ConnectionState,
    dark: Boolean,
    modifier: Modifier = Modifier,
) {
    var page by rememberSaveable(s.server.id) { mutableStateOf(0) }
    Column(modifier.fillMaxHeight()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                if (s.connected) Icons.Default.CheckCircle else Icons.Default.Circle,
                null,
                tint =
                    if (s.connected) MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.outline,
                modifier = Modifier.size(16.dp),
            )
            Spacer(Modifier.width(8.dp))
            Text(
                if (s.connected) "Connected"
                else if (s.connecting) "Connecting…" else "Disconnected",
                style = MaterialTheme.typography.labelLarge,
            )
            Spacer(Modifier.weight(1f))
            if (s.connecting) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
        }

        PrimaryTabRow(selectedTabIndex = page) {
            listOf("Monitor", "Terminal", "SFTP").forEachIndexed { i, label ->
                Tab(selected = page == i, onClick = { page = i }, text = { Text(label) })
            }
        }
        when (page) {
            0 -> MonitorScreen(s, Modifier.weight(1f))
            1 -> TerminalScreen(vm, s, dark, Modifier.weight(1f))
            else -> FilesScreen(vm, s, Modifier.weight(1f))
        }
    }
    s.error?.let { error ->
        AlertDialog(
            onDismissRequest = { s.error = null },
            title = { Text("Connection") },
            text = { Text(error) },
            confirmButton = { TextButton(onClick = { s.error = null }) { Text("OK") } },
        )
    }
}

@Composable
private fun TerminalScreen(vm: Workspace, s: ConnectionState, dark: Boolean, modifier: Modifier) {
    val context = LocalContext.current
    val palettes = remember {
        JSONArray(context.assets.open("palettes.json").bufferedReader().use { it.readText() })
    }
    val selected =
        if (vm.preferences.palette == "ubuntu-neo")
            if (dark) "ubuntu-neo-dark" else "ubuntu-neo-light"
        else vm.preferences.palette
    val palette =
        (0 until palettes.length())
            .map { palettes.getJSONObject(it) }
            .find { it.getString("id") == selected } ?: palettes.getJSONObject(0)
    val theme =
        JSONObject()
            .put("background", palette.getString("background"))
            .put("foreground", palette.getString("foreground"))
            .put("cursor", palette.getString("foreground"))
    val ansi = palette.getJSONArray("ansi")
    listOf(
            "black",
            "red",
            "green",
            "yellow",
            "blue",
            "magenta",
            "cyan",
            "white",
            "brightBlack",
            "brightRed",
            "brightGreen",
            "brightYellow",
            "brightBlue",
            "brightMagenta",
            "brightCyan",
            "brightWhite",
        )
        .forEachIndexed { i, key -> theme.put(key, ansi.getString(i)) }
    LaunchedEffect(s.connected) { if (s.connected) vm.shell(s) }
    Column(modifier) {
        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(onClick = { s.terminal?.showKeyboard() }) { Text("Keyboard") }
            TextButton(onClick = { s.terminal?.hideKeyboard() }) { Text("Hide") }
            listOf(
                    "Esc" to "\u001b",
                    "Tab" to "\t",
                    "Ctrl-C" to "\u0003",
                    "Ctrl-D" to "\u0004",
                    "↑" to "\u001b[A",
                    "↓" to "\u001b[B",
                    "←" to "\u001b[D",
                    "→" to "\u001b[C",
                )
                .forEach { (label, bytes) ->
                    TextButton(onClick = { vm.send(s, bytes) }, enabled = s.connected) {
                        Text(label)
                    }
                }
        }
        AndroidView(
            factory = { ctx ->
                TerminalPane(
                        ctx,
                        { text -> vm.viewModelScope.launch { vm.send(s, text) } },
                        { c, r -> vm.resize(s, c, r) },
                        { value -> vm.viewModelScope.launch { vm.oscDirectory(s, value) } },
                    )
                    .also { view ->
                        s.terminal = view
                        view.onReady = {
                            view.write(s.terminalBytes)
                            view.setAppearance(theme, vm.preferences.fontSize)
                            view.showKeyboard()
                        }
                    }
            },
            update = { it.setAppearance(theme, vm.preferences.fontSize) },
            onRelease = { view ->
                view.hideKeyboard()
                if (s.terminal === view) s.terminal = null
                view.destroy()
            },
            modifier = Modifier.fillMaxWidth().weight(1f).testTag("terminal"),
        )
        if (vm.macros.isNotEmpty())
            Row(Modifier.horizontalScroll(rememberScrollState())) {
                vm.macros.forEach { macro ->
                    AssistChip(
                        onClick = { vm.send(s, macro.command + "\n") },
                        label = { Text(macro.name) },
                        modifier = Modifier.padding(4.dp),
                        enabled = s.connected,
                    )
                }
            }
    }
}

@Composable
private fun SettingsScreen(vm: Workspace, modifier: Modifier) {
    val context = LocalContext.current
    val palettes = remember {
        JSONArray(context.assets.open("palettes.json").bufferedReader().use { it.readText() })
            .let { a ->
                (0 until a.length()).map {
                    a.getJSONObject(it).let { it.getString("id") to it.getString("name") }
                }
            }
    }
    var newName by remember { mutableStateOf("") }
    var newCommand by remember { mutableStateOf("") }
    var forget by remember { mutableStateOf<Server?>(null) }
    val picker =
        rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            vm.externalFileFlow = false
            if (uri != null) vm.importMigration(uri)
        }
    LazyColumn(
        modifier.padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        contentPadding = PaddingValues(bottom = 24.dp),
    ) {
        item { Text("Make it yours", style = MaterialTheme.typography.headlineSmall) }
        item {
            SettingChoice(
                "Appearance",
                vm.preferences.appearance,
                listOf("system" to "System", "light" to "Light", "dark" to "Dark"),
            ) {
                vm.settings(vm.preferences.copy(appearance = it))
            }
        }
        item {
            SettingChoice("Terminal colors", vm.preferences.palette, palettes) {
                vm.settings(vm.preferences.copy(palette = it))
            }
            Text(
                "Ubuntu Neo (Auto) follows Appearance. Fixed Light and Dark themes keep their selected colors.",
                style = MaterialTheme.typography.bodySmall,
            )
        }
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Dynamic colors (Android 12+)", Modifier.weight(1f))
                Switch(
                    vm.preferences.dynamicColor,
                    { vm.settings(vm.preferences.copy(dynamicColor = it)) },
                )
            }
        }
        item {
            Text("Terminal font · ${vm.preferences.fontSize} sp")
            Slider(
                vm.preferences.fontSize.toFloat(),
                { vm.settings(vm.preferences.copy(fontSize = it.toInt())) },
                valueRange = 10f..24f,
                steps = 13,
            )
        }
        item {
            SettingChoice(
                "Refresh interval",
                vm.preferences.interval.toString(),
                listOf("5" to "5 seconds", "10" to "10 seconds", "30" to "30 seconds"),
            ) {
                vm.settings(vm.preferences.copy(interval = it.toInt()))
            }
        }
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("SFTP follows OSC 7 directory", Modifier.weight(1f))
                Switch(
                    vm.preferences.followDirectory,
                    { vm.settings(vm.preferences.copy(followDirectory = it)) },
                )
            }
            Text(
                "Only matching hosts are followed. Remote output cannot open links or change your clipboard.",
                style = MaterialTheme.typography.bodySmall,
            )
        }
        item {
            HorizontalDivider()
            Text("Saved commands", style = MaterialTheme.typography.titleLarge)
        }
        items(vm.macros, key = { it.id }) { macro ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(macro.name)
                    Text(macro.command, style = MaterialTheme.typography.bodySmall)
                }
                IconButton(onClick = { vm.saveMacros(vm.macros.filter { it.id != macro.id }) }) {
                    Icon(Icons.Default.DeleteOutline, "Delete command")
                }
            }
        }
        item {
            OutlinedTextField(
                newName,
                { newName = it },
                label = { Text("Command name") },
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                newCommand,
                { newCommand = it },
                label = { Text("Command") },
                modifier = Modifier.fillMaxWidth(),
            )
            TextButton(
                onClick = {
                    vm.saveMacros(vm.macros + Macro(name = newName, command = newCommand))
                    newName = ""
                    newCommand = ""
                },
                enabled = newName.isNotBlank() && newCommand.isNotBlank(),
            ) {
                Text("Save command")
            }
        }
        item {
            HorizontalDivider()
            Text("Import and trust", style = MaterialTheme.typography.titleLarge)
            OutlinedButton(
                onClick = {
                    vm.externalFileFlow = true
                    picker.launch(
                        arrayOf("application/json", "text/plain", "application/octet-stream")
                    )
                }
            ) {
                Text("Import Mac migration JSON")
            }
            Text(
                "Version 1 migration files are supported. Existing IDs are preserved; secrets go to encrypted storage. The source file is not deleted automatically.",
                style = MaterialTheme.typography.bodySmall,
            )
        }
        items(vm.servers, key = { "trust-" + it.id }) { server ->
            TextButton(onClick = { forget = server }) {
                Text("Forget fingerprint · ${server.title}")
            }
        }
        item {
            HorizontalDivider()
            Text("ModernTerm 0.2.3 · Android", style = MaterialTheme.typography.titleMedium)
            Text(
                "Android 10+ · No Google services required\nConnections close when you leave the app. No permanent background sessions.\nHarmonyOS / Mate 70: not verified on a physical device.",
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
    forget?.let { server ->
        AlertDialog(
            onDismissRequest = { forget = null },
            title = { Text("Forget saved fingerprint?") },
            text = {
                Text(
                    "Only do this after independently verifying a server key change. The next connection will ask you to verify its fingerprint again."
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        vm.forgetPin(server)
                        forget = null
                    }
                ) {
                    Text("Forget")
                }
            },
            dismissButton = { TextButton(onClick = { forget = null }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun SettingChoice(
    label: String,
    value: String,
    values: List<Pair<String, String>>,
    select: (String) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Column {
        Text(label, style = MaterialTheme.typography.labelLarge)
        Box {
            OutlinedButton(onClick = { expanded = true }, modifier = Modifier.fillMaxWidth()) {
                Text(values.find { it.first == value }?.second ?: value, Modifier.weight(1f))
                Icon(Icons.Default.ExpandMore, null)
            }
            DropdownMenu(expanded, { expanded = false }) {
                values.forEach { (id, name) ->
                    DropdownMenuItem(
                        text = { Text(name) },
                        onClick = {
                            select(id)
                            expanded = false
                        },
                    )
                }
            }
        }
    }
}
