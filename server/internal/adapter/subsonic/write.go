// The interactive half of the compatibility surface: playlists, stars
// and ratings, scrobbling, bookmark parity over spoken-word resume,
// and the internet radio library. Everything still flows through the
// service layer, so ownership, visibility, and scrobble queueing apply
// exactly as they do for first-party traffic.
package subsonic

import (
	"context"
	"crypto/md5"
	"encoding/hex"
	"fmt"
	"net/http"
	"slices"
	"sort"
	"strconv"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// failFromService maps a service error onto the protocol's error codes.
func (h *Handler) failFromService(w http.ResponseWriter, r *http.Request, err error, notFoundMsg string) {
	switch service.KindOf(err) {
	case service.KindNotFound:
		h.fail(w, r, 70, notFoundMsg)
	case service.KindForbidden:
		h.fail(w, r, 50, "not authorized for this operation")
	case service.KindInvalid:
		h.fail(w, r, 10, err.Error())
	case service.KindMaintenance:
		h.fail(w, r, 0, "the catalog is temporarily under maintenance; retry shortly")
	default:
		h.fail(w, r, 0, "the operation failed")
	}
}

// --- playlists ---------------------------------------------------------------

// allPlaylists pages the service listing to completion.
func (h *Handler) allPlaylists(ctx context.Context, uc *service.UserCtx) ([]service.Playlist, error) {
	var out []service.Playlist
	cursor := ""
	for {
		page, err := h.svc.Playlists(ctx, uc, "", cursor, 500)
		if err != nil {
			return nil, err
		}
		out = append(out, page.Playlists...)
		if page.Next == "" {
			return out, nil
		}
		cursor = page.Next
	}
}

// playlistEntries pages one playlist's members to completion.
func (h *Handler) playlistEntries(ctx context.Context, uc *service.UserCtx, id string) ([]service.PlaylistEntry, error) {
	var out []service.PlaylistEntry
	cursor := ""
	for {
		page, err := h.svc.PlaylistItems(ctx, uc, id, cursor, 500)
		if err != nil {
			return nil, err
		}
		out = append(out, page.Entries...)
		if page.Next == "" {
			return out, nil
		}
		cursor = page.Next
	}
}

func (h *Handler) getPlaylists(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	rows, err := h.allPlaylists(r.Context(), uc)
	if err != nil {
		h.failFromService(w, r, err, "listing playlists failed")
		return
	}
	out := &playlists{}
	for _, pl := range rows {
		out.Playlists = append(out.Playlists, playlistHeader(pl))
	}
	h.ok(w, r, envelope{Playlists: out})
}

func (h *Handler) getPlaylist(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	id := r.Form.Get("id")
	pl, err := h.svc.PlaylistByPID(r.Context(), uc, id)
	if err != nil {
		h.failFromService(w, r, err, "no such playlist")
		return
	}
	entries, err := h.playlistEntries(r.Context(), uc, id)
	if err != nil {
		h.failFromService(w, r, err, "no such playlist")
		return
	}
	h.renderPlaylist(w, r, uc, pl, entries)
}

func (h *Handler) renderPlaylist(w http.ResponseWriter, r *http.Request, uc *service.UserCtx, pl service.Playlist, entries []service.PlaylistEntry) {
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	out := &playlistWithSongs{playlistShape: playlistHeader(pl)}
	var durMS int64
	for _, e := range entries {
		out.Entries = append(out.Entries, h.entryChild(idx, e.Item))
		durMS += e.Item.DurationMS
	}
	out.SongCount = len(entries)
	out.Duration = int(durMS / 1000)
	h.ok(w, r, envelope{Playlist: out})
}

// entryChild renders one playlist or list member: tracks resolve
// through the grouped index for full album linkage, everything else
// renders from the summary row.
func (h *Handler) entryChild(idx *index, it service.ItemSummary) child {
	if tr := idx.trackByPID[it.PID]; tr != nil {
		return songChild(*tr, idx.albumByKey[albumKeyForTrack(*tr)])
	}
	return child{
		ID:       it.PID,
		Title:    it.Title,
		Album:    it.Album,
		Artist:   it.Artist,
		CoverArt: it.PID,
		Duration: int(it.DurationMS / 1000),
		Type:     it.MediaType,
	}
}

func (h *Handler) createPlaylist(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	songIDs := r.Form["songId"]
	if existing := r.Form.Get("playlistId"); existing != "" {
		// The protocol's replace form: the playlist keeps its identity,
		// the member list becomes exactly the given songs.
		if err := h.svc.ReplacePlaylistItems(r.Context(), uc, existing, songIDs, nil); err != nil {
			h.failFromService(w, r, err, "no such playlist")
			return
		}
		h.respondWithPlaylist(w, r, uc, existing)
		return
	}
	name := r.Form.Get("name")
	if name == "" {
		h.fail(w, r, 10, "missing name")
		return
	}
	pl, err := h.svc.CreatePlaylist(r.Context(), uc, service.PlaylistCreate{
		Name:     name,
		Kind:     "static",
		ItemPIDs: songIDs,
	})
	if err != nil {
		h.failFromService(w, r, err, "creating the playlist failed")
		return
	}
	h.respondWithPlaylist(w, r, uc, pl.PID)
}

func (h *Handler) respondWithPlaylist(w http.ResponseWriter, r *http.Request, uc *service.UserCtx, id string) {
	pl, err := h.svc.PlaylistByPID(r.Context(), uc, id)
	if err != nil {
		h.failFromService(w, r, err, "no such playlist")
		return
	}
	entries, err := h.playlistEntries(r.Context(), uc, id)
	if err != nil {
		h.failFromService(w, r, err, "no such playlist")
		return
	}
	h.renderPlaylist(w, r, uc, pl, entries)
}

func (h *Handler) updatePlaylist(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	id := r.Form.Get("playlistId")
	if id == "" {
		h.fail(w, r, 10, "missing playlistId")
		return
	}
	upd := service.PlaylistUpdate{}
	if name := r.Form.Get("name"); name != "" {
		upd.Name = &name
	}
	if pub := r.Form.Get("public"); pub != "" {
		vis := "private"
		if pub == "true" {
			vis = "shared"
		}
		upd.Visibility = &vis
	}
	if upd.Name != nil || upd.Visibility != nil {
		if _, err := h.svc.UpdatePlaylist(r.Context(), uc, id, upd); err != nil {
			h.failFromService(w, r, err, "no such playlist")
			return
		}
	}
	// Removals go index-descending so earlier removals never shift the
	// positions later ones refer to.
	if removes := r.Form["songIndexToRemove"]; len(removes) > 0 {
		positions := make([]int, 0, len(removes))
		for _, raw := range removes {
			n, err := strconv.Atoi(raw)
			if err != nil || n < 0 {
				h.fail(w, r, 10, "malformed songIndexToRemove")
				return
			}
			positions = append(positions, n)
		}
		sort.Sort(sort.Reverse(sort.IntSlice(positions)))
		// A duplicated index names the same row twice; removing it
		// twice would take a second, shifted item with it.
		positions = slices.Compact(positions)
		for _, pos := range positions {
			if err := h.svc.RemovePlaylistItemAt(r.Context(), uc, id, pos); err != nil {
				h.failFromService(w, r, err, "no such playlist")
				return
			}
		}
	}
	if adds := r.Form["songIdToAdd"]; len(adds) > 0 {
		if err := h.svc.AddPlaylistItems(r.Context(), uc, id, adds); err != nil {
			h.failFromService(w, r, err, "no such playlist")
			return
		}
	}
	h.ok(w, r, envelope{})
}

func (h *Handler) deletePlaylist(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	if err := h.svc.DeletePlaylist(r.Context(), uc, r.Form.Get("id")); err != nil {
		h.failFromService(w, r, err, "no such playlist")
		return
	}
	h.ok(w, r, envelope{})
}

// --- stars and ratings -------------------------------------------------------

func (h *Handler) setStar(w http.ResponseWriter, r *http.Request, uc *service.UserCtx, starred bool) {
	if len(r.Form["albumId"]) > 0 || len(r.Form["artistId"]) > 0 {
		h.fail(w, r, 0, "starring albums and artists is not supported by this server; star songs instead")
		return
	}
	ids := r.Form["id"]
	if len(ids) == 0 {
		h.fail(w, r, 10, "missing id")
		return
	}
	for _, id := range ids {
		if _, err := h.svc.SetStar(r.Context(), uc, id, starred, nil); err != nil {
			h.failFromService(w, r, err, "no such song")
			return
		}
	}
	h.ok(w, r, envelope{})
}

func (h *Handler) setRating(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	id := r.Form.Get("id")
	raw := r.Form.Get("rating")
	if id == "" || raw == "" {
		h.fail(w, r, 10, "missing id or rating")
		return
	}
	stars, err := strconv.Atoi(raw)
	if err != nil || stars < 0 || stars > 5 {
		h.fail(w, r, 10, "rating must be 0 to 5")
		return
	}
	var rating *int
	if stars > 0 {
		v := stars * 20
		rating = &v
	}
	if _, err := h.svc.SetRating(r.Context(), uc, id, rating, nil); err != nil {
		h.failFromService(w, r, err, "no such song")
		return
	}
	h.ok(w, r, envelope{})
}

func (h *Handler) getStarred2(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	out := &starred2{}
	cursor := ""
	for {
		page, err := h.svc.Browse(r.Context(), uc, "starred", 0, cursor, 500)
		if err != nil {
			h.failFromService(w, r, err, "listing starred items failed")
			return
		}
		for _, it := range page.Items {
			out.Songs = append(out.Songs, h.entryChild(idx, it))
		}
		if page.Next == "" {
			break
		}
		cursor = page.Next
	}
	h.ok(w, r, envelope{Starred2: out})
}

// --- scrobbling --------------------------------------------------------------

func (h *Handler) scrobble(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	ids := r.Form["id"]
	if len(ids) == 0 {
		h.fail(w, r, 10, "missing id")
		return
	}
	submission := r.Form.Get("submission") != "false"
	if !submission {
		// A now-playing update: ephemeral, best effort, first id only
		// (the protocol sends one).
		if err := h.svc.NowPlayingScrobble(r.Context(), uc, ids[0]); err != nil {
			h.failFromService(w, r, err, "no such song")
			return
		}
		h.ok(w, r, envelope{})
		return
	}
	times := r.Form["time"]
	sessions := make([]service.ListenSession, 0, len(ids))
	for i, id := range ids {
		det, err := h.svc.Item(r.Context(), uc, id)
		if err != nil {
			h.failFromService(w, r, err, "no such song")
			return
		}
		started := time.Now()
		timed := false
		if i < len(times) {
			if ms, err := strconv.ParseInt(times[i], 10, 64); err == nil && ms > 0 {
				started = time.UnixMilli(ms)
				timed = true
			}
		}
		s := service.ListenSession{
			SessionID: scrobbleSessionID(uc.ID, id, started, timed),
			PID:       id,
			StartedAt: started.UTC(),
			MsPlayed:  det.DurationMS,
			Client:    r.Form.Get("c"),
			Source:    "live",
		}
		// A submission asserts the client played the item; when the
		// catalog has no duration the played threshold cannot compute,
		// so the finished flag carries the assertion instead.
		if det.DurationMS <= 0 {
			s.Finished = true
		}
		sessions = append(sessions, s)
	}
	res, err := h.svc.IngestListens(r.Context(), uc, sessions)
	if err != nil {
		h.failFromService(w, r, err, "no such song")
		return
	}
	if len(res.Rejected) > 0 {
		h.fail(w, r, 10, res.Rejected[0].Message)
		return
	}
	h.ok(w, r, envelope{})
}

// scrobbleSessionID derives the listen's idempotency id. A timed
// submission hashes deterministically, so an offline queue replaying
// the same scrobble twice dedupes; an untimed one is unique by nature.
func scrobbleSessionID(userID, itemPID string, started time.Time, timed bool) string {
	stamp := started.UnixMilli()
	if !timed {
		stamp = time.Now().UnixNano()
	}
	sum := md5.Sum(fmt.Appendf(nil, "%s|%s|%d", userID, itemPID, stamp))
	return "subsonic-" + hex.EncodeToString(sum[:])
}

// --- bookmarks (spoken-word resume parity) -----------------------------------

// Bookmark endpoints map onto book and episode resume positions, which
// is how the clients that call them use them. getBookmarks lists the
// caller's in-progress spoken-word items; createBookmark writes a
// position; deleteBookmark clears it.

func (h *Handler) getBookmarks(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	items, err := h.svc.RecentlyPositionedItems(r.Context(), uc, 200)
	if err != nil {
		h.failFromService(w, r, err, "listing bookmarks failed")
		return
	}
	out := &bookmarks{}
	for _, it := range items {
		st, err := h.svc.PlayState(r.Context(), uc, it.PID)
		if err != nil || st.PositionMS <= 0 {
			continue
		}
		out.Bookmarks = append(out.Bookmarks, bookmark{
			Position: st.PositionMS,
			Username: r.Form.Get("u"),
			Created:  st.UpdatedAt.UTC().Format(time.RFC3339),
			Changed:  st.UpdatedAt.UTC().Format(time.RFC3339),
			Entry:    h.entryChild(idx, it),
		})
	}
	h.ok(w, r, envelope{Bookmarks: out})
}

func (h *Handler) createBookmark(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	id := r.Form.Get("id")
	pos, err := strconv.ParseInt(r.Form.Get("position"), 10, 64)
	if id == "" || err != nil || pos < 0 {
		h.fail(w, r, 10, "missing or malformed id or position")
		return
	}
	if err := h.svc.Checkpoint(r.Context(), uc, id, pos, nil); err != nil {
		h.failFromService(w, r, err, "no such item")
		return
	}
	h.ok(w, r, envelope{})
}

func (h *Handler) deleteBookmark(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	id := r.Form.Get("id")
	if id == "" {
		h.fail(w, r, 10, "missing id")
		return
	}
	if err := h.svc.Checkpoint(r.Context(), uc, id, 0, nil); err != nil {
		h.failFromService(w, r, err, "no such item")
		return
	}
	h.ok(w, r, envelope{})
}

// --- internet radio ----------------------------------------------------------

func (h *Handler) getInternetRadioStations(w http.ResponseWriter, r *http.Request) {
	stations, err := h.svc.RadioStations(r.Context())
	if err != nil {
		h.fail(w, r, 0, "listing stations failed")
		return
	}
	out := &internetRadioStations{}
	for _, st := range stations {
		out.Stations = append(out.Stations, internetRadioStation{
			ID:          st.PID,
			Name:        st.Name,
			StreamURL:   st.StreamURL,
			HomepageURL: st.HomepageURL,
		})
	}
	h.ok(w, r, envelope{InternetRadioStations: out})
}

func (h *Handler) createInternetRadioStation(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	if _, err := h.svc.CreateRadioStation(r.Context(), uc, service.RadioStationEdit{
		Name:        r.Form.Get("name"),
		StreamURL:   r.Form.Get("streamUrl"),
		HomepageURL: r.Form.Get("homepageUrl"),
	}); err != nil {
		h.failFromService(w, r, err, "creating the station failed")
		return
	}
	h.ok(w, r, envelope{})
}

func (h *Handler) updateInternetRadioStation(w http.ResponseWriter, r *http.Request) {
	_, err := h.svc.UpdateRadioStation(r.Context(), r.Form.Get("id"), service.RadioStationEdit{
		Name:        r.Form.Get("name"),
		StreamURL:   r.Form.Get("streamUrl"),
		HomepageURL: r.Form.Get("homepageUrl"),
	})
	if err != nil {
		h.failFromService(w, r, err, "no such station")
		return
	}
	h.ok(w, r, envelope{})
}

func (h *Handler) deleteInternetRadioStation(w http.ResponseWriter, r *http.Request) {
	if err := h.svc.DeleteRadioStation(r.Context(), r.Form.Get("id")); err != nil {
		h.failFromService(w, r, err, "no such station")
		return
	}
	h.ok(w, r, envelope{})
}

// playlistHeader converts the service playlist to the protocol header.
func playlistHeader(pl service.Playlist) playlistShape {
	out := playlistShape{
		ID:      pl.PID,
		Name:    pl.Name,
		Owner:   pl.OwnerName,
		Public:  pl.Visibility == "shared",
		Created: pl.CreatedAt.UTC().Format(time.RFC3339),
		Changed: pl.UpdatedAt.UTC().Format(time.RFC3339),
	}
	if pl.ItemCount != nil {
		out.SongCount = *pl.ItemCount
	}
	return out
}
