package service

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/oklog/ulid/v2"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// The Jellyfin import. A minimal REST client walks the user's audio and
// audiobook items for their per-user data (favourite, play count, last
// played, resume position) and matches each through the resolve ladder,
// the same way the Subsonic import does. Jellyfin keeps no per-play log
// and has no per-user rating, so history is synthesized from the play
// count the way a count-only source's always is, and ratings are not
// offered at all.

// jellyfinPageSize is how many items one Items request asks for. The
// server pages by StartIndex and reports TotalRecordCount, and a large
// library is many pages either way; five hundred keeps each answer to a
// few megabytes.
var jellyfinPageSize = 500

// jellyfinClient speaks the slice of the Jellyfin API this import
// reads. Authentication is either a login (which mints an access token
// bound to a user) or a server API key, which authorizes everything but
// names nobody - so with a key the username still has to be resolved to
// a user id before any per-user data can be read.
type jellyfinClient struct {
	migrateSource
	token string
	// device is minted once per import, not per request: it is what a
	// Jellyfin server lists as the session this run opened, and a fresh
	// one on every call would fill that list with a hundred ghosts.
	device string
	userID string
}

func newJellyfinClient(base string) *jellyfinClient {
	return &jellyfinClient{
		migrateSource: newMigrateSource("jellyfin", base),
		device:        migrateClientName + "-" + ulid.Make().String(),
	}
}

// authHeader is Jellyfin's own scheme. The client fields are not
// decoration: a server logs them, and the device is how an
// administrator recognises this import in their session list.
func (c *jellyfinClient) authHeader() string {
	h := fmt.Sprintf(`MediaBrowser Client="WaxDeck", Device="%s", DeviceId=%q, Version="1"`,
		migrateClientName, c.device)
	if c.token != "" {
		h += fmt.Sprintf(`, Token=%q`, c.token)
	}
	return h
}

func (c *jellyfinClient) do(ctx context.Context, method, path string, body []byte, out any) error {
	return c.fetch(ctx, method, path, body,
		http.Header{"Authorization": {c.authHeader()}}, out)
}

// login exchanges a username and password for an access token and the
// user id every later read is scoped to.
func (c *jellyfinClient) login(ctx context.Context, username, password string) error {
	body, err := json.Marshal(map[string]string{"Username": username, "Pw": password})
	if err != nil {
		return err
	}
	var out struct {
		AccessToken string `json:"AccessToken"`
		User        struct {
			ID string `json:"Id"`
		} `json:"User"`
	}
	if err := c.do(ctx, http.MethodPost, "/Users/AuthenticateByName", body, &out); err != nil {
		return err
	}
	if out.AccessToken == "" || out.User.ID == "" {
		return fmt.Errorf("%w: jellyfin: the login answered no access token", errToolPermanent)
	}
	c.token, c.userID = out.AccessToken, out.User.ID
	return nil
}

// resolveUser finds the user id for a name, which is what an API key
// cannot supply: the key is the server's, and per-user data is absent
// from every answer that does not name whose it is.
func (c *jellyfinClient) resolveUser(ctx context.Context, username string) error {
	var users []struct {
		ID   string `json:"Id"`
		Name string `json:"Name"`
	}
	if err := c.do(ctx, http.MethodGet, "/Users", nil, &users); err != nil {
		return err
	}
	for _, u := range users {
		if strings.EqualFold(u.Name, username) {
			c.userID = u.ID
			return nil
		}
	}
	return fmt.Errorf("%w: jellyfin: no user named %q on that server", errToolPermanent, username)
}

// jellyfinItem is the slice of BaseItemDto this import reads. Ticks are
// hundred-nanosecond units, so a millisecond is ten thousand of them.
type jellyfinItem struct {
	ID   string `json:"Id"`
	Name string `json:"Name"`
	// Type is the DTO's own kind ("Audio", "MusicAlbum", ...), which is
	// what separates the two shapes the favourites listing returns.
	Type         string   `json:"Type"`
	Album        string   `json:"Album"`
	AlbumArtist  string   `json:"AlbumArtist"`
	Artists      []string `json:"Artists"`
	RunTimeTicks int64    `json:"RunTimeTicks"`
	ProviderIds  struct {
		MusicBrainzTrack string `json:"MusicBrainzTrack"`
	} `json:"ProviderIds"`
	UserData struct {
		IsFavorite            bool   `json:"IsFavorite"`
		PlayCount             int    `json:"PlayCount"`
		PlaybackPositionTicks int64  `json:"PlaybackPositionTicks"`
		LastPlayedDate        string `json:"LastPlayedDate"`
	} `json:"UserData"`
}

func (i jellyfinItem) artist() string {
	if len(i.Artists) > 0 {
		return i.Artists[0]
	}
	return i.AlbumArtist
}

func (i jellyfinItem) durationMS() int64 { return i.RunTimeTicks / 10000 }

// items pages the user-scoped item list for one set of item types.
//
// The user id rides the query rather than the path: the user-scoped
// items route is gone from the stable API, and without a userId the
// answer carries no UserData at all - which is the entire reason this
// import reads the list. Fields asks only for ProviderIds, because the
// rest of what is read here (Album, Artists, RunTimeTicks, UserData)
// are default DTO properties and Fields takes only ItemFields values.
func (c *jellyfinClient) items(ctx context.Context, types string, extra url.Values, fn func(jellyfinItem) error) error {
	for start := 0; ; {
		q := url.Values{}
		for k, vs := range extra {
			q[k] = vs
		}
		q.Set("userId", c.userID)
		q.Set("IncludeItemTypes", types)
		q.Set("Recursive", "true")
		q.Set("Fields", "ProviderIds")
		// An order, because the walk pages by offset: without one the
		// server is free to answer the same query in a different order
		// each time, and a row that moves across a page boundary between
		// two requests is read twice or not at all.
		q.Set("SortBy", "Id")
		q.Set("SortOrder", "Ascending")
		q.Set("StartIndex", strconv.Itoa(start))
		q.Set("Limit", strconv.Itoa(jellyfinPageSize))
		var page struct {
			Items            []jellyfinItem `json:"Items"`
			TotalRecordCount int            `json:"TotalRecordCount"`
		}
		if err := c.do(ctx, http.MethodGet, "/Items?"+q.Encode(), nil, &page); err != nil {
			return err
		}
		for _, it := range page.Items {
			if err := fn(it); err != nil {
				return err
			}
		}
		start += len(page.Items)
		// A short page ends the walk on its own. The count is what the
		// server says the query holds, and one that did not arrive
		// decodes as zero - which after the first page reads as "that
		// was all of it", so a forty-thousand-item library imported five
		// hundred of them and reported success.
		if len(page.Items) < jellyfinPageSize {
			return nil
		}
		if page.TotalRecordCount > 0 && start >= page.TotalRecordCount {
			return nil
		}
	}
}

// jellyfinAlbumKey identifies one album across the songs on it: an
// album is a title by somebody, and a title on its own is not one.
func jellyfinAlbumKey(artist, album string) string {
	return strings.ToLower(artist) + "\x00" + strings.ToLower(album)
}

// parseJellyfinTime reads the ISO 8601 stamps UserData carries. The
// second layout is the one that matters: a stamp can arrive with no
// zone suffix, and without it that falls back to an hour ago. A layout
// for the fractional seconds is not needed - time.Parse takes those
// after the seconds field whether or not the layout signifies them.
func parseJellyfinTime(s string) time.Time {
	return parseSourceTime(s, time.RFC3339Nano, "2006-01-02T15:04:05")
}

// runJellyfinImport replays a Jellyfin account's favourites, play
// counts, last-played times and resume positions onto the target
// account. Only items carrying state are matched: a walk that resolved
// every song in a library would be pure cost.
func (l *Library) runJellyfinImport(ctx context.Context, t *wdb.ToolTask, uc *UserCtx, p migrationParams, secret string) (migrationSummary, error) {
	sum := migrationSummary{Source: p.Source, DryRun: p.DryRun, Samples: migrationSamples{Unmatched: []string{}}}
	client := newJellyfinClient(p.ServerURL)
	// A password logs in; an API key authorizes but names nobody, so the
	// username is resolved to a user id instead. Which one arrived was
	// decided when the order was placed: nothing at run time can tell a
	// key from a password.
	if p.TokenAuth {
		client.token = secret
		if err := client.resolveUser(ctx, p.Username); err != nil {
			return sum, migrateClientErr(err)
		}
	} else if err := client.login(ctx, p.Username, secret); err != nil {
		return sum, migrateClientErr(err)
	}
	prog := newMigrateProgress(l, t)

	// Every audio item carrying state, in the order the server lists
	// them, so the summary and its samples come out deterministic.
	var songs []jellyfinItem
	collect := func(it jellyfinItem) error {
		// The walk itself renews the lease. A hundred-thousand-item
		// library is two hundred sequential pages before the per-item
		// loop below reports for the first time, which is well past the
		// lease: another drain worker would re-claim the task and run a
		// second copy of this import beside it. The percentage does not
		// move here, which report tolerates.
		prog.report(ctx, 0)
		u := it.UserData
		if !u.IsFavorite && u.PlayCount == 0 && u.PlaybackPositionTicks == 0 {
			return nil
		}
		songs = append(songs, it)
		return nil
	}
	if err := client.items(ctx, "Audio", nil, collect); err != nil {
		return sum, migrateClientErr(err)
	}
	// Books, which take the same per-item shape and differ only in the
	// kind they resolve as.
	firstBook := len(songs)
	if err := client.items(ctx, "AudioBook", nil, collect); err != nil {
		return sum, migrateClientErr(err)
	}

	for i, it := range songs {
		if ctx.Err() != nil {
			return sum, ctx.Err()
		}
		prog.report(ctx, float64(i+1)/float64(len(songs))*90)
		ref := model.PortableRef{
			Kind:       model.KindTrack,
			MBID:       it.ProviderIds.MusicBrainzTrack,
			Artist:     it.artist(),
			Title:      it.Name,
			Album:      it.Album,
			DurationMS: it.durationMS(),
		}
		prefix := PrefixTrack
		if i >= firstBook {
			// A book matches on its own identifiers and its author; a
			// recording MBID is not one of them.
			ref = model.PortableRef{
				Kind:       model.KindBook,
				Artist:     it.artist(),
				Title:      it.Name,
				DurationMS: it.durationMS(),
			}
			prefix = PrefixBook
		}
		found, rung, err := l.resolveMigrationRef(ctx, ref)
		if err != nil {
			return sum, classify(err)
		}
		if found == nil || rung == model.MatchNone {
			sum.noteUnmatched(it.artist(), it.Name)
			continue
		}
		sum.Matched++
		pid := apiPID(prefix, found.PID)
		write := func(fn func() error) (bool, error) {
			if p.DryRun {
				return true, nil
			}
			if err := fn(); err != nil {
				if migrateWriteSkippable(err) {
					l.log.Warn("migration write skipped", "task", t.ID, "item", pid, "err", err)
					return false, nil
				}
				return false, err
			}
			return true, nil
		}
		if p.Stars && it.UserData.IsFavorite {
			// Jellyfin records no time for a favourite, so this write
			// lands in server-now; the catalog orders star writes by
			// recorded time and nil is what says "as of now".
			ok, err := write(func() error {
				_, err := l.SetStar(ctx, uc, pid, true, nil)
				return err
			})
			if err != nil {
				return sum, err
			}
			if ok {
				sum.Stars++
			}
		}
		if p.History && it.UserData.PlayCount > 0 {
			count := it.UserData.PlayCount
			if count > migrateListenCap {
				count = migrateListenCap
				sum.ListensCapped++
			}
			if p.DryRun {
				sum.Listens += count
			} else {
				n, err := l.migrateListens(ctx, uc, &sum, p.Source, it.ID, pid,
					found.DurationMS, count, parseJellyfinTime(it.UserData.LastPlayedDate))
				if err != nil {
					return sum, err
				}
				sum.Listens += n
			}
		}
		if p.Progress && it.UserData.PlaybackPositionTicks > 0 {
			ok, err := write(func() error {
				_, err := l.Checkpoint(ctx, uc, pid, it.UserData.PlaybackPositionTicks/10000, nil)
				return err
			})
			if err != nil {
				return sum, err
			}
			if ok {
				sum.Progress++
			}
		}
	}

	if p.Stars {
		// Only the music: a book title colliding with an album name
		// would otherwise star an unrelated entity through a track ref.
		if err := l.importJellyfinEntityStars(ctx, t, uc, p, client, prog, songs[:firstBook], &sum); err != nil {
			return sum, err
		}
	}
	prog.report(ctx, 95)
	return sum, nil
}

// importJellyfinEntityStars replays favourite albums and artists.
//
// The same shape as the Subsonic import's: a starred group reaches the
// catalog through one of its member songs, whose matched item carries
// the entity handles that name what to star. The members come from the
// walk already done rather than from more requests - a favourite album
// is named by the songs that say they belong to it - so this pass costs
// one listing per entity type and no per-group fetches.
func (l *Library) importJellyfinEntityStars(ctx context.Context, t *wdb.ToolTask, uc *UserCtx, p migrationParams, client *jellyfinClient, prog *migrateProgress, walked []jellyfinItem, sum *migrationSummary) error {
	var albums, artists []jellyfinItem
	if err := client.items(ctx, "MusicAlbum,MusicArtist", url.Values{"Filters": {"IsFavorite"}},
		func(it jellyfinItem) error {
			// One listing, two kinds: the DTO says which it is.
			switch it.Type {
			case "MusicAlbum":
				albums = append(albums, it)
			case "MusicArtist":
				artists = append(artists, it)
			}
			return nil
		}); err != nil {
		return migrateClientErr(err)
	}
	if len(albums) == 0 && len(artists) == 0 {
		return nil
	}

	// Members are the songs already walked, indexed by the names a
	// favourite group carries. Those are the songs that had state of
	// their own, so a favourite album nobody ever played is not among
	// them; that case asks the server for the group's real members
	// rather than reporting a present album as missing.
	byAlbum := map[string][]jellyfinItem{}
	byAlbumName := map[string][]jellyfinItem{}
	byArtist := map[string][]jellyfinItem{}
	for _, s := range walked {
		if s.Album != "" {
			key := strings.ToLower(s.Album)
			byAlbumName[key] = append(byAlbumName[key], s)
			byAlbum[jellyfinAlbumKey(s.AlbumArtist, s.Album)] =
				append(byAlbum[jellyfinAlbumKey(s.AlbumArtist, s.Album)], s)
		}
		for _, a := range append([]string{s.AlbumArtist}, s.Artists...) {
			if a != "" {
				key := strings.ToLower(a)
				byArtist[key] = append(byArtist[key], s)
			}
		}
	}

	// membersOf asks the server for a group's songs, for a favourite
	// whose tracks carry no state of their own and so never appeared in
	// the walk above. One listing per such group, and only for a
	// favourite: the same shape the Subsonic import pays for a starred
	// album, rather than a walk of the whole library.
	membersOf := func(key, id string) ([]jellyfinItem, error) {
		var out []jellyfinItem
		err := client.items(ctx, "Audio", url.Values{key: {id}}, func(it jellyfinItem) error {
			out = append(out, it)
			return nil
		})
		return out, err
	}

	resolveMember := func(members []jellyfinItem) (*model.ItemView, error) {
		for _, s := range members {
			if ctx.Err() != nil {
				return nil, ctx.Err()
			}
			it, rung, err := l.resolveMigrationRef(ctx, model.PortableRef{
				Kind:       model.KindTrack,
				MBID:       s.ProviderIds.MusicBrainzTrack,
				Artist:     s.artist(),
				Title:      s.Name,
				Album:      s.Album,
				DurationMS: s.durationMS(),
			})
			if err != nil {
				return nil, classify(err)
			}
			if it != nil && rung != model.MatchNone {
				return it, nil
			}
		}
		return nil, nil
	}

	star := func(members []jellyfinItem, fetch func() ([]jellyfinItem, error), label string, entityPID func(*model.ItemView) model.PID, prefix string, count *int) error {
		it, err := resolveMember(members)
		if err != nil {
			return err
		}
		if it == nil {
			// Nothing this listener had played matched, which says
			// nothing about the group: ask the server what is in it.
			fetched, fetchErr := fetch()
			if fetchErr != nil {
				return migrateClientErr(fetchErr)
			}
			if it, err = resolveMember(fetched); err != nil {
				return err
			}
		}
		var pid model.PID
		if it != nil {
			pid = entityPID(it)
		}
		if pid == "" {
			sum.noteUnmatchedEntity(label)
			return nil
		}
		if p.DryRun {
			*count++
			return nil
		}
		if _, err := l.SetEntityStar(ctx, uc, apiPID(prefix, pid), true, nil); err != nil {
			if migrateWriteSkippable(err) {
				l.log.Warn("migration entity star skipped", "task", t.ID, "entity", label, "err", err)
				return nil
			}
			return err
		}
		*count++
		return nil
	}

	for _, al := range albums {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		// The entity passes renew the task lease; the percentage does
		// not move, which report tolerates.
		prog.report(ctx, 90)
		label := al.Name
		// Whose album, not just which title. A shelf holds more than one
		// "Greatest Hits", and matching on the name alone stars whichever
		// of them this listener happened to have played - the favourite
		// itself then reports as present and is never looked up. Where
		// the favourite names no album artist there is nothing to
		// compare, and the title alone is all there is to go on.
		members := byAlbumName[strings.ToLower(al.Name)]
		if al.AlbumArtist != "" {
			label = al.AlbumArtist + " - " + al.Name
			members = byAlbum[jellyfinAlbumKey(al.AlbumArtist, al.Name)]
		}
		if err := star(members,
			func() ([]jellyfinItem, error) { return membersOf("ParentId", al.ID) }, label,
			func(it *model.ItemView) model.PID { return it.AlbumPID }, PrefixAlbum, &sum.AlbumStars); err != nil {
			return err
		}
	}
	for _, ar := range artists {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		prog.report(ctx, 90)
		if err := star(byArtist[strings.ToLower(ar.Name)],
			func() ([]jellyfinItem, error) { return membersOf("ArtistIds", ar.ID) }, ar.Name,
			migrateArtistEntity, PrefixArtist, &sum.ArtistStars); err != nil {
			return err
		}
	}
	return nil
}
