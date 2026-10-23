package api

import (
	"context"
	"mime"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"time"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// ServeDownload serves an item's original bytes for offline use:
// media-token authenticated (query string, like /media/stream, so
// download managers that cannot send headers work), ranged and
// resumable via http.ServeContent, with the file's strong validator as
// its ETag. The id parameter pins the exact bytes the URL was minted
// for; a file rewritten since answers the stream-stale error and the
// client re-requests download-info.
//
// A download token opens it. So does a stream token for the original's
// bytes, served inline rather than as an attachment (see
// streamOpensDownload).
func (s *Server) ServeDownload(w http.ResponseWriter, r *http.Request) {
	if s.media == nil {
		writeError(w, http.StatusNotImplemented, "internal", "downloads are not configured on this server")
		return
	}
	q := r.URL.Query()
	pid := q.Get("pid")
	if pid == "" {
		writeError(w, http.StatusBadRequest, "invalid-request", "pid is required")
		return
	}
	if q.Get(service.JoinKey) != "" {
		s.serveJoinedMP3(w, r, pid, q.Get("mt"))
		return
	}
	// A token with no stream parameters bound: a download's, or a stream's
	// the direct play-info minted. Failing that, a stream's bound to the
	// parameters its URL carries, as one redirected here arrives.
	mt := q.Get("mt")
	bound := url.Values{}
	claims, err := s.media.Verify(mt, auth.MediaWant{Purposes: []string{auth.PurposeDownload, auth.PurposeStream}, PID: pid})
	if err != nil {
		bound = q
		claims, err = s.media.Verify(mt, auth.MediaWant{Purposes: []string{auth.PurposeStream}, PID: pid, Shape: flow.StreamShape(q)})
	}
	if err != nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "missing, expired, or wrong media token")
		return
	}
	if _, ok := s.authorizeMediaFor(w, r, claims); !ok {
		return
	}
	var f service.DownloadFile
	if claims.Purpose == auth.PurposeStream {
		// One lookup answers both what the token streams and the file.
		var src flow.Source
		src, f, err = s.sources.StreamDownloadSource(r.Context(), pid, q.Get("f"))
		if err != nil {
			writeDownloadSourceError(w, err)
			return
		}
		if !s.streamOpensDownload(src, bound) {
			writeError(w, http.StatusUnauthorized, "unauthenticated", "missing, expired, or wrong media token")
			return
		}
	} else if f, err = s.sources.DownloadSource(r.Context(), pid, q.Get("f")); err != nil {
		writeDownloadSourceError(w, err)
		return
	}
	if id := q.Get("id"); id != "" && id != f.ETag {
		writeError(w, http.StatusGone, "stream-stale", "the file changed on disk; re-request download-info")
		return
	}

	file, err := os.Open(f.Path)
	if err != nil {
		writeError(w, http.StatusNotFound, "not-found", "no such download")
		return
	}
	defer file.Close()

	w.Header().Set("Content-Type", f.MimeType)
	w.Header().Set("ETag", `"`+f.ETag+`"`)
	disposition := "attachment"
	if claims.Purpose == auth.PurposeStream {
		disposition = "inline"
	}
	w.Header().Set("Content-Disposition", mime.FormatMediaType(disposition, map[string]string{"filename": f.FileName}))
	// The modtime drives Last-Modified and If-Range; it is the same
	// instant the ETag pins.
	http.ServeContent(w, r, "", time.Unix(0, f.MTimeNS), file)
}

// downloadSources is the lookup the download route serves a file from.
type downloadSources interface {
	StreamDownloadSource(ctx context.Context, apiItemPID, filePID string) (flow.Source, service.DownloadFile, error)
	DownloadSource(ctx context.Context, apiItemPID, filePID string) (service.DownloadFile, error)
}

// streamOpensDownload reports whether a stream token bound to the stream
// parameters bound opens the download route for the source src. One for
// the original's bytes does, whatever the engine is doing: the stream
// route passes the same bytes through, and a URL minted while the engine
// was away (a device's whole queue, perhaps) has to keep working once it
// is back. One for what only the engine makes never does, nor one for a
// window of a larger file while the engine answers, since that token may
// be the engine's cut and this route would hand over the whole file.
// Without the engine a window plays directly, whole with its span.
func (s *Server) streamOpensDownload(src flow.Source, bound url.Values) bool {
	return flow.OriginalBytes(bound, src) && (!src.Virtual || !s.bridge.Up())
}

// writeDownloadSourceError answers a download whose file could not be
// resolved.
func writeDownloadSourceError(w http.ResponseWriter, err error) {
	switch service.KindOf(err) {
	case service.KindNotFound, service.KindInvalid, service.KindConflict:
		writeError(w, http.StatusNotFound, "not-found", "no such download")
	case service.KindMaintenance:
		writeError(w, http.StatusServiceUnavailable, "catalog-maintenance", "the catalog is in maintenance; retry shortly")
	default:
		writeError(w, http.StatusInternalServerError, "internal", "resolving download failed")
	}
}

// Routes served outside the generated router but inside its base path.
// The generated strict handler still declares these operations (clients
// generate against them) and its method for one is unreachable, so the
// pattern lives here rather than being retyped at each mux: an exact
// pattern beats the /api/v1/ prefix, and every mux that registers the
// prefix has to register these beside it.
//
// The base path is spelled out because it is a wiring constant, fixed at
// StdHTTPServerOptions.BaseURL where the generated handler is built.
const (
	// BackupArchiveRoute serves ranged backup archives (ServeBackupArchive).
	BackupArchiveRoute = "GET /api/v1/admin/backups/{backupId}/archive"
	// TaskEventsRoute is the tool-task SSE stream. It stays on the
	// generated handler; the pattern exists so the mux can class it apart
	// from ordinary API requests, since it is open for as long as someone
	// is watching a task.
	TaskEventsRoute = "GET /api/v1/tools/tasks/{taskId}/events"
)

// ServeBackupArchive serves a backup archive, ranged and resumable via
// http.ServeContent. It lives outside the generated router for the same
// reason the item download does: the strict-handler shape hands back one
// body and streams it whole, so an interrupted multi-gigabyte download
// re-fetches from zero. Registration is the exact path on the outer mux,
// which wins over the generated router's /api/v1/ prefix; the operation
// stays declared in the spec, so clients still generate against it.
//
// Authentication is the same session middleware the rest of /api/v1
// runs behind, and administrators only, exactly as the generated
// operation enforced.
//
// No locking and no half-written-file guard: buildArchive writes the
// zip beside its final name and renames it in, so a row that lists at
// all names a complete file.
func (s *Server) ServeBackupArchive(w http.ResponseWriter, r *http.Request) {
	p, ok := principalFromContext(r.Context())
	if !ok || !p.IsAdmin() {
		writeError(w, http.StatusForbidden, "forbidden", "administrators only")
		return
	}
	id := r.PathValue("backupId")
	path, err := s.backups.ArchivePath(r.Context(), id)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound:
			writeError(w, http.StatusNotFound, "not-found", "no backup with id "+id)
		case service.KindConflict:
			// A running or failed backup has no archive yet. The spec
			// declares this code; the generated shape answered it as an
			// unhandled internal error.
			writeError(w, http.StatusConflict, "conflict", err.Error())
		default:
			writeError(w, http.StatusInternalServerError, "internal", "resolving the backup archive failed")
		}
		return
	}

	file, err := os.Open(path)
	if err != nil {
		writeError(w, http.StatusNotFound, "not-found", "the archive file is missing")
		return
	}
	defer file.Close()
	st, err := file.Stat()
	if err != nil {
		writeError(w, http.StatusInternalServerError, "internal", "reading the backup archive failed")
		return
	}

	w.Header().Set("Content-Type", "application/zip")
	w.Header().Set("Content-Disposition",
		mime.FormatMediaType("attachment", map[string]string{"filename": filepath.Base(path)}))
	// An archive never changes after it is renamed into place, so the
	// modtime is a sound validator for Last-Modified and If-Range.
	http.ServeContent(w, r, "", st.ModTime(), file)
}
