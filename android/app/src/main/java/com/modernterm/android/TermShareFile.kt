package com.modernterm.android

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File
import java.util.UUID

object TermShareFile {
    private fun root(context: Context) = File(context.cacheDir, "downloads/term-shares")

    fun prepare(context: Context, bytes: ByteArray): Uri {
        require(
            bytes.size in 64..TermArchive.MAXIMUM &&
                bytes.copyOfRange(0, 8).contentEquals(byteArrayOf(77, 84, 69, 82, 77, 0, 13, 10))
        ) {
            "Only encrypted .term files can be shared."
        }
        cleanup(context)
        val folder = File(root(context), UUID.randomUUID().toString())
        check(folder.mkdirs()) { "Could not create a temporary share file." }
        val file = File(folder, "ModernTerm-connections.term")
        try {
            file.writeBytes(bytes)
        } catch (e: Exception) {
            folder.deleteRecursively()
            throw e
        }
        return FileProvider.getUriForFile(context, "${context.packageName}.files", file)
    }

    fun chooser(context: Context, bytes: ByteArray): Intent {
        val uri = prepare(context, bytes)
        val send =
            Intent(Intent.ACTION_SEND).apply {
                type = "application/octet-stream"
                putExtra(Intent.EXTRA_STREAM, uri)
                clipData = ClipData.newRawUri("Encrypted SSH connections", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        return Intent.createChooser(send, "Share encrypted .term file")
    }

    fun cleanup(context: Context, now: Long = System.currentTimeMillis()) {
        // Recipients may read asynchronously after the chooser returns. Retain encrypted
        // files for 24 hours, then clean only this feature's UUID-named cache folders.
        root(context).listFiles()?.forEach { folder ->
            if (
                runCatching { UUID.fromString(folder.name) }.isSuccess &&
                    now - folder.lastModified() > 24 * 60 * 60 * 1000L
            )
                folder.deleteRecursively()
        }
    }
}
