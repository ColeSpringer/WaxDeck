package com.colespringer.waxdeck

import android.content.ClipData
import android.content.Intent
import android.content.res.AssetFileDescriptor
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.Executors

// audio_service hosts the engine in its media service, so the base
// class comes from it. Share-sheet traffic runs both ways over the
// waxdeck/share channel: intake queues audio and text, cards go out.
// Folder uploads run over waxdeck/saf: one pickTree call opens the
// system tree picker, walks the tree, and answers every file under it;
// readChunk then serves the transfer's windowed reads. The channel
// stays a capability grant - the extension filter, ordering, and the
// transfer are Dart-side.
class MainActivity : AudioServiceActivity() {
    private val pendingShares = ArrayDeque<Map<String, Any?>>()
    private val mainHandler = Handler(Looper.getMainLooper())

    // One worker owns every document read, and with it the one cached
    // stream sequential transfers reuse; both die in onDestroy.
    private val safReads = Executors.newSingleThreadExecutor()
    private var cachedRead: CachedRead? = null

    // An open document stream and how far into it the reads have come.
    // Touched only on the safReads worker.
    private class CachedRead(
        val uri: String,
        val stream: InputStream,
        var offset: Long,
    )

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "waxdeck/saf")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickTree" -> pickTree(result)
                    "readChunk" -> readChunk(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickTree(result: MethodChannel.Result) {
        if (pendingTree != null) {
            result.error("busy", "a folder pick is already open", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, PICK_TREE_REQUEST)
        } catch (e: Exception) {
            // No documents picker on this ROM. Answered before
            // pendingTree is set, so the next attempt is not refused
            // as busy by a pick that never opened.
            result.error("no-picker", e.message, null)
            return
        }
        pendingTree = result
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_TREE_REQUEST) return
        val result = pendingTree ?: return
        pendingTree = null
        val tree = data?.data
        if (resultCode != RESULT_OK || tree == null) {
            result.success(null)
            return
        }
        // Off the main thread: a big tree is one query per directory.
        // Throwable, not Exception: a pathological tree ends in an
        // Error, and a worker dying silently would leave the Dart
        // future waiting forever.
        Thread {
            val answer = try {
                enumerateTree(tree)
            } catch (e: Throwable) {
                mainHandler.post { result.error("enumerate-failed", e.message, null) }
                return@Thread
            }
            mainHandler.post { result.success(answer) }
        }.start()
    }

    // Lists every file under the picked tree: name, size, and the
    // directory path rooted at the tree's own display name - the
    // relativeDir shape the desktop and web walks build. Iterative
    // with a visited set: a provider may hand back an ancestor as a
    // child (shortcut documents), and recursing there would loop until
    // the process died.
    private fun enumerateTree(tree: Uri): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        val rootId = DocumentsContract.getTreeDocumentId(tree)
        val visited = hashSetOf(rootId)
        val stack = ArrayDeque<Pair<String, String>>()
        stack.addLast(rootId to treeDisplayName(tree))
        while (stack.isNotEmpty()) {
            val (documentId, dir) = stack.removeLast()
            val children =
                DocumentsContract.buildChildDocumentsUriUsingTree(tree, documentId)
            contentResolver.query(
                children,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                    DocumentsContract.Document.COLUMN_SIZE,
                ),
                null,
                null,
                null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val id = cursor.getString(0) ?: continue
                    val name = cursor.getString(1) ?: continue
                    if (cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                        if (visited.add(id)) stack.addLast(id to "$dir/$name")
                        continue
                    }
                    // The upload session declares its size up front. A
                    // provider whose listing reports none gets one
                    // more chance through the opened descriptor;
                    // still unknown crosses as -1, which the Dart side
                    // counts rather than dropping - a whole folder of
                    // these must not read as an empty pick.
                    val size =
                        if (cursor.isNull(3)) sizeViaDescriptor(tree, id)
                        else cursor.getLong(3)
                    out.add(
                        mapOf(
                            "name" to name,
                            "size" to size,
                            "relativeDir" to dir,
                            "uri" to DocumentsContract
                                .buildDocumentUriUsingTree(tree, id).toString(),
                        ),
                    )
                }
            }
        }
        return out
    }

    // The size a listing did not carry, asked of the opened descriptor;
    // -1 where even that does not know.
    private fun sizeViaDescriptor(tree: Uri, id: String): Long = try {
        val uri = DocumentsContract.buildDocumentUriUsingTree(tree, id)
        contentResolver.openAssetFileDescriptor(uri, "r")?.use { afd ->
            if (afd.length == AssetFileDescriptor.UNKNOWN_LENGTH) -1L else afd.length
        } ?: -1L
    } catch (_: Exception) {
        -1L
    }

    private fun treeDisplayName(tree: Uri): String {
        val doc = DocumentsContract.buildDocumentUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        contentResolver.query(
            doc,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0)?.let { return it }
        }
        // Storage document ids read "primary:Music"; the leaf is the name.
        return DocumentsContract.getTreeDocumentId(tree)
            .substringAfterLast(':').substringAfterLast('/').ifEmpty { "folder" }
    }

    // One [start, start+length) window of a document, served from the
    // one cached stream: a transfer reads sequentially, so the next
    // window almost always starts where the last ended and costs no
    // re-open - without the cache a non-seekable provider pays the
    // whole prefix again per window, which is quadratic in file size.
    // A window elsewhere (a retry) reopens and walks forward. Exactly
    // one reply leaves per call, decided after the read finishes:
    // posting from inside the stream's own scope could reply twice
    // when close() throws after a success already went out - a
    // second reply crashes the messenger. A short or empty answer
    // means the document ended early.
    private fun readChunk(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        val start = call.argument<Number>("start")?.toLong()
        val length = call.argument<Number>("length")?.toInt()
        if (uri == null || start == null || length == null || start < 0 || length <= 0) {
            result.error("bad-request", "uri, start, and length are required", null)
            return
        }
        safReads.execute {
            val answer = try {
                readWindow(uri, start, length)
            } catch (e: Throwable) {
                dropCachedRead()
                mainHandler.post { result.error("read-failed", e.message, null) }
                return@execute
            }
            mainHandler.post { result.success(answer) }
        }
    }

    // Runs on safReads only, which is what makes cachedRead safe to
    // touch without locks.
    private fun readWindow(uri: String, start: Long, length: Int): ByteArray {
        var read = cachedRead
        if (read == null || read.uri != uri || read.offset != start) {
            dropCachedRead()
            val stream = contentResolver.openInputStream(Uri.parse(uri))
                ?: throw IllegalStateException("the document could not be opened")
            read = CachedRead(uri, stream, 0L)
            cachedRead = read
            if (!advance(read, start)) {
                // Shorter than the asked offset: the document shrank.
                dropCachedRead()
                return ByteArray(0)
            }
        }
        val buffer = ByteArray(length)
        var got = 0
        while (got < length) {
            val n = read.stream.read(buffer, got, length - got)
            if (n < 0) break
            got += n
        }
        read.offset += got
        // A short read is the end; a stream at EOF serves nobody.
        if (got < length) dropCachedRead()
        return if (got == length) buffer else buffer.copyOf(got)
    }

    // Walks the stream forward to [to]; false when it ended first.
    // skip() lseeks where the provider is file-backed; pipe-backed
    // streams throw (ESPIPE) or answer 0, and reading into a scratch
    // buffer is the fallback either way.
    private fun advance(read: CachedRead, to: Long): Boolean {
        var scratch: ByteArray? = null
        while (read.offset < to) {
            val remaining = to - read.offset
            val skipped = try {
                read.stream.skip(remaining)
            } catch (_: IOException) {
                0L
            }
            if (skipped > 0) {
                read.offset += skipped
                continue
            }
            val buf = scratch ?: ByteArray(64 * 1024).also { scratch = it }
            val n = read.stream.read(buf, 0, minOf(remaining, buf.size.toLong()).toInt())
            if (n < 0) return false
            read.offset += n
        }
        return true
    }

    private fun dropCachedRead() {
        val read = cachedRead ?: return
        cachedRead = null
        try {
            read.stream.close()
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        // The worker owns the cached stream; both go with the activity.
        safReads.execute { dropCachedRead() }
        safReads.shutdown()
        super.onDestroy()
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

        // Arbitrary but stable; plugin request codes route through the
        // engine's own registry, so only this activity sees it.
        const val PICK_TREE_REQUEST = 51422

        // In the companion, not the instance: Android may recreate
        // this activity while the system picker is foreground, and the
        // engine - with it the Dart future - survives in
        // audio_service's cache. The recreated instance's
        // onActivityResult has to find the pending reply, or that
        // future never completes.
        var pendingTree: MethodChannel.Result? = null
    }
}
