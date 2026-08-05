package com.colespringer.waxdeck

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// audio_service hosts the engine in its media service, so the base
// class comes from it. Share-sheet traffic runs both ways over the
// waxdeck/share channel: intake queues audio and text, cards go out.
class MainActivity : AudioServiceActivity() {
    private val pendingShares = ArrayDeque<Map<String, Any?>>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        captureShare(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "waxdeck/share")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumeShared" -> result.success(pendingShares.removeFirstOrNull())
                    "shareImage" -> shareImage(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    // Writes the image into the one cache directory the FileProvider
    // exposes and opens the chooser on it. The bytes are the card the
    // Dart side rendered; nothing here interprets them.
    private fun shareImage(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        val bytes = call.argument<ByteArray>("bytes")
        val fileName = call.argument<String>("fileName")
        if (bytes == null || fileName == null) {
            result.error("bad-request", "an image and a file name are required", null)
            return
        }
        try {
            val directory = File(cacheDir, SHARE_CARD_DIR).apply { mkdirs() }
            // Written and replaced under one name per card: the chooser
            // reads it while it is open, and yesterday's copy is of no
            // use to anybody once this one exists.
            val file = File(directory, File(fileName).name)
            val temp = File(directory, "${file.name}.tmp")
            temp.outputStream().use {
                it.write(bytes)
                it.fd.sync()
            }
            if (temp.length() != bytes.size.toLong()) {
                temp.delete()
                result.error("short-write", "the image could not be written whole", null)
                return
            }
            // renameTo is platform-dependent and refuses an existing
            // target on some filesystems, so a second share of the same
            // card replaces it rather than reporting a false failure.
            if (!temp.renameTo(file) && !(file.delete() && temp.renameTo(file))) {
                temp.delete()
                result.error("share-failed", "the image could not be published", null)
                return
            }
            val uri = FileProvider.getUriForFile(this, "$packageName.shares", file)
            val send = Intent(Intent.ACTION_SEND).apply {
                type = "image/png"
                putExtra(Intent.EXTRA_STREAM, uri)
                call.argument<String>("subject")?.let { putExtra(Intent.EXTRA_SUBJECT, it) }
                // The flag alone grants through the chooser on current
                // Android; clip data is what older releases and some
                // OEM builds read instead.
                clipData = ClipData.newRawUri(null, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(send, null))
            result.success(null)
        } catch (e: Exception) {
            result.error("share-failed", e.message, null)
        }
    }

    private fun captureShare(intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_SEND -> {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (intent.type == "text/plain" && text != null) {
                    pendingShares.addLast(mapOf("type" to "url", "url" to text.trim()))
                    return
                }
                @Suppress("DEPRECATION")
                val stream = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) ?: return
                val file = copyToCache(stream) ?: return
                pendingShares.addLast(mapOf("type" to "files", "files" to listOf(file)))
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                @Suppress("DEPRECATION")
                val streams =
                    intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: return
                val files = streams.mapNotNull { copyToCache(it) }
                if (files.isNotEmpty()) {
                    pendingShares.addLast(mapOf("type" to "files", "files" to files))
                }
            }
        }
    }

    // Copies one shared content stream into cacheDir so the Dart side
    // reads a plain file path with the app's own permissions.
    private fun copyToCache(uri: Uri): Map<String, String>? {
        return try {
            val name = displayName(uri) ?: "shared-audio"
            val file = File.createTempFile("share-", "-$name", cacheDir)
            val input = contentResolver.openInputStream(uri) ?: return null
            input.use { source -> file.outputStream().use { source.copyTo(it) } }
            mapOf("path" to file.absolutePath, "name" to name)
        } catch (_: Exception) {
            null
        }
    }

    private fun displayName(uri: Uri): String? {
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && cursor.moveToFirst()) return cursor.getString(index)
        }
        return uri.lastPathSegment
    }

    private companion object {
        // Must match res/xml/file_paths.xml, which is what makes this
        // directory - and only this one - readable to a receiver.
        const val SHARE_CARD_DIR = "share-cards"
    }
}
