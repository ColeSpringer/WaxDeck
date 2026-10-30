package subsonic

import (
	"context"
	"math/rand/v2"
	"net/http"
	"sort"
	"strings"
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
	exts := []openSubsonicExtension{
		{Name: "apiKeyAuthentication", Versions: []int{1}},
		{Name: "formPost", Versions: []int{1}},
		{Name: "sonicSimilarity", Versions: []int{1}},
	}
	// stream's timeOffset is a cut the streaming engine makes, so only a
	// server running one honours it. A configured engine that is away
	// still counts: a client reads this list once and keeps it, and an
	// offset asked meanwhile is refused rather than played from the top.
	if h.engine {
		exts = append(exts, openSubsonicExtension{Name: "transcodeOffset", Versions: []int{1}})
	}
	h.ok(w, r, envelope{OpenSubsonicExtensions: exts})
}

func (h *Handler) getIndexes(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	idx, ok := h.scopedIndex(w, r, uc)
	if !ok {
		return
	}
	// The position the index answers for, so a client's change check
	// moves exactly when what it is shown does.
	out := &indexes{LastModified: idx.tail}
	var section *folderIndex
	for _, a := range idx.artists {
		letter := indexLetter(a.name)
		if section == nil || section.Name != letter {
			out.Index = append(out.Index, folderIndex{Name: letter})
			section = &out.Index[len(out.Index)-1]
		}
		section.Artists = append(section.Artists, a.folder())
	}
	h.ok(w, r, envelope{Indexes: out})
}

func (h *Handler) getMusicDirectory(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	id := r.Form.Get("id")
	if id == "" {
		h.fail(w, r, 10, "missing id")
		return
	}
	// An episode names its show as its parent.
	if strings.HasPrefix(id, service.PrefixPodcast+"-") {
		h.showDirectory(w, r, uc, id)
		return
	}
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

// showDirectory answers a podcast show as the directory of the episodes
// getPodcasts lists for it that can play, built from the same reads, so it
// is a directory exactly to the callers getPodcasts lists them to.
func (h *Handler) showDirectory(w http.ResponseWriter, r *http.Request, uc *service.UserCtx, id string) {
	subs, err := h.followedShows(r.Context(), uc, id)
	if err != nil {
		h.failFromService(w, r, err, "no such directory")
		return
	}
	if len(subs) == 0 {
		h.fail(w, r, 70, "no such directory")
		return
	}
	show := subs[0].Show
	eps, err := h.channelEpisodes(r.Context(), uc, show.PID, episodesPerChannel)
	if err != nil {
		h.failFromService(w, r, err, "no such directory")
		return
	}
	out := &directory{ID: show.PID, Name: show.Title, Children: make([]child, 0, len(eps))}
	for _, ep := range eps {
		// A child is a song, with no streamId to say it has nothing to play.
		if e := episodeShape(ep, show); e.StreamID != "" {
			out.Children = append(out.Children, e.child)
		}
	}
	h.ok(w, r, envelope{Directory: out})
}

func (h *Handler) getAlbumList(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	idx, ok := h.scopedIndex(w, r, uc)
	if !ok {
		return
	}
	albums, marks, ref, err := h.albumList(r.Context(), r, uc, idx)
	if ref != nil {
		h.fail(w, r, ref.code, ref.msg)
		return
	}
	if err != nil {
		h.failFromService(w, r, err, "listing albums failed")
		return
	}
	out := &albumList{}
	for _, al := range albums {
		out.Albums = append(out.Albums, albumDirChild(al))
	}
	h.ok(w, r, envelope{AlbumList: out, entityMarks: marks})
}

// getStarred is getStarred2's folder-mode twin: the same three lists in
// the directory shapes this mode uses.
func (h *Handler) getStarred(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	idx, ok := h.scopedIndex(w, r, uc)
	if !ok {
		return
	}
	songs, err := h.starredSongs(r, uc, idx)
	if err != nil {
		h.failFromService(w, r, err, "listing starred items failed")
		return
	}
	artists, albums, err := h.starredGroups(r.Context(), uc, idx)
	if err != nil {
		h.failFromService(w, r, err, "listing starred entities failed")
		return
	}
	out := &starred{Songs: songs}
	for _, a := range artists {
		out.Artists = append(out.Artists, a.folder())
	}
	for _, al := range albums {
		out.Albums = append(out.Albums, albumDirChild(al))
	}
	h.ok(w, r, envelope{Starred: out})
}

func (h *Handler) getRandomSongs(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	idx, ok := h.scopedIndex(w, r, uc)
	if !ok {
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
	idx, ok := h.scopedIndex(w, r, uc)
	if !ok {
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

// Artist biographies have no backing source on this server; the empty
// shapes keep client artist pages rendering, for an id the caller can
// browse: an artist, and for getArtistInfo an album or a song too, as
// the protocol has it.
func (h *Handler) getArtistInfo(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	// A show is a directory too, to whoever getMusicDirectory opens it for.
	if id := r.Form.Get("id"); strings.HasPrefix(id, service.PrefixPodcast+"-") {
		subs, err := h.followedShows(r.Context(), uc, id)
		switch {
		case err != nil:
			h.failFromService(w, r, err, "no such artist")
		case len(subs) == 0:
			h.fail(w, r, 70, "no such artist")
		default:
			h.ok(w, r, envelope{ArtistInfo: &artistInfo{}})
		}
		return
	}
	idx, ok := h.artistInfoIndex(w, r, uc)
	if !ok {
		return
	}
	if id := r.Form.Get("id"); idx.findArtist(id) == nil && idx.findAlbum(id) == nil && idx.trackByPID[id] == nil {
		h.fail(w, r, 70, "no such artist")
		return
	}
	h.ok(w, r, envelope{ArtistInfo: &artistInfo{}})
}

func (h *Handler) getArtistInfo2(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	idx, ok := h.artistInfoIndex(w, r, uc)
	if !ok {
		return
	}
	if idx.findArtist(r.Form.Get("id")) == nil {
		h.fail(w, r, 70, "no such artist")
		return
	}
	h.ok(w, r, envelope{ArtistInfo2: &artistInfo{}})
}

// artistInfoIndex is the caller's index for an artist info request that
// names an id. False means the failure is written.
func (h *Handler) artistInfoIndex(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) (*index, bool) {
	if r.Form.Get("id") == "" {
		h.fail(w, r, 10, "missing id")
		return nil, false
	}
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return nil, false
	}
	return idx, true
}

// getTopSongs is an artist's tracks the caller has played, most played
// first, the more recently played on a tie. The artist is named, as the
// protocol has it, matched on either the track's artist or the album
// artist it groups under.
func (h *Handler) getTopSongs(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	name := r.Form.Get("artist")
	if name == "" {
		h.fail(w, r, 10, "missing artist")
		return
	}
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	count := clampCount(formInt(r, "count", 50))
	var candidates []track
	var pids []string
	for _, tr := range idx.tracks {
		al := idx.albumForTrack(tr)
		if strings.EqualFold(tr.Artist, name) || (al != nil && strings.EqualFold(al.artist, name)) {
			candidates = append(candidates, tr)
			pids = append(pids, tr.PID)
		}
	}
	counts, err := h.svc.ItemMarks(r.Context(), uc, pids)
	if err != nil {
		h.failFromService(w, r, err, "reading play counts failed")
		return
	}
	played := candidates[:0]
	for _, tr := range candidates {
		if counts[tr.PID].PlayCount > 0 {
			played = append(played, tr)
		}
	}
	sort.SliceStable(played, func(i, j int) bool {
		mi, mj := counts[played[i].PID], counts[played[j].PID]
		if mi.PlayCount != mj.PlayCount {
			return mi.PlayCount > mj.PlayCount
		}
		return mi.LastPlayedAt.After(mj.LastPlayedAt)
	})
	out := &songList{Songs: []child{}}
	for _, tr := range played[:min(count, len(played))] {
		out.Songs = append(out.Songs, songChild(tr, idx.albumForTrack(tr)))
	}
	h.ok(w, r, envelope{TopSongs: out})
}

// --- podcasts (read-only) ----------------------------------------------------

// episodesPerChannel caps how many episodes one channel response
// carries; feeds with deeper archives are truncated newest-first,
// which is what podcast clients render anyway.
const episodesPerChannel = 100

func (h *Handler) getPodcasts(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	includeEpisodes := r.Form.Get("includeEpisodes") != "false"
	onlyID := r.Form.Get("id")
	subs, err := h.followedShows(r.Context(), uc, onlyID)
	if err != nil {
		h.failFromService(w, r, err, "listing subscriptions failed")
		return
	}
	out := &podcastsShape{Channels: []podcastChannel{}}
	for _, sub := range subs {
		ch := podcastChannel{
			ID:          sub.Show.PID,
			URL:         sub.Show.FeedURL,
			Title:       sub.Show.Title,
			Description: sub.Show.DescriptionText(),
			CoverArt:    sub.Show.PID,
			Status:      "completed",
		}
		if includeEpisodes {
			eps, err := h.channelEpisodes(r.Context(), uc, sub.Show.PID, episodesPerChannel)
			if onlyID == "" && service.KindOf(err) == service.KindNotFound {
				continue // gone since the listing, not the whole list's failure
			}
			if err != nil {
				h.failFromService(w, r, err, "listing episodes failed")
				return
			}
			ch.Episodes = make([]podcastEpisode, 0, len(eps))
			for _, ep := range eps {
				ch.Episodes = append(ch.Episodes, podcastEntry(ep, sub.Show))
			}
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
	type dated struct {
		ep   service.EpisodeSummary
		show *service.PodcastShow
		at   string
	}
	var all []dated
	for i := range subs {
		// Episode pages are newest-first, so the global newest count
		// can only come from each show's newest count; fetching more
		// per show would be materialized and thrown away.
		eps, err := h.channelEpisodes(r.Context(), uc, subs[i].Show.PID, count)
		if service.KindOf(err) == service.KindNotFound {
			continue // gone since the listing, as in getPodcasts
		}
		if err != nil {
			h.failFromService(w, r, err, "listing episodes failed")
			return
		}
		for _, ep := range eps {
			all = append(all, dated{ep: ep, show: &subs[i].Show, at: publishDate(ep)})
		}
	}
	sort.SliceStable(all, func(i, j int) bool { return all[i].at > all[j].at })
	// Shaped after the cut, so only the episodes answered are described.
	out := &newestPodcasts{Episodes: make([]podcastEpisode, 0, min(count, len(all)))}
	for _, d := range all[:min(count, len(all))] {
		out.Episodes = append(out.Episodes, podcastEntry(d.ep, *d.show))
	}
	h.ok(w, r, envelope{NewestPodcasts: out})
}

// followedShows are the shows getPodcasts lists: the caller's
// subscriptions it may hear, or with only, that show alone if it is one,
// read on its own.
func (h *Handler) followedShows(ctx context.Context, uc *service.UserCtx, only string) ([]service.Subscription, error) {
	if only == "" {
		return h.allSubscriptions(ctx, uc)
	}
	d, err := h.svc.PodcastDetailFor(ctx, uc, only)
	if k := service.KindOf(err); k == service.KindNotFound || k == service.KindInvalid {
		return nil, nil
	}
	// The pid as the show has it: a respelled one names no channel here.
	if err != nil || !d.Subscribed || d.Show.PID != only {
		return nil, err
	}
	return []service.Subscription{{Show: d.Show, Settings: *d.Settings}}, nil
}

func (h *Handler) allSubscriptions(ctx context.Context, uc *service.UserCtx) ([]service.Subscription, error) {
	var out []service.Subscription
	cursor := ""
	for {
		page, next, err := h.svc.Subscriptions(ctx, uc, cursor, 200, false)
		if err != nil {
			return nil, err
		}
		for _, sub := range page {
			if !sub.Withheld {
				out = append(out, sub)
			}
		}
		if next == "" {
			break
		}
		cursor = next
	}
	return out, nil
}

// channelEpisodes reads a followed show's newest episodes, at most cap.
func (h *Handler) channelEpisodes(ctx context.Context, uc *service.UserCtx, showPID string, cap int) ([]service.EpisodeSummary, error) {
	eps := []service.EpisodeSummary{}
	cursor := ""
	for len(eps) < cap {
		page, next, err := h.svc.Episodes(ctx, uc, showPID, cursor, min(cap, 100))
		if err != nil {
			return nil, err
		}
		for _, ep := range page {
			eps = append(eps, ep)
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
func episodeShape(ep service.EpisodeSummary, show service.PodcastShow) podcastEpisode {
	showPID := show.PID
	// The fetched file's format, or the one its feed declared for an
	// episode the relay serves; formatFacts' floor when neither is known,
	// which keeps contentType present (formatFacts says why it must be).
	suffix, contentType := formatFacts(ep.Container)
	if ep.MimeType != "" {
		contentType = ep.MimeType
	}
	out := podcastEpisode{
		child: child{
			ID:          ep.PID,
			Parent:      showPID,
			Title:       ep.Title,
			Artist:      ep.Artist,
			Album:       ep.Album,
			CoverArt:    ep.PID,
			Duration:    int(ep.DurationMS / 1000),
			Type:        "podcast",
			Suffix:      suffix,
			ContentType: contentType,
		},
		ChannelID:   showPID,
		PublishDate: publishDate(ep),
	}
	if ep.Explicit || show.Explicit {
		// The show's own flag counts, not just the episode's: a feed that
		// declares the advisory once at the channel level covers every
		// episode under it, and WaxDeck's content gating already reads it
		// that way (a show marked explicit is withheld whole from an
		// account without the permission). Reporting only the item-level
		// flag would have the compatibility surface disagree with the
		// server about the same episode.
		//
		// Only the positive direction is reported: the feed flag parses to
		// a bool, so a false one is "the feed did not say explicit", not
		// "the feed said clean", and OpenSubsonic reads an empty
		// explicitStatus as unknown.
		out.ExplicitStatus = "explicit"
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

// podcastEntry is one episode as the podcast views list it: its shape and
// the feed's description, which only those views carry.
func podcastEntry(ep service.EpisodeSummary, show service.PodcastShow) podcastEpisode {
	out := episodeShape(ep, show)
	out.Description = ep.DescriptionText()
	return out
}

// publishDate is when an episode was published, as the protocol writes
// it; empty when the feed dated it nothing.
func publishDate(ep service.EpisodeSummary) string {
	if ep.PublishedNS <= 0 {
		return ""
	}
	return time.Unix(0, ep.PublishedNS).UTC().Format(time.RFC3339)
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
