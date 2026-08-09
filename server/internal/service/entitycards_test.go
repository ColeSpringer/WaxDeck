package service

import (
	"context"
	"io"
	"log/slog"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxdeck/fixtures"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// newShelfFixture is a catalog with two releases by two artists, one of
// them carrying every album-identity tag there is. It backs the three
// reads a home shelf and an album header need: resolving a mixed pid
// list to cards, an album's edition facts, and a facet enumeration
// scoped to one artist.
func newShelfFixture(t *testing.T) (context.Context, *Library, *UserCtx) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(io.Discard, nil))

	track := func(name, title, artist, album string, d time.Duration, extra map[string]string) fixtures.Spec {
		tags := map[string]string{
			"TITLE":       title,
			"ARTIST":      artist,
			"ALBUMARTIST": artist,
			"ALBUM":       album,
			"DATE":        "1996",
		}
		for k, v := range extra {
			tags[k] = v
		}
		return fixtures.Spec{Name: name, Codec: fixtures.CodecFLAC, Duration: d, Tags: tags}
	}
	// Every identity column upstream keeps on the album entity, so the
	// read surface has something to answer with. Only the first track
	// carries them: the entity takes them from whichever member has them,
	// which is also the shape a half-tagged release arrives in.
	identity := map[string]string{
		"BARCODE":        "036000291452",
		"LABEL":          "Meridian Sound",
		"CATALOGNUMBER":  "MER-114",
		"MEDIA":          "2xVinyl",
		"RELEASECOUNTRY": "US",
	}
	libDir := t.TempDir()
	if _, err := fixtures.Generate(libDir,
		track("wide", "Wide Angle", "Field Notes", "Long Exposure", 2*time.Second, identity),
		track("close", "Close Focus", "Field Notes", "Long Exposure", 2500*time.Millisecond, nil),
		track("grain", "Grain", "Nightjar", "Contact Sheet", 3*time.Second, nil),
	); err != nil {
		t.Fatalf("generating fixtures: %v", err)
	}

	dataDir := t.TempDir()
	store, err := wdb.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	group := supervise.NewGroup(log)
	svc, err := Open(ctx, Config{
		DataDir: dataDir,
		Roots:   []Root{{Name: "lib", Path: libDir}},
		Logger:  log,
	}, store, group)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cancel()
		group.Wait()
		svc.Close()
		store.Close()
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatalf("scanning fixture library: %v", err)
	}
	acct, err := svc.CreateAccount(ctx, AccountCreate{
		Username: "admin", Password: "correct-horse", Roles: []string{"admin"},
	})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return ctx, svc, uc
}

// bucketPID finds the entity pid behind one dimension's bucket by label.
func bucketPID(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, dimension, label string) string {
	t.Helper()
	page, err := svc.Facets(ctx, uc, FacetQuery{Dimension: dimension, Limit: 500})
	if err != nil {
		t.Fatalf("enumerating %s: %v", dimension, err)
	}
	for _, b := range page.Buckets {
		if b.Label == label {
			if b.EntityPID == "" {
				t.Fatalf("%s bucket %q carries no entity pid", dimension, label)
			}
			return b.EntityPID
		}
	}
	t.Fatalf("no %s bucket labelled %q", dimension, label)
	return ""
}

// TestEntityCardsAnswerInRequestOrder is the contract the pinned shelf
// rests on: the caller's order is the response's order, across kinds, so
// a shelf never reshuffles under a thumb.
func TestEntityCardsAnswerInRequestOrder(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newShelfFixture(t)

	album := bucketPID(t, ctx, svc, uc, "album", "Long Exposure")
	other := bucketPID(t, ctx, svc, uc, "album", "Contact Sheet")
	artist := bucketPID(t, ctx, svc, uc, "artist", "Nightjar")

	pl, err := svc.CreatePlaylist(ctx, uc, PlaylistCreate{Name: "Tape One", Kind: "static"})
	if err != nil {
		t.Fatal(err)
	}

	want := []string{other, pl.PID, album, artist}
	cards, _, err := svc.EntityCards(ctx, uc, want)
	if err != nil {
		t.Fatalf("resolving cards: %v", err)
	}
	if len(cards) != len(want) {
		t.Fatalf("got %d cards, want %d", len(cards), len(want))
	}
	for i, card := range cards {
		if card.PID != want[i] {
			t.Fatalf("card %d is %s, want %s", i, card.PID, want[i])
		}
	}
	byPID := map[string]EntityCard{}
	for _, card := range cards {
		byPID[card.PID] = card
	}
	if got := byPID[album]; got.Kind != "album" || got.Title != "Long Exposure" {
		t.Fatalf("album card is %+v", got)
	}
	// The artist line an album carries comes from two hops (album to
	// release group to artist), which is the part most likely to answer
	// empty if either batch is keyed wrongly.
	if got := byPID[album].Artist; got != "Field Notes" {
		t.Fatalf("album card names artist %q, want Field Notes", got)
	}
	if got := byPID[album].ItemCount; got == nil || *got != 2 {
		t.Fatalf("album card counts %v, want 2", got)
	}
	if got := byPID[artist]; got.Kind != "artist" || got.Title != "Nightjar" || got.Artist != "" {
		t.Fatalf("artist card is %+v", got)
	}
	if got := byPID[pl.PID]; got.Kind != "playlist" || got.Title != "Tape One" {
		t.Fatalf("playlist card is %+v", got)
	}
}

// TestEntityCardsDropWhatCannotBeResolved pins the display-drop rule the
// pinned list depends on: a departed pid leaves the shelf one card
// shorter rather than failing the read, so nothing has to prune a
// preference document to keep home working.
func TestEntityCardsDropWhatCannotBeResolved(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newShelfFixture(t)

	album := bucketPID(t, ctx, svc, uc, "album", "Long Exposure")
	departed := "al-01JZX5N8QW3F4V9T2B7KD3M9R6"
	// Never subscribed, so a show pid resolves to nothing even though the
	// prefix is pinnable.
	show := "pc-01JZX5N8QW3F4V9T2B7KD3M9R7"

	cards, gone, err := svc.EntityCards(ctx, uc, []string{departed, album, show})
	if err != nil {
		t.Fatalf("resolving cards: %v", err)
	}
	if len(cards) != 1 || cards[0].PID != album {
		t.Fatalf("got %+v, want only the album", cards)
	}
	// The album pid the catalog has no row for is named departed; the
	// unsubscribed show is not, because unsubscribed is a state the
	// listener can end and the resolver never learns whether the show
	// exists behind it. Pruning it would turn a lapse into a loss.
	if len(gone) != 1 || gone[0] != departed {
		t.Fatalf("departed = %v, want only %s", gone, departed)
	}

	if _, _, err := svc.EntityCards(ctx, uc, []string{"tr-01JZX5N8QW3F4V9T2B7KD3M9R6"}); KindOf(err) != KindInvalid {
		t.Fatalf("a track pid should be a request error, got %v", err)
	}
	over := make([]string, maxEntityCards+1)
	for i := range over {
		over[i] = album
	}
	if _, _, err := svc.EntityCards(ctx, uc, over); KindOf(err) != KindInvalid {
		t.Fatalf("over the cap should be a request error, got %v", err)
	}
	if cards, _, err := svc.EntityCards(ctx, uc, nil); err != nil || len(cards) != 0 {
		t.Fatalf("an empty request should answer empty, got %+v %v", cards, err)
	}

	// Crockford base32 parses either case, and the catalog keys its batch
	// answer by the stored pid, so a lower-case ULID that resolved and
	// then failed to match would be a card silently missing from a shelf.
	lower, _, err := svc.EntityCards(ctx, uc, []string{strings.ToLower(album)})
	if err != nil {
		t.Fatalf("resolving a lower-case pid: %v", err)
	}
	if len(lower) != 1 || lower[0].PID != album {
		t.Fatalf("a lower-case pid answered %+v, want the album", lower)
	}
}

// TestEntityCardsDropOutsideTheGrant keeps the resolver from handing a
// restricted caller a pid it could not have reached through a listing.
func TestEntityCardsDropOutsideTheGrant(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newShelfFixture(t)

	album := bucketPID(t, ctx, svc, uc, "album", "Long Exposure")
	restricted := &UserCtx{
		ID:         uc.ID,
		CatalogPID: uc.CatalogPID,
		Libraries:  map[string]bool{"lb-nothing": true},
	}
	cards, gone, err := svc.EntityCards(ctx, restricted, []string{album})
	if err != nil {
		t.Fatalf("resolving cards: %v", err)
	}
	if len(cards) != 0 {
		t.Fatalf("a caller granted no holding library should see no card, got %+v", cards)
	}
	// Out of the grant is invisible, never departed: the album exists,
	// and a widened grant brings the card back. A client pruning on
	// this answer would lose the pin over an access decision.
	if len(gone) != 0 {
		t.Fatalf("an out-of-grant album was named departed: %v", gone)
	}
}

// TestEntityCardsNameTheDeparted pins the boundary the pruning signal
// runs on: departed is what the server no longer has for anyone, and a
// miss the caller could still get back stays unnamed.
func TestEntityCardsNameTheDeparted(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newShelfFixture(t)

	pl, err := svc.CreatePlaylist(ctx, uc, PlaylistCreate{Name: "Doomed", Kind: "static"})
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.DeletePlaylist(ctx, uc, pl.PID); err != nil {
		t.Fatal(err)
	}

	other, err := svc.CreateAccount(ctx, AccountCreate{Username: "neighbour", Password: "pw-neighbour-1"})
	if err != nil {
		t.Fatal(err)
	}
	otherCtx, err := svc.UserCtx(ctx, other.User)
	if err != nil {
		t.Fatal(err)
	}
	private, err := svc.CreatePlaylist(ctx, otherCtx, PlaylistCreate{Name: "Theirs", Kind: "static"})
	if err != nil {
		t.Fatal(err)
	}

	cards, gone, err := svc.EntityCards(ctx, uc, []string{pl.PID, private.PID})
	if err != nil {
		t.Fatalf("resolving cards: %v", err)
	}
	if len(cards) != 0 {
		t.Fatalf("neither playlist should draw a card, got %+v", cards)
	}
	// The deleted playlist is gone for everyone; the neighbour's private
	// one exists and could be shared tomorrow.
	if len(gone) != 1 || gone[0] != pl.PID {
		t.Fatalf("departed = %v, want only %s", gone, pl.PID)
	}
}

// TestCountsAreOnlyAnsweredWhereTheyAreTrue: the catalog's entity counts
// take no library scope, so handing one to a restricted caller would
// advertise tracks their own listing will not show. They are answered to
// a caller who can see everything and left absent otherwise.
func TestCountsAreOnlyAnsweredWhereTheyAreTrue(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newShelfFixture(t)

	album := bucketPID(t, ctx, svc, uc, "album", "Long Exposure")
	libs, err := svc.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(libs) == 0 {
		t.Fatal("the fixture has no library")
	}
	// Granted the library that actually holds the album, so the entity is
	// visible and only the count is in question.
	granted := &UserCtx{
		ID: uc.ID, CatalogPID: uc.CatalogPID,
		Libraries: map[string]bool{strings.TrimPrefix(libs[0].PID, PrefixLibrary+"-"): true},
	}

	full, err := svc.Album(ctx, uc, album)
	if err != nil {
		t.Fatal(err)
	}
	if full.ItemCount != 2 || full.TotalDurationMS == 0 {
		t.Fatalf("a full-visibility caller should get the counts, got %+v", full)
	}
	scoped, err := svc.Album(ctx, granted, album)
	if err != nil {
		t.Fatalf("reading the album as a granted caller: %v", err)
	}
	if scoped.ItemCount != 0 || scoped.TotalDurationMS != 0 {
		t.Fatalf("a restricted caller was handed catalog-wide counts: %+v", scoped)
	}
	// The identity is still answered - it is a fact about the release
	// rather than about the caller's reach.
	if scoped.Barcode != full.Barcode || scoped.Title != full.Title {
		t.Fatalf("the identity changed with the caller: %+v", scoped)
	}

	cards, _, err := svc.EntityCards(ctx, granted, []string{album})
	if err != nil {
		t.Fatal(err)
	}
	if len(cards) != 1 {
		t.Fatalf("the album should still resolve, got %+v", cards)
	}
	if cards[0].ItemCount != nil {
		t.Fatalf("a restricted caller's card carries a count: %v", *cards[0].ItemCount)
	}
	if own, _, err := svc.EntityCards(ctx, uc, []string{album}); err != nil {
		t.Fatal(err)
	} else if own[0].ItemCount == nil || *own[0].ItemCount != 2 {
		t.Fatalf("a full-visibility card lost its count: %+v", own[0])
	}
}

// TestAlbumIdentity is the read half of the entity edit surface: the
// five edition columns a track row cannot carry.
func TestAlbumIdentity(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newShelfFixture(t)

	album := bucketPID(t, ctx, svc, uc, "album", "Long Exposure")
	got, err := svc.Album(ctx, uc, album)
	if err != nil {
		t.Fatalf("reading album: %v", err)
	}
	if got.PID != album || got.Title != "Long Exposure" {
		t.Fatalf("album is %+v", got)
	}
	for _, want := range []struct{ field, value, have string }{
		{"barcode", "036000291452", got.Barcode},
		{"label", "Meridian Sound", got.Label},
		{"catalogNumber", "MER-114", got.CatalogNumber},
		{"media", "2xVinyl", got.Media},
		{"country", "US", got.Country},
	} {
		if want.have != want.value {
			t.Fatalf("%s is %q, want %q", want.field, want.have, want.value)
		}
	}
	if got.ItemCount != 2 {
		t.Fatalf("album counts %d tracks, want 2", got.ItemCount)
	}
	if got.Year != 1996 {
		t.Fatalf("album year is %d, want 1996", got.Year)
	}
	if !strings.HasPrefix(got.ReleaseGroupPID, PrefixReleaseGroup+"-") {
		t.Fatalf("release group pid is %q", got.ReleaseGroupPID)
	}

	// A release with nothing tagged answers the identity fields empty
	// rather than refusing, which is what lets the client render nothing.
	bare, err := svc.Album(ctx, uc, bucketPID(t, ctx, svc, uc, "album", "Contact Sheet"))
	if err != nil {
		t.Fatalf("reading the untagged album: %v", err)
	}
	if bare.Barcode != "" || bare.Label != "" || bare.Media != "" {
		t.Fatalf("an untagged release carries identity: %+v", bare)
	}
}

// TestAlbumRejectsTheWrongPrefix keeps a track pid presented as an album
// a plain not-found rather than a wrong-shaped answer.
func TestAlbumRejectsTheWrongPrefix(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newShelfFixture(t)

	page, err := svc.Items(ctx, uc, ItemFilter{}, "", 1)
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Items) == 0 {
		t.Fatal("the fixture library listed nothing")
	}
	if _, err := svc.Album(ctx, uc, page.Items[0].PID); KindOf(err) != KindNotFound {
		t.Fatalf("a track pid should be not-found, got %v", err)
	}
	if _, err := svc.Album(ctx, uc, "al-01JZX5N8QW3F4V9T2B7KD3M9R6"); KindOf(err) != KindNotFound {
		t.Fatalf("an unknown album should be not-found, got %v", err)
	}
	if _, err := svc.Album(ctx, uc, "not-a-pid"); KindOf(err) != KindNotFound {
		t.Fatalf("a malformed pid should be not-found, got %v", err)
	}
}

// TestAlbumHiddenOutsideTheGrant keeps the identity read on the same
// visibility rule every other entity read applies.
func TestAlbumHiddenOutsideTheGrant(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newShelfFixture(t)

	album := bucketPID(t, ctx, svc, uc, "album", "Long Exposure")
	restricted := &UserCtx{
		ID:         uc.ID,
		CatalogPID: uc.CatalogPID,
		Libraries:  map[string]bool{"lb-nothing": true},
	}
	if _, err := svc.Album(ctx, restricted, album); KindOf(err) != KindNotFound {
		t.Fatalf("an album outside the grant should be not-found, got %v", err)
	}
}
