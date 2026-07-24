package subsonic

import (
	"net/http"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// Sonic discovery on the compatibility surface: the classic
// getSimilarSongs pair plus the sonicSimilarity OpenSubsonic extension
// (getSonicSimilarTracks and findSonicPath). The classic views accept
// a song, artist, or album id and degrade to metadata heuristics; the
// extension views are the explicitly sonic surface third-party clients
// gate features on.

func (h *Handler) getSimilarSongs(w http.ResponseWriter, r *http.Request, uc *service.UserCtx, element string) {
	id := r.Form.Get("id")
	if id == "" {
		h.fail(w, r, 10, "missing id")
		return
	}
	count := clampCount(formInt(r, "count", 50))
	seedPID, ok, err := h.similarSeed(r, uc, id)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	if !ok {
		h.fail(w, r, 70, "no such id")
		return
	}
	res, err := h.svc.SimilarTracksFor(r.Context(), uc, seedPID, count)
	if err != nil {
		h.failFromService(w, r, err, "finding similar songs failed")
		return
	}
	list, err := h.summariesToSongs(r, uc, res.Items)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	if element == "similarSongs2" {
		h.ok(w, r, envelope{SimilarSongs2: list})
		return
	}
	h.ok(w, r, envelope{SimilarSongs: list})
}

// similarSeed resolves a Subsonic id (song pid, artist id, or album
// id, in either identifier scheme) to a seed track pid. An index-read failure is an
// error, distinct from an unknown id.
func (h *Handler) similarSeed(r *http.Request, uc *service.UserCtx, id string) (string, bool, error) {
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		return "", false, err
	}
	if tr := idx.trackByPID[id]; tr != nil {
		return tr.PID, true, nil
	}
	if al := idx.findAlbum(id); al != nil {
		if len(al.tracks) > 0 {
			return al.tracks[0].PID, true, nil
		}
		return "", false, nil
	}
	if a := idx.findArtist(id); a != nil && len(a.albums) > 0 && len(a.albums[0].tracks) > 0 {
		return a.albums[0].tracks[0].PID, true, nil
	}
	return "", false, nil
}

func (h *Handler) getSonicSimilarTracks(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	id := r.Form.Get("id")
	if id == "" {
		h.fail(w, r, 10, "missing id")
		return
	}
	count := clampCount(formInt(r, "count", 50))
	res, err := h.svc.SimilarTracksFor(r.Context(), uc, id, count)
	if err != nil {
		h.failFromService(w, r, err, "finding sonic similar tracks failed")
		return
	}
	if res.Basis != service.BasisSonic {
		// The extension promises sonic answers; without embedding
		// coverage the honest response is empty, not a metadata guess
		// (clients fall back to getSimilarSongs themselves).
		h.ok(w, r, envelope{SonicSimilarTracks: &songList{Songs: []child{}}})
		return
	}
	list, err := h.summariesToSongs(r, uc, res.Items)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	h.ok(w, r, envelope{SonicSimilarTracks: list})
}

func (h *Handler) findSonicPath(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	from, to := r.Form.Get("fromId"), r.Form.Get("toId")
	if from == "" || to == "" {
		h.fail(w, r, 10, "missing fromId or toId")
		return
	}
	length := formInt(r, "length", 12)
	if length < 3 {
		length = 3
	}
	if length > 50 {
		length = 50
	}
	res, err := h.svc.SonicPathFor(r.Context(), uc, from, to, length)
	if err != nil {
		h.failFromService(w, r, err, "finding a sonic path failed")
		return
	}
	list, err := h.summariesToSongs(r, uc, res.Items)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	h.ok(w, r, envelope{SonicPath: list})
}

// summariesToSongs maps discovery results onto Subsonic children via
// the string-grouped index (the same objects every browse view mints).
// An index-read failure surfaces to the caller; swallowing it would
// render a real backend problem as an empty result.
func (h *Handler) summariesToSongs(r *http.Request, uc *service.UserCtx, items []service.ItemSummary) (*songList, error) {
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		return nil, err
	}
	out := &songList{Songs: []child{}}
	for _, it := range items {
		tr := idx.trackByPID[it.PID]
		if tr == nil {
			continue
		}
		out.Songs = append(out.Songs, songChild(*tr, idx.albumForTrack(*tr)))
	}
	return out, nil
}
