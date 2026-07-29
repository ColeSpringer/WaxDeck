package subsonic

import (
	"context"
	"math/rand/v2"
	"net/http"
	"sort"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// The endpoints in this file exist because real clients call them on
// their startup and browse paths: DSub browses by folder out of the
// box (getIndexes/getMusicDirectory/getAlbumList/getStarred), Feishin
// probes artist info, top songs, and scan status, and Symfonium reads
// getOpenSubsonicExtensions the moment the envelope says openSubsonic.
// The folder tree is emulated from tags: artists are the top-level
// directories, albums their children, using the same minted ids as
// the ID3 views, so both browse modes address identical objects.

// getOpenSubsonicExtensions reports the extensions this surface
// actually implements. The envelope declares openSubsonic, which
// makes this endpoint mandatory.
func (h *Handler) getOpenSubsonicExtensions(w http.ResponseWriter, r *http.Request) {
	h.ok(w, r, envelope{OpenSubsonicExtensions: []openSubsonicExtension{
		{Name: "apiKeyAuthentication", Versions: []int{1}},
		{Name: "formPost", Versions: []int{1}},
		{Name: "sonicSimilarity", Versions: []int{1}},
	}})
}

func (h *Handler) getIndexes(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	out := &indexes{LastModified: h.svc.CatalogTailSeq()}
	var section *folderIndex
	for _, a := range idx.artists {
		letter := indexLetter(a.name)
		if section == nil || section.Name != letter {
			out.Index = append(out.Index, folderIndex{Name: letter})
			section = &out.Index[len(out.Index)-1]
		}
		section.Artists = append(section.Artists, folderArtist{ID: a.id, Name: a.name})
	}
	h.ok(w, r, envelope{Indexes: out})
}

func (h *Handler) getMusicDirectory(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	id := r.Form.Get("id")
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	// The id may be either scheme, and the two namespaces are disjoint,
	// so try the album reading before the artist one.
	if al := idx.findAlbum(id); al != nil {
		out := &directory{ID: al.id, Parent: al.artistID, Name: al.name}
		for _, tr := range al.tracks {
			out.Children = append(out.Children, songChild(tr, al))
		}
		h.ok(w, r, envelope{Directory: out})
		return
	}
	if a := idx.findArtist(id); a != nil {
		out := &directory{ID: a.id, Name: a.name}
		for _, al := range a.albums {
			out.Children = append(out.Children, albumDirChild(al))
		}
		h.ok(w, r, envelope{Directory: out})
		return
	}
	h.fail(w, r, 70, "no such directory")
}

func (h *Handler) getAlbumList(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	out := &albumList{}
	for _, al := range h.pagedAlbums(r, idx) {
		out.Albums = append(out.Albums, albumDirChild(al))
	}
	h.ok(w, r, envelope{AlbumList: out})
}

// getStarred is getStarred2's folder-mode twin: the same three lists in
// the directory shapes this mode uses.
func (h *Handler) getStarred(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	songs, err := h.starredSongs(r, uc, idx)
	if err != nil {
		h.failFromService(w, r, err, "listing starred items failed")
		return
	}
	artists, albums, err := h.starredGroups(r, uc, idx)
	if err != nil {
		h.failFromService(w, r, err, "listing starred entities failed")
		return
	}
	out := &starred{Songs: songs}
	for _, a := range artists {
		out.Artists = append(out.Artists, folderArtist{ID: a.id, Name: a.name})
	}
	for _, al := range albums {
		out.Albums = append(out.Albums, albumDirChild(al))
	}
	h.ok(w, r, envelope{Starred: out})
}

func (h *Handler) getRandomSongs(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	size := clampCount(formInt(r, "size", 10))
	// The protocol's filters narrow the pool before the shuffle; a
	// year filter excludes untagged tracks (year zero is unknown, not
	// "before everything").
	genre := r.Form.Get("genre")
	fromYear := formInt(r, "fromYear", 0)
	toYear := formInt(r, "toYear", 0)
	picks := make([]int, 0, len(idx.tracks))
	for i, tr := range idx.tracks {
		if genre != "" && tr.Genre != genre {
			continue
		}
		if (fromYear > 0 || toYear > 0) && tr.Year == 0 {
			continue
		}
		if fromYear > 0 && tr.Year < fromYear {
			continue
		}
		if toYear > 0 && tr.Year > toYear {
			continue
		}
		picks = append(picks, i)
	}
	rand.Shuffle(len(picks), func(i, j int) { picks[i], picks[j] = picks[j], picks[i] })
	out := &songList{}
	for _, i := range picks {
		if len(out.Songs) >= size {
			break
		}
		tr := idx.tracks[i]
		out.Songs = append(out.Songs, songChild(tr, idx.albumForTrack(tr)))
	}
	h.ok(w, r, envelope{RandomSongs: out})
}

func (h *Handler) getSongsByGenre(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	g := r.Form.Get("genre")
	if g == "" {
		h.fail(w, r, 10, "missing genre")
		return
	}
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	count := clampCount(formInt(r, "count", 10))
	offset := max(formInt(r, "offset", 0), 0)
	out := &songList{}
	seen := 0
	for _, tr := range idx.tracks {
		if tr.Genre != g {
			continue
		}
		if seen < offset {
			seen++
			continue
		}
		if len(out.Songs) >= count {
			break
		}
		out.Songs = append(out.Songs, songChild(tr, idx.albumForTrack(tr)))
	}
	h.ok(w, r, envelope{SongsByGenre: out})
}

// getScanStatus reports the library size. Scans run through the
// first-party job surface; this endpoint answers the polling clients
// that gate features on it, not scan progress.
func (h *Handler) getScanStatus(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	h.ok(w, r, envelope{ScanStatus: &scanStatus{Scanning: false, Count: int64(len(idx.tracks))}})
}

// Artist biographies and top-song rankings have no backing source on
// this server; the empty shapes keep client artist pages rendering.
func (h *Handler) getArtistInfo(w http.ResponseWriter, r *http.Request) {
	h.ok(w, r, envelope{ArtistInfo: &artistInfo{}})
}

func (h *Handler) getArtistInfo2(w http.ResponseWriter, r *http.Request) {
	h.ok(w, r, envelope{ArtistInfo2: &artistInfo{}})
}

func (h *Handler) getTopSongs(w http.ResponseWriter, r *http.Request) {
	h.ok(w, r, envelope{TopSongs: &songList{}})
}

// --- podcasts (read-only) ----------------------------------------------------

// episodesPerChannel caps how many episodes one channel response
// carries; feeds with deeper archives are truncated newest-first,
// which is what podcast clients render anyway.
const episodesPerChannel = 100

func (h *Handler) getPodcasts(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	includeEpisodes := r.Form.Get("includeEpisodes") != "false"
	onlyID := r.Form.Get("id")
	subs, err := h.allSubscriptions(r.Context(), uc)
	if err != nil {
		h.failFromService(w, r, err, "listing subscriptions failed")
		return
	}
	out := &podcastsShape{Channels: []podcastChannel{}}
	for _, sub := range subs {
		if onlyID != "" && sub.Show.PID != onlyID {
			continue
		}
		ch := podcastChannel{
			ID:       sub.Show.PID,
			URL:      sub.Show.FeedURL,
			Title:    sub.Show.Title,
			CoverArt: sub.Show.PID,
			Status:   "completed",
		}
		if includeEpisodes {
			eps, err := h.channelEpisodes(r.Context(), uc, sub.Show.PID, episodesPerChannel)
			if err != nil {
				h.failFromService(w, r, err, "listing episodes failed")
				return
			}
			ch.Episodes = eps
		}
		out.Channels = append(out.Channels, ch)
	}
	if onlyID != "" && len(out.Channels) == 0 {
		h.fail(w, r, 70, "no such podcast channel")
		return
	}
	h.ok(w, r, envelope{Podcasts: out})
}

func (h *Handler) getNewestPodcasts(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	count := clampCount(formInt(r, "count", 20))
	subs, err := h.allSubscriptions(r.Context(), uc)
	if err != nil {
		h.failFromService(w, r, err, "listing subscriptions failed")
		return
	}
	var all []podcastEpisode
	for _, sub := range subs {
		// Episode pages are newest-first, so the global newest count
		// can only come from each show's newest count; fetching more
		// per show would be materialized and thrown away.
		eps, err := h.channelEpisodes(r.Context(), uc, sub.Show.PID, count)
		if err != nil {
			h.failFromService(w, r, err, "listing episodes failed")
			return
		}
		all = append(all, eps...)
	}
	sort.SliceStable(all, func(i, j int) bool { return all[i].PublishDate > all[j].PublishDate })
	if len(all) > count {
		all = all[:count]
	}
	h.ok(w, r, envelope{NewestPodcasts: &newestPodcasts{Episodes: all}})
}

func (h *Handler) allSubscriptions(ctx context.Context, uc *service.UserCtx) ([]service.Subscription, error) {
	var out []service.Subscription
	cursor := ""
	for {
		page, next, err := h.svc.Subscriptions(ctx, uc, cursor, 200)
		if err != nil {
			return nil, err
		}
		out = append(out, page...)
		if next == "" {
			break
		}
		cursor = next
	}
	return out, nil
}

func (h *Handler) channelEpisodes(ctx context.Context, uc *service.UserCtx, showPID string, cap int) ([]podcastEpisode, error) {
	eps := []podcastEpisode{}
	cursor := ""
	for len(eps) < cap {
		page, next, err := h.svc.Episodes(ctx, uc, showPID, cursor, min(cap, 100))
		if err != nil {
			return nil, err
		}
		for _, ep := range page {
			eps = append(eps, episodeShape(ep, showPID))
			if len(eps) >= cap {
				break
			}
		}
		if next == "" {
			break
		}
		cursor = next
	}
	return eps, nil
}

// episodeShape maps one episode. An episode gets a streamId whenever it
// can be played: fetched to the server, or unfetched but carrying a feed
// enclosure the server will relay by passthrough. The status still
// reports the download state, which is what keeps the client's download
// button honest about what is held locally.
func episodeShape(ep service.EpisodeSummary, showPID string) podcastEpisode {
	out := podcastEpisode{
		child: child{
			ID:       ep.PID,
			Parent:   showPID,
			Title:    ep.Title,
			Artist:   ep.Artist,
			Album:    ep.Album,
			CoverArt: ep.PID,
			Duration: int(ep.DurationMS / 1000),
			Type:     "podcast",
		},
		ChannelID: showPID,
	}
	if ep.PublishedNS > 0 {
		out.PublishDate = time.Unix(0, ep.PublishedNS).UTC().Format(time.RFC3339)
	}
	if ep.Downloaded || ep.HasEnclosure {
		out.StreamID = ep.PID
	}
	switch {
	case ep.Downloaded:
		out.Status = "completed"
	case ep.FetchState == "failed":
		out.Status = "error"
	case ep.FetchState != "":
		out.Status = "downloading"
	default:
		out.Status = "skipped"
	}
	return out
}

// clampCount bounds client-supplied list sizes.
func clampCount(n int) int {
	if n < 1 {
		return 10
	}
	if n > 500 {
		return 500
	}
	return n
}
