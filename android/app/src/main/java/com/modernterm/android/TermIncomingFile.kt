package com.modernterm.android

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns

data class TermIncomingFile(val bytes: ByteArray, val name: String)

object TermIncomingFiles {
    @Suppress("DEPRECATION")
    fun uris(intent: Intent): List<Uri> {
        val result =
            when (intent.action) {
                    Intent.ACTION_VIEW -> listOfNotNull(intent.data)
                    Intent.ACTION_SEND ->
                        listOfNotNull(intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
                    Intent.ACTION_SEND_MULTIPLE ->
                        intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.toList()
                            ?: emptyList()
                    else -> return emptyList()
                }
                .ifEmpty {
                    intent.clipData?.let { clip ->
                        (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
                    } ?: emptyList()
                }
                .distinct()
        require(result.isNotEmpty() && result.size <= 20) { "Choose 1–20 .term files." }
        require(result.all { it.scheme == "content" }) {
            "Open a local attachment using a content URI."
        }
        return result
    }

    fun read(context: Context, uris: List<Uri>): List<TermIncomingFile> {
        require(uris.size in 1..20) { "Choose 1–20 .term files." }
        var total = 0
        return uris.map { uri ->
            require(uri.scheme == "content") { "Open a local attachment using a content URI." }
            val bytes =
                context.contentResolver.openInputStream(uri)?.use { input ->
                    val output = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        total += n
                        require(total <= TermArchive.MAXIMUM) { "Selected files exceed 16 MiB." }
                        output.write(buffer, 0, n)
                    }
                    output.toByteArray()
                } ?: error("Could not read attachment.")
            require(
                bytes.size >= 64 &&
                    bytes
                        .copyOfRange(0, 8)
                        .contentEquals(byteArrayOf(77, 84, 69, 82, 77, 0, 13, 10))
            ) {
                "This is not an encrypted .term file."
            }
            val name =
                context.contentResolver
                    .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                    ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
                    ?: "Encrypted connections.term"
            TermIncomingFile(bytes, name)
        }
    }
}
