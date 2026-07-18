package api

import (
	"mime"
	"net/http"
	"os"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// ServeDownload serves an item's original bytes for offline use:
// media-token authenticated (query string, like /media/stream, so
// download managers that cannot send headers work), ranged and
// resumable via http.ServeContent, with the file's strong validator as
// its ETag. The id parameter pins the exact bytes the URL was minted
// for; a file rewritten since answers the stream-stale error and the
// client re-requests download-info.
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
	if _, err := s.media.Verify(q.Get("mt"), pid); err != nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "missing, expired, or wrong media token")
		return
	}
	f, err := s.svc.DownloadSource(r.Context(), pid, q.Get("f"))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound, service.KindInvalid:
			writeError(w, http.StatusNotFound, "not-found", "no such download")
		case service.KindMaintenance:
			writeError(w, http.StatusServiceUnavailable, "catalog-maintenance", "the catalog is in maintenance; retry shortly")
		default:
			writeError(w, http.StatusInternalServerError, "internal", "resolving download failed")
		}
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
	w.Header().Set("Content-Disposition", mime.FormatMediaType("attachment", map[string]string{"filename": f.FileName}))
	// The modtime drives Last-Modified and If-Range; it is the same
	// instant the ETag pins.
	http.ServeContent(w, r, "", time.Unix(0, f.MTimeNS), file)
}
