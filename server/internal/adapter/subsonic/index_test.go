package subsonic

import (
	"strings"
	"testing"
)

// Untagged tracks group under the unknown buckets; every album lookup
// must apply the same defaults, or a song response loses the album and
// artist linkage its browse responses carry.
func TestUnknownTagAlbumLinkage(t *testing.T) {
	rows := []track{
		{PID: "tr-1", Title: "Tagged", Artist: "Artist", AlbumArtist: "Artist", Album: "Album"},
		{PID: "tr-2", Title: "Untagged"},
	}
	idx := buildIndex(rows, nil)
	for _, tr := range rows {
		if idx.albumForTrack(tr) == nil {
			t.Fatalf("track %s: albumForTrack misses the album it grouped under", tr.PID)
		}
	}
	if idx.albumByKey[albumKey("", "")] != nil {
		t.Fatal("an album grouped under raw empty tags instead of the unknown buckets")
	}
	al := idx.albumForTrack(rows[1])
	if al.artist != unknownArtist || al.name != unknownAlbum {
		t.Fatalf("untagged album = %q / %q, want the unknown buckets", al.artist, al.name)
	}
}

// Artist ordering groups by index section ("#" first) and folds case
// inside one. A byte-order sort runs A to Z twice (uppercase initials,
// then lowercase), and a plain folded sort still splits "#" (symbols
// past 'z'), either way emitting duplicate getArtists index sections.
func TestArtistIndexFoldsCase(t *testing.T) {
	rows := []track{
		{PID: "tr-1", AlbumArtist: "alpha ensemble", Album: "One"},
		{PID: "tr-2", AlbumArtist: "Beta Band", Album: "Two"},
		{PID: "tr-3", AlbumArtist: "Ann", Album: "Three"},
		{PID: "tr-4", AlbumArtist: "beta quartet", Album: "Four"},
		{PID: "tr-5", AlbumArtist: "~exotic", Album: "Five"},
		{PID: "tr-6", AlbumArtist: "9th Symphony", Album: "Six"},
	}
	idx := buildIndex(rows, nil)
	want := []string{"9th Symphony", "~exotic", "alpha ensemble", "Ann", "Beta Band", "beta quartet"}
	if len(idx.artists) != len(want) {
		t.Fatalf("artists = %d, want %d", len(idx.artists), len(want))
	}
	for i, a := range idx.artists {
		if a.name != want[i] {
			t.Fatalf("artist order[%d] = %q, want %q", i, a.name, want[i])
		}
	}
	// Each index letter forms exactly one contiguous run.
	seen := map[string]bool{}
	last := ""
	for _, a := range idx.artists {
		letter := indexLetter(a.name)
		if letter != last && seen[letter] {
			t.Fatalf("index letter %q appears in two separate runs", letter)
		}
		seen[letter] = true
		last = letter
	}
}

// A group the catalog holds an entity for is keyed and identified by
// that entity; a loose track, which has no album row, keeps the minted
// identifier. A real library mixes both shapes, so both must work in one
// index.
func TestIndexMixesEntityAndMintedIDs(t *testing.T) {
	rows := []track{
		{PID: "tr-1", Title: "One", Artist: "Ensemble", AlbumArtist: "Ensemble", Album: "Cataloged",
			AlbumArtistPID: "ar-A", AlbumPID: "al-A"},
		{PID: "tr-2", Title: "Loose", Artist: "Ensemble", AlbumArtist: "Ensemble", Album: "Uncataloged",
			AlbumArtistPID: "ar-A"},
	}
	idx := buildIndex(rows, nil)

	if len(idx.artists) != 1 || idx.artists[0].id != "ar-A" {
		t.Fatalf("artists = %+v, want one keyed on ar-A", idx.artists)
	}
	if len(idx.albums) != 2 {
		t.Fatalf("albums = %d, want 2", len(idx.albums))
	}
	cataloged := idx.albumForTrack(rows[0])
	if cataloged == nil || cataloged.id != "al-A" || cataloged.pid != "al-A" {
		t.Fatalf("cataloged album = %+v, want id and pid al-A", cataloged)
	}
	loose := idx.albumForTrack(rows[1])
	if loose == nil || loose.pid != "" || loose.id != encodeAlbumID("Ensemble", "Uncataloged") {
		t.Fatalf("loose album = %+v, want a minted id and no pid", loose)
	}
	// A song response links to the album its browse response carries.
	if got := songChild(rows[0], cataloged); got.AlbumID != "al-A" || got.ArtistID != "ar-A" {
		t.Fatalf("song links = %q / %q, want al-A / ar-A", got.AlbumID, got.ArtistID)
	}

	// Both identifiers resolve through the shared lookups.
	if idx.findAlbum("al-A") != cataloged {
		t.Error("entity album id does not resolve")
	}
	if idx.findAlbum(loose.id) != loose {
		t.Error("minted album id does not resolve")
	}
	if idx.findArtist("ar-A") != idx.artists[0] {
		t.Error("entity artist id does not resolve")
	}
	if idx.findAlbum("no-such-id") != nil || idx.findArtist("no-such-id") != nil {
		t.Error("an unknown id resolved to something")
	}
}

// An identifier a client cached before the surface moved to entity pids
// still resolves through the display-key fallback, so a cutover does not
// invalidate every stored playlist and favorite in the wild.
func TestCachedMintedIDStillResolves(t *testing.T) {
	rows := []track{
		{PID: "tr-1", Artist: "Ensemble", AlbumArtist: "Ensemble", Album: "Cataloged",
			AlbumArtistPID: "ar-A", AlbumPID: "al-A"},
	}
	idx := buildIndex(rows, nil)

	al := idx.findAlbum(encodeAlbumID("Ensemble", "Cataloged"))
	if al == nil || al.pid != "al-A" {
		t.Fatalf("cached minted album id resolved to %+v, want the al-A entity", al)
	}
	a := idx.findArtist(encodeArtistID("Ensemble"))
	if a == nil || a.pid != "ar-A" {
		t.Fatalf("cached minted artist id resolved to %+v, want the ar-A entity", a)
	}
	// The responses hand out the entity id, so a client that follows one
	// migrates itself off the cached form.
	if al.id3().ID != "al-A" || a.id3().ID != "ar-A" {
		t.Fatal("responses still carry the minted ids")
	}
}

// A track with no album-artist tag groups under its own artist, in pid
// space exactly as in display space: the service mirrors the display
// fallback onto AlbumArtistPID, and without it the track would carry no
// album-artist identity and drop out of the artist index.
func TestTrackWithoutAlbumArtistGroupsUnderItsArtist(t *testing.T) {
	rows := []track{
		// AlbumArtist and AlbumArtistPID both carry the service's
		// track-artist fallback.
		{PID: "tr-1", Artist: "Soloist", AlbumArtist: "Soloist", Album: "Recital",
			AlbumArtistPID: "ar-S", AlbumPID: "al-R"},
	}
	idx := buildIndex(rows, nil)
	if len(idx.artists) != 1 {
		t.Fatalf("artists = %d, want 1", len(idx.artists))
	}
	a := idx.artists[0]
	if a.id != "ar-S" || a.name != "Soloist" || len(a.albums) != 1 {
		t.Fatalf("artist = %+v, want the soloist with one album", a)
	}
}

// Two tracks of one entity whose tags spell it differently must produce
// one stable label. Before entity keying they were separate groups; now
// they are one, and taking the name from whichever row the sweep reached
// first would make a cached, golden-tested index nondeterministic. The
// catalog's own name settles it.
func TestEntityNameIsCanonicalNotFirstSeen(t *testing.T) {
	rows := []track{
		{PID: "tr-1", Artist: "beatles", AlbumArtist: "beatles", Album: "revolver",
			AlbumArtistPID: "ar-B", AlbumPID: "al-R"},
		{PID: "tr-2", Artist: "The Beatles", AlbumArtist: "The Beatles", Album: "Revolver",
			AlbumArtistPID: "ar-B", AlbumPID: "al-R"},
	}
	names := map[string]string{"ar-B": "The Beatles", "al-R": "Revolver"}

	idx := buildIndex(rows, names)
	if len(idx.artists) != 1 || idx.artists[0].name != "The Beatles" {
		t.Fatalf("artists = %+v, want one named The Beatles", idx.artists)
	}
	if len(idx.albums) != 1 || idx.albums[0].name != "Revolver" || idx.albums[0].artist != "The Beatles" {
		t.Fatalf("albums = %+v, want one Revolver by The Beatles", idx.albums)
	}

	// Reversing the sweep order changes nothing.
	rev := buildIndex([]track{rows[1], rows[0]}, names)
	if rev.artists[0].name != "The Beatles" || rev.albums[0].name != "Revolver" {
		t.Fatalf("reversed sweep = %q / %q, want the same canonical names",
			rev.artists[0].name, rev.albums[0].name)
	}
}

// The reshape that changes membership rather than just identifiers: a
// compilation whose tracks each carry their own artist tag and no album
// artist used to split into one album per artist, because the album key
// was artist plus title. Keyed on the album entity they are the one
// album they always were, and every contributing artist still reaches
// it.
func TestCompilationCollapsesIntoOneAlbum(t *testing.T) {
	rows := []track{
		{PID: "tr-1", Title: "One", Artist: "Ensemble", AlbumArtist: "Ensemble", Album: "Sampler",
			AlbumArtistPID: "ar-E", AlbumPID: "al-S"},
		{PID: "tr-2", Title: "Two", Artist: "Quartet", AlbumArtist: "Quartet", Album: "Sampler",
			AlbumArtistPID: "ar-Q", AlbumPID: "al-S"},
	}
	idx := buildIndex(rows, map[string]string{
		"ar-E": "Ensemble", "ar-Q": "Quartet", "al-S": "Sampler",
	})

	if len(idx.albums) != 1 {
		t.Fatalf("albums = %d, want the compilation to be one album", len(idx.albums))
	}
	al := idx.albums[0]
	if len(al.tracks) != 2 {
		t.Fatalf("album holds %d tracks, want both", len(al.tracks))
	}
	if len(idx.artists) != 2 {
		t.Fatalf("artists = %d, want both contributors", len(idx.artists))
	}
	// Neither contributor is left albumless: an artist whose only
	// appearance is the compilation must still browse to it.
	for _, a := range idx.artists {
		if len(a.albums) != 1 || a.albums[0] != al {
			t.Fatalf("artist %q albums = %+v, want the shared compilation", a.name, a.albums)
		}
	}
	// The album itself carries one artist id, which is all the protocol
	// allows.
	if al.artistID == "" {
		t.Fatal("the compilation carries no artist id")
	}
}

// A minted group has no catalog entity behind it, so there is nothing
// for an entity star or rating to write to. The refusal names that
// reason rather than claiming the server cannot do entity stars at all.
func TestMintedGroupRefusesEntityStar(t *testing.T) {
	rows := []track{
		{PID: "tr-1", Artist: "Ensemble", AlbumArtist: "Ensemble", Album: "Cataloged",
			AlbumArtistPID: "ar-A", AlbumPID: "al-A"},
		{PID: "tr-2", Artist: "Nobody", AlbumArtist: "Nobody", Album: "Loose"},
	}
	idx := buildIndex(rows, nil)

	loose := idx.albumForTrack(rows[1])
	if loose == nil || loose.pid != "" {
		t.Fatalf("loose album = %+v, want a minted bucket", loose)
	}
	pid, reason := resolveEntityID(idx, loose.id, wantAlbum)
	if pid != "" {
		t.Errorf("a minted album resolved to entity pid %q", pid)
	}
	if !strings.Contains(reason, "no catalog album") {
		t.Errorf("refusal = %q, want it to name the missing catalog album", reason)
	}

	// The entity-backed one resolves, and so does its artist.
	if pid, reason := resolveEntityID(idx, "al-A", wantAlbum); pid != "al-A" || reason != "" {
		t.Errorf("entity album resolved to %q (%q)", pid, reason)
	}
	if pid, reason := resolveEntityID(idx, "ar-A", wantArtist); pid != "ar-A" || reason != "" {
		t.Errorf("entity artist resolved to %q (%q)", pid, reason)
	}
	// An unknown id is a plain not-found, named for the kind the caller
	// said it had.
	if _, reason := resolveEntityID(idx, "nonsense", wantAlbum); reason != "no such album" {
		t.Errorf("unknown album refusal = %q", reason)
	}
	if _, reason := resolveEntityID(idx, "nonsense", wantArtist); reason != "no such artist" {
		t.Errorf("unknown artist refusal = %q", reason)
	}

	// A folder-mode id says nothing about which kind it is, so an
	// unscoped lookup searches both and each entity still resolves.
	if pid, _ := resolveEntityID(idx, "al-A", ""); pid != "al-A" {
		t.Errorf("unscoped album resolved to %q", pid)
	}
	if pid, _ := resolveEntityID(idx, "ar-A", ""); pid != "ar-A" {
		t.Errorf("unscoped artist resolved to %q", pid)
	}
	if _, reason := resolveEntityID(idx, "nonsense", ""); reason != "no such album or artist" {
		t.Errorf("unscoped unknown refusal = %q", reason)
	}
}
