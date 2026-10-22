package subsonic

import (
	"context"
	"net/http"
	"strings"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// The annotate pass: every success envelope is walked for the songs,
// albums and artists it carries, which then take the caller's own marks
// (star, rating, plays) in one batch per kind, the songs their bookmarks,
// and the songs and albums their files' facts. The marks are decorations
// on a response the caller is already entitled to, so a failed read
// renders it without them rather than failing it.

// ucKey carries the authenticated caller to the annotate pass.
type ucKey struct{}

func withCaller(r *http.Request, uc *service.UserCtx) *http.Request {
	return r.WithContext(context.WithValue(r.Context(), ucKey{}, uc))
}

func callerOf(r *http.Request) *service.UserCtx {
	uc, _ := r.Context().Value(ucKey{}).(*service.UserCtx)
	return uc
}

// shapes are the annotatable shapes one envelope carries.
type shapes struct {
	songs         []*child // songs, episodes and books
	groups        []*child // album folders
	albums        []*albumID3
	artists       []*artistID3
	folderArtists []*folderArtist
	directories   []*directory // an album's or an artist's
}

func (s *shapes) child(c *child) {
	if c.IsDir {
		s.groups = append(s.groups, c)
		return
	}
	s.songs = append(s.songs, c)
}

func (s *shapes) children(list []child) {
	for i := range list {
		s.child(&list[i])
	}
}

func (s *shapes) albumList(list []albumID3) {
	for i := range list {
		s.albums = append(s.albums, &list[i])
	}
}

func (s *shapes) artistList(list []artistID3) {
	for i := range list {
		s.artists = append(s.artists, &list[i])
	}
}

func (s *shapes) folderArtistList(list []folderArtist) {
	for i := range list {
		s.folderArtists = append(s.folderArtists, &list[i])
	}
}

// collect walks every field of the envelope that carries one of the
// shapes.
func (s *shapes) collect(env *envelope) {
	if env.Song != nil {
		s.child(env.Song)
	}
	if env.Album != nil {
		s.albums = append(s.albums, &env.Album.albumID3)
		s.children(env.Album.Songs)
	}
	if env.Artist != nil {
		s.artists = append(s.artists, &env.Artist.artistID3)
		s.albumList(env.Artist.Albums)
	}
	if env.Artists != nil {
		for i := range env.Artists.Index {
			s.artistList(env.Artists.Index[i].Artists)
		}
	}
	if env.Indexes != nil {
		for i := range env.Indexes.Index {
			s.folderArtistList(env.Indexes.Index[i].Artists)
		}
	}
	if env.AlbumList2 != nil {
		s.albumList(env.AlbumList2.Albums)
	}
	if env.AlbumList != nil {
		s.children(env.AlbumList.Albums)
	}
	if env.SearchResult3 != nil {
		s.artistList(env.SearchResult3.Artists)
		s.albumList(env.SearchResult3.Albums)
		s.children(env.SearchResult3.Songs)
	}
	if env.Starred2 != nil {
		s.artistList(env.Starred2.Artists)
		s.albumList(env.Starred2.Albums)
		s.children(env.Starred2.Songs)
	}
	if env.Starred != nil {
		s.folderArtistList(env.Starred.Artists)
		s.children(env.Starred.Albums)
		s.children(env.Starred.Songs)
	}
	if env.Directory != nil {
		s.directories = append(s.directories, env.Directory)
		s.children(env.Directory.Children)
	}
	if env.Playlist != nil {
		s.children(env.Playlist.Entries)
	}
	if env.Bookmarks != nil {
		for i := range env.Bookmarks.Bookmarks {
			s.child(&env.Bookmarks.Bookmarks[i].Entry)
		}
	}
	if env.NowPlaying != nil {
		for i := range env.NowPlaying.Entries {
			s.child(&env.NowPlaying.Entries[i].child)
		}
	}
	for _, list := range []*songList{env.RandomSongs, env.SongsByGenre, env.TopSongs, env.SimilarSongs,
		env.SimilarSongs2, env.SonicSimilarTracks, env.SonicPath} {
		if list != nil {
			s.children(list.Songs)
		}
	}
	if env.Podcasts != nil {
		for i := range env.Podcasts.Channels {
			for j := range env.Podcasts.Channels[i].Episodes {
				s.child(&env.Podcasts.Channels[i].Episodes[j].child)
			}
		}
	}
	if env.NewestPodcasts != nil {
		for i := range env.NewestPodcasts.Episodes {
			s.child(&env.NewestPodcasts.Episodes[i].child)
		}
	}
}

func (s *shapes) empty() bool {
	return len(s.songs)+len(s.groups)+len(s.albums)+len(s.artists)+len(s.folderArtists)+len(s.directories) == 0
}

// itemPIDs are the songs and every album's tracks, each once.
func (s *shapes) itemPIDs() []string {
	var out []string
	seen := map[string]bool{}
	add := func(pid string) {
		if pid != "" && !seen[pid] {
			seen[pid] = true
			out = append(out, pid)
		}
	}
	for _, c := range s.songs {
		add(c.ID)
	}
	for _, tracks := range s.albumTracks() {
		for _, tr := range tracks {
			add(tr.PID)
		}
	}
	return out
}

// entityPIDs are the albums and artists with a catalog entity behind
// them, each once; a minted group has no entity state to carry.
func (s *shapes) entityPIDs() []string {
	var out []string
	seen := map[string]bool{}
	add := func(id, prefix string) {
		if strings.HasPrefix(id, prefix+"-") && !seen[id] {
			seen[id] = true
			out = append(out, id)
		}
	}
	for _, c := range s.groups {
		add(c.ID, service.PrefixAlbum)
	}
	for _, al := range s.albums {
		add(al.ID, service.PrefixAlbum)
	}
	for _, a := range s.artists {
		add(a.ID, service.PrefixArtist)
	}
	for _, a := range s.folderArtists {
		add(a.ID, service.PrefixArtist)
	}
	for _, d := range s.directories {
		add(d.ID, service.PrefixAlbum)
		add(d.ID, service.PrefixArtist)
	}
	return out
}

// filePIDs are each album's first track's file, then the songs' files,
// each once: an album's created is required where a song's is not, so
// the albums' come first when a response holds more than one call reads.
func (s *shapes) filePIDs() []string {
	var out []string
	seen := map[string]bool{}
	add := func(pid string) {
		if pid != "" && !seen[pid] {
			seen[pid] = true
			out = append(out, pid)
		}
	}
	for _, tracks := range s.albumTracks() {
		if len(tracks) > 0 {
			add(tracks[0].FilePID)
		}
	}
	for _, c := range s.songs {
		add(c.fileID)
	}
	return out
}

func (s *shapes) albumTracks() [][]track {
	out := make([][]track, 0, len(s.groups)+len(s.albums))
	for _, c := range s.groups {
		out = append(out, c.tracks)
	}
	for _, al := range s.albums {
		out = append(out, al.tracks)
	}
	return out
}

// apply writes the marks and facts read for the shapes into them.
func (s *shapes) apply(items map[string]service.ItemMark, entities map[string]service.EntityMark, files map[string]service.FileFacts, bookmarks map[string]int64) {
	for _, c := range s.songs {
		m := items[c.ID]
		c.marks = itemMarks(m)
		c.plays = plays{PlayCount: m.PlayCount, Played: stamp(m.LastPlayedAt)}
		c.BookmarkPosition = bookmarks[c.ID]
		if f, ok := files[c.fileID]; ok {
			c.Created, c.BitRate = stamp(f.AddedAt), f.BitrateKbps
			if !c.carved {
				c.Size = f.SizeBytes
			}
		}
	}
	for _, c := range s.groups {
		c.marks = entityMarks(entities[c.ID])
		c.plays = albumPlays(c.tracks, items)
		c.Created = albumCreated(c.tracks, files)
	}
	for _, al := range s.albums {
		al.marks = entityMarks(entities[al.ID])
		al.plays = albumPlays(al.tracks, items)
		al.Created = albumCreated(al.tracks, files)
	}
	for _, a := range s.artists {
		a.marks = entityMarks(entities[a.ID])
	}
	for _, a := range s.folderArtists {
		a.marks = entityMarks(entities[a.ID])
	}
	for _, d := range s.directories {
		d.marks = entityMarks(entities[d.ID])
	}
}

func itemMarks(m service.ItemMark) marks {
	return marks{Starred: stamp(m.StarredAt), UserRating: userRating(m.Rating)}
}

func entityMarks(m service.EntityMark) marks {
	return marks{Starred: stamp(m.StarredAt), UserRating: userRating(m.Rating)}
}

// albumPlays adds up an album's tracks' plays and takes their last.
func albumPlays(tracks []track, items map[string]service.ItemMark) plays {
	var count int
	var last time.Time
	for _, tr := range tracks {
		m := items[tr.PID]
		count += m.PlayCount
		if m.LastPlayedAt.After(last) {
			last = m.LastPlayedAt
		}
	}
	return plays{PlayCount: count, Played: stamp(last)}
}

func albumCreated(tracks []track, files map[string]service.FileFacts) string {
	if len(tracks) == 0 {
		return ""
	}
	return stamp(files[tracks[0].FilePID].AddedAt)
}

// userRating maps a stored 0..100 rating onto the protocol's 1..5; 0 is
// no rating, which the attribute omits.
func userRating(r *int) int {
	if r == nil {
		return 0
	}
	return min(max((*r+10)/20, 1), 5)
}

func stamp(t time.Time) string {
	if t.IsZero() {
		return ""
	}
	return t.UTC().Format(time.RFC3339)
}

// annotate fills the caller's marks and the file facts into every shape
// the envelope carries.
func (h *Handler) annotate(r *http.Request, env *envelope) {
	uc := callerOf(r)
	if uc == nil || h.svc == nil {
		return
	}
	var s shapes
	s.collect(env)
	if s.empty() {
		return
	}
	ctx := r.Context()
	var items map[string]service.ItemMark
	if pids := s.itemPIDs(); len(pids) > 0 {
		var err error
		if items, err = h.svc.ItemMarks(ctx, uc, pids); err != nil {
			h.warn("subsonic item marks", "err", err)
		}
	}
	entities := map[string]service.EntityMark{}
	var unread []string
	for _, pid := range s.entityPIDs() {
		if m, ok := env.entityMarks[pid]; ok {
			entities[pid] = m
		} else {
			unread = append(unread, pid)
		}
	}
	if len(unread) > 0 {
		read, err := h.svc.EntityMarks(ctx, uc, unread)
		if err != nil {
			h.warn("subsonic entity marks", "err", err)
		}
		for pid, m := range read {
			entities[pid] = m
		}
	}
	var files map[string]service.FileFacts
	if pids := s.filePIDs(); len(pids) > 0 {
		files = h.svc.FileFacts(ctx, pids)
	}
	var bookmarks map[string]int64
	if len(s.songs) > 0 {
		pids := make([]string, len(s.songs))
		resume := make(map[string]int64, len(s.songs))
		for i, c := range s.songs {
			pids[i], resume[c.ID] = c.ID, items[c.ID].PositionMS
		}
		var err error
		if bookmarks, err = h.svc.SubsonicBookmarkPositions(ctx, uc, pids, resume); err != nil {
			h.warn("subsonic bookmark positions", "err", err)
		}
	}
	s.apply(items, entities, files, bookmarks)
}
