package com.colespringer.waxdeck

import android.content.ClipData
import android.content.ContentResolver
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
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

// audio_service hosts the engine in its media service, so the base
// class comes from it. Share-sheet traffic runs both ways over the
// waxdeck/share channel: intake queues audio and text, cards go out.
// Folder uploads run over waxdeck/saf, pulled a page at a time:
// pickTree opens the system tree picker and answers the granted root,
// nextTreeBatch advances the walk by a bounded number of entries,
// disposeTreeWalk drops one nobody finished, and readChunk serves the
// transfer's windowed reads. Pull rather than push, so the caller sets
// the pace and nothing - here, in the messenger's encode, or Dart-side
// - ever holds a whole tree. The channel stays a capability grant: the
// extension filter, ordering, and the transfer are Dart-side.
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
                    "nextTreeBatch" -> nextTreeBatch(call, result)
                    "disposeTreeWalk" -> {
                        // Naming a walk that is not the current one is
                        // not a failure - it is a superseded loop
                        // tidying up after one that is already gone.
                        walkFor(call)?.let { dropTreeWalk(it) }
                        result.success(null)
                    }
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
        // A grant is what supersedes the last walk, not merely
        // opening a picker: a second pick the user cancels leaves the
        // first one's walk alone.
        dropTreeWalk()
        // The walk resolves documents through the application context
        // and lives in the companion: Android may recreate this
        // activity mid-walk while the engine - and with it the Dart
        // loop pulling batches - lives on in audio_service's cache.
        val walk = TreeWalk(applicationContext.contentResolver, tree, nextWalkId())
        treeWalk = walk
        // Off the main thread from the first query: naming the root is
        // already one round trip to the provider. Throwable, not
        // Exception: a pathological tree ends in an Error, and a worker
        // dying silently would leave the Dart future waiting forever.
        safWalks.execute {
            val root = try {
                walk.start()
            } catch (e: Throwable) {
                mainHandler.post {
                    dropTreeWalk(walk)
                    result.error("enumerate-failed", e.message, null)
                }
                return@execute
            }
            // The walk's id goes back with it: every later call names
            // the walk it belongs to, so a superseded loop can neither
            // consume a newer walk's entries nor dispose it.
            mainHandler.post {
                result.success(mapOf("root" to root, "walk" to walk.id))
            }
        }
    }

    // Advances the open walk by at most `max` entries and answers them
    // with whether the tree is finished. A failure mid-walk drops the
    // walk: the tree is half-read, and half a folder is not a pick.
    private fun nextTreeBatch(call: MethodCall, result: MethodChannel.Result) {
        val walk = walkFor(call)
        if (walk == null) {
            result.error("no-walk", "no folder pick is open", null)
            return
        }
        val max = (call.argument<Number>("max")?.toInt() ?: BATCH_LIMIT)
            .coerceIn(1, BATCH_LIMIT)
        safWalks.execute {
            val page = try {
                walk.next(max)
            } catch (e: Throwable) {
                mainHandler.post {
                    dropTreeWalk(walk)
                    result.error("enumerate-failed", e.message, null)
                }
                return@execute
            }
            mainHandler.post {
                // A finished walk frees itself; disposeTreeWalk is for
                // the caller that stopped early.
                if (page.done) dropTreeWalk(walk)
                result.success(mapOf("entries" to page.entries, "done" to page.done))
            }
        }
    }

    // The open walk, when the caller named it. A call naming another
    // one comes from a loop a newer pick superseded, and answering it
    // would hand the new walk's entries to the wrong caller.
    private fun walkFor(call: MethodCall): TreeWalk? {
        val walk = treeWalk ?: return null
        return if (call.argument<String>("walk") == walk.id) walk else null
    }

    // Drops the walk; what is left of it is garbage, since the worker
    // is the process's and not the walk's. Main thread only, which is
    // where every channel call and every posted reply runs.
    //
    // A reply posted from the worker names the walk it came from: a
    // newer pick may have superseded that one while the batch was in
    // flight, and the old answer must not take the new walk down.
    private fun dropTreeWalk(only: TreeWalk? = null) {
        val walk = treeWalk ?: return
        if (only != null && only !== walk) return
        treeWalk = null
    }

    // One folder pick's traversal, resumable: the stack, the visited
    // set, and the current directory's listing that enumerateTree used
    // to hold in locals live here instead, so a batch can stop
    // anywhere and the next call picks up where it left off.
    //
    // Every field is touched on [safWalks] and nowhere else, which is
    // what makes them safe without locks - the discipline cachedRead
    // keeps on safReads. The resolver comes from the application
    // context because the walk outlives any one activity instance, and
    // [id] is how a caller says which walk it means.
    private class TreeWalk(
        private val resolver: ContentResolver,
        private val tree: Uri,
        val id: String,
    ) {
        // Directories still to list, each with its path relative to the
        // tree root, and the ids already queued: a provider may hand
        // back an ancestor as a child (shortcut documents), and
        // following one would loop until the process died.
        private val stack = ArrayDeque<Pair<String, String>>()
        private val visited = hashSetOf<String>()

        // The directory being emitted, listed whole and handed out a
        // page at a time: what one batch holds is a page, but what the
        // walk holds is one directory's rows, not the tree's. That is
        // the bound a cursor held open across channel calls would trade
        // for a cursor a provider can invalidate under it, and one
        // directory is small beside the pick the Dart side is building
        // anyway.
        private val pending = ArrayDeque<Row>()

        // A listed file before it is worth a document URI or a
        // descriptor open, both of which the emitting batch pays for.
        private class Row(
            val id: String,
            val name: String,
            val dir: String,
            val size: Long?,
        )

        class Page(val entries: List<Map<String, Any>>, val done: Boolean)

        // Seeds the walk at the tree root and answers its display name,
        // which is the directory every entry hangs off - the Dart side
        // prefixes it, so it does not ride every entry across the
        // channel.
        fun start(): String {
            val rootId = DocumentsContract.getTreeDocumentId(tree)
            visited.add(rootId)
            stack.addLast(rootId to "")
            return treeDisplayName()
        }

        fun next(max: Int): Page {
            val out = ArrayList<Map<String, Any>>()
            // Directories are budgeted as well as entries: a page that
            // fills from one listing is the common case, but a run of
            // empty directories would otherwise walk the whole tree
            // inside one batch and answer nothing.
            var listed = 0
            while (out.size < max && listed < max) {
                val row = pending.removeFirstOrNull()
                if (row == null) {
                    val dir = stack.removeLastOrNull() ?: break
                    list(dir)
                    listed++
                    continue
                }
                out.add(
                    mapOf(
                        "name" to row.name,
                        // The upload session declares its size up
                        // front. A provider whose listing reports none
                        // gets one more chance through the opened
                        // descriptor; still unknown crosses as -1,
                        // which the Dart side counts rather than
                        // dropping - a whole folder of these must not
                        // read as an empty pick. Paid here rather than
                        // while listing, so a directory of them costs
                        // one open per emitted entry instead of a batch
                        // that stalls before it answers anything.
                        "size" to (row.size ?: sizeViaDescriptor(row.id)),
                        "relativeDir" to row.dir,
                        "uri" to DocumentsContract
                            .buildDocumentUriUsingTree(tree, row.id).toString(),
                    ),
                )
            }
            return Page(out, pending.isEmpty() && stack.isEmpty())
        }

        // Lists one directory: subdirectories onto the stack, files
        // into the page queue.
        private fun list(entry: Pair<String, String>) {
            val (documentId, dir) = entry
            val children =
                DocumentsContract.buildChildDocumentsUriUsingTree(tree, documentId)
            // A null cursor is a provider that failed, not a directory
            // with nothing in it - and the difference matters, because
            // swallowing it answers `done` over a tree that was never
            // finished. Half a folder is not a pick.
            val cursor = resolver.query(
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
            ) ?: throw IllegalStateException("the folder could not be listed")
            cursor.use {
                while (cursor.moveToNext()) {
                    val id = cursor.getString(0) ?: continue
                    val name = cursor.getString(1) ?: continue
                    if (cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                        val path = if (dir.isEmpty()) name else "$dir/$name"
                        if (visited.add(id)) stack.addLast(id to path)
                        continue
                    }
                    val size = if (cursor.isNull(3)) null else cursor.getLong(3)
                    pending.addLast(Row(id, name, dir, size))
                }
            }
        }

        // The size a listing did not carry, asked of the opened
        // descriptor; -1 where even that does not know.
        private fun sizeViaDescriptor(id: String): Long = try {
            val uri = DocumentsContract.buildDocumentUriUsingTree(tree, id)
            resolver.openAssetFileDescriptor(uri, "r")?.use { afd ->
                if (afd.length == AssetFileDescriptor.UNKNOWN_LENGTH) -1L else afd.length
            } ?: -1L
        } catch (_: Exception) {
            -1L
        }

        private fun treeDisplayName(): String {
            val doc = DocumentsContract.buildDocumentUriUsingTree(
                tree,
                DocumentsContract.getTreeDocumentId(tree),
            )
            resolver.query(
                doc,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0)?.let { return it }
            }
            // Storage document ids read "primary:Music"; the leaf is
            // the name.
            return DocumentsContract.getTreeDocumentId(tree)
                .substringAfterLast(':').substringAfterLast('/').ifEmpty { "folder" }
        }
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
        try {
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
        } catch (_: RejectedExecutionException) {
            // The activity that owned this reader is gone. Answered
            // rather than dropped: a call that never replies leaves the
            // transfer waiting for a window that is never coming.
            result.error("read-failed", "the document reader is closed", null)
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

        // Here for the same reason: the walk outlives the activity it
        // was picked in, so onDestroy leaves it alone and the Dart
        // loop - or the next grant - is what ends it.
        var treeWalk: TreeWalk? = null

        private var walkSerial = 0L

        fun nextWalkId(): String = "walk-${++walkSerial}"

        // One walk worker for the whole process, made on first use and
        // never shut down. Shared rather than per-walk so an abandoned
        // walk leaks nothing but its own state, and outside the
        // activity because a walk outlives the instance that started
        // it. Tasks are serialized, so a stale batch finishes before a
        // newer walk's begins and each still touches only its own
        // state.
        val safWalks: ExecutorService by lazy {
            Executors.newSingleThreadExecutor { runnable ->
                Thread(runnable, "wax-saf-walk").apply { isDaemon = true }
            }
        }

        // Both the size a batch answers when the caller names none and
        // the ceiling on what it will answer. One number, because the
        // ceiling exists to bound the main-thread encode and a bound
        // ten times the size anyone asks for bounds nothing.
        const val BATCH_LIMIT = 500
    }
}
