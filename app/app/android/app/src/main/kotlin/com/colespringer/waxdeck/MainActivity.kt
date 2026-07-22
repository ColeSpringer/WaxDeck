package com.colespringer.waxdeck

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// audio_service hosts the Flutter engine inside its media service so
// playback survives the activity; the activity base class comes from it.
//
// On top of that this activity receives share-sheet intents: shared
// audio streams are copied into the app cache (content: URIs die with
// the sending activity), shared text rides through as a URL, and the
// Dart side drains the queue over the waxdeck/share channel on start
// and resume.
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
                    else -> result.notImplemented()
                }
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
}
