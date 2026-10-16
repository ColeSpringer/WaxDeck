package api

import (
	"net/http"
	"os"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/mp3join"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// serveJoinedMP3 streams a book whose parts are all MP3 at one rate and
// one channel count as one stream, on a server without the engine: each
// part's frames as they are, its tags and length frame left out, nothing
// encoded. It answers through the shell the engine's joined stream does
// (mp3join.Response): no length, no range but the whole, and a part lost
// once audio has gone out (gone, short of its length, holding no frame,
// or not the book's shape) breaks the transfer off rather than ending it
// as the book's end.
func (s *Server) serveJoinedMP3(w http.ResponseWriter, r *http.Request, pid, mt string) {
	// The engine joins books itself; a stream token opens this route only
	// while it is away.
	purposes := []string{}
	if !s.bridge.Up() {
		purposes = append(purposes, auth.PurposeStream)
	}
	if _, _, ok := s.verifiedMedia(w, r, mt, auth.MediaWant{Purposes: purposes, PID: pid, Shape: service.JoinShape}); !ok {
		return
	}
	parts, err := s.svc.StreamParts(r.Context(), pid)
	if err != nil {
		refuseJoin(w, err)
		return
	}
	if !service.JoinableMP3(parts) {
		writeError(w, http.StatusNotFound, "not-found", "no such download")
		return
	}
	if mp3join.RangeRefused(r) {
		w.Header().Set("Accept-Ranges", "none")
		writeError(w, http.StatusRequestedRangeNotSatisfiable, "invalid-request",
			"a joined stream is not byte-addressable; play it from the start")
		return
	}
	first, err := os.Open(parts[0].Src.Path)
	if err != nil {
		writeError(w, http.StatusNotFound, "not-found", "no such download")
		return
	}
	// Every part at the book's one shape: a part of another is refused
	// before a byte of it goes out.
	out := mp3join.NewResponse(w, r, mp3join.Shape{Rate: parts[0].Rate, Channels: parts[0].Channels}, func(part string, err error) {
		s.log.Warn("joined book broken off at a part", "pid", pid, "part", part, "err", err)
	})
	if !out.Open() {
		first.Close()
		return
	}
	for i, p := range parts {
		f := first
		if i > 0 {
			if f, err = os.Open(p.Src.Path); err != nil {
				out.BreakOff(p.FilePID, err)
			}
		}
		// A file cut short on disk reads to a clean end: its length is the
		// only sign, as for the engine's encodes.
		func() {
			defer f.Close()
			out.CopyPart(p.FilePID, f, p.Src.DurationMS, 0)
		}()
	}
}

// refuseJoin answers a book the join could not lay out, as ServeDownload
// answers a source it could not resolve: only a book that is gone is not
// found, since that one tells the client to stop asking.
func refuseJoin(w http.ResponseWriter, err error) {
	switch service.KindOf(err) {
	case service.KindNotFound, service.KindInvalid:
		writeError(w, http.StatusNotFound, "not-found", "no such download")
	case service.KindMaintenance:
		writeError(w, http.StatusServiceUnavailable, "catalog-maintenance", "the catalog is in maintenance; retry shortly")
	default:
		writeError(w, http.StatusInternalServerError, "internal", "resolving the book failed")
	}
}
