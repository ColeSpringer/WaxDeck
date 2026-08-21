package api

import (
	"strings"
	"testing"
)

// TestArtSourceReportsTheRungThatAnswered covers the source mark's read
// side end to end: an item that holds its own cover reports where it
// came from, an album with no cover of its own reports the member
// track's answer and names the rung it came off, and the byte endpoint
// carries the same four values as headers for a consumer that has only
// that response to read.
func TestArtSourceReportsTheRungThatAnswered(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	page := h.items(t, "")
	if len(page.Items) == 0 {
		t.Fatal("no items in the demo library")
	}
	var pid, albumPid string
	for _, it := range page.Items {
		if it.AlbumPid != nil && *it.AlbumPid != "" {
			pid, albumPid = it.Pid, *it.AlbumPid
			break
		}
	}
	if pid == "" {
		t.Fatal("no demo item carries an album entity")
	}
	wantStatus(t, metadataPutBytes(t, h.ts, "/api/v1/items/"+pid+"/artwork", h.token, tinyPNG(t)),
		200, "set front")

	// A cover set through the curation surface is the user's, and the
	// rung that answered is the item's own.
	item := decode[Item](t, get(t, h.ts, "/api/v1/items/"+pid, h.token))
	if item.ArtSource == nil {
		t.Fatal("the item detail read reports no art source for a cover it holds")
	}
	if item.ArtSource.Source != "user" {
		t.Errorf("item art source = %q, want user", item.ArtSource.Source)
	}
	if item.ArtSource.Level == nil || *item.ArtSource.Level != "track" {
		t.Errorf("item art level = %v, want track", item.ArtSource.Level)
	}

	// An album with no cover of its own answers from the member track,
	// and says so rather than claiming the album made the choice. This
	// is the case the own-level read cannot see, and the reason the
	// detail reads resolve instead of listing slots. Clearing the
	// album's own cover is what puts it in that state.
	albumArt := "/api/v1/entities/album/" + albumPid + "/artwork"
	wantStatus(t, h.deleteReq(t, albumArt), 204, "clear the album's own cover")
	wantStatus(t, putJSON(t, h.ts, albumArt+"/lock", h.token, map[string]any{"locked": false}),
		200, "leave the album unpinned")
	album := decode[AlbumDetail](t, get(t, h.ts, "/api/v1/albums/"+albumPid, h.token))
	if album.ArtSource == nil {
		t.Fatal("the album detail read reports no art source for a cover it resolves")
	}
	if album.ArtSource.Derived == nil || !*album.ArtSource.Derived {
		t.Errorf("album art derived = %v, want the member track's cover marked as borrowed",
			album.ArtSource.Derived)
	}
	if album.ArtSource.Source != "user" {
		t.Errorf("album art source = %q, want the member track's own answer",
			album.ArtSource.Source)
	}

	// The same four values on the byte response, for a consumer holding
	// nothing else. WaxDeck's own clients read the JSON: a browser gives
	// an <img> caller no access to these.
	resp := getArt(t, h, "/api/v1/items/"+pid+"/art", "")
	resp.Body.Close()
	if got := resp.Header.Get("X-Art-Source"); got != "user" {
		t.Errorf("X-Art-Source = %q, want user", got)
	}
	if got := resp.Header.Get("X-Art-Level"); got != "track" {
		t.Errorf("X-Art-Level = %q, want track", got)
	}
}

// TestArtRolesReportProvenanceAndTheLock covers the artwork manager's
// read: each own-level slot names where its image came from, and the
// front slot reports whether it is pinned.
func TestArtRolesReportProvenanceAndTheLock(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	page := h.items(t, "")
	if len(page.Items) == 0 {
		t.Fatal("no items in the demo library")
	}
	pid := page.Items[0].Pid
	wantStatus(t, metadataPutBytes(t, h.ts, "/api/v1/items/"+pid+"/artwork", h.token, tinyPNG(t)),
		200, "set front")

	roles := decode[ArtRoles](t, get(t, h.ts, "/api/v1/items/"+pid+"/art-roles", h.token))
	front, ok := roleNamed(roles, "front")
	if !ok {
		t.Fatalf("art-roles missing front: %+v", roles.Roles)
	}
	if front.Source == nil || *front.Source != "user" {
		t.Errorf("front slot source = %v, want user", front.Source)
	}
	// Setting item artwork pins by default, which is what carries the
	// chosen cover through an enrichment run.
	if front.Locked == nil || !*front.Locked {
		t.Errorf("front slot locked = %v, want the default pin", front.Locked)
	}
	if roles.ArtSource == nil || roles.ArtSource.Source != "user" {
		t.Errorf("art-roles art source = %+v, want the resolved user cover", roles.ArtSource)
	}
}

// TestItemPinnedWithNothingBehindIt is the state that used to be
// invisible: a cover cleared and then pinned refuses every later write
// and shows nothing, with no way to tell that from an entity that simply
// has no cover yet. It now reports as a front slot with a pin and no
// format.
func TestItemPinnedWithNothingBehindIt(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	page := h.items(t, "")
	if len(page.Items) == 0 {
		t.Fatal("no items in the demo library")
	}
	pid := page.Items[0].Pid

	// Clear (which leaves the pin as it stands, and nothing has pinned
	// this one), then pin the empty slot through the locks surface.
	wantStatus(t, h.deleteReq(t, "/api/v1/items/"+pid+"/artwork"), 204, "clear front")
	wantStatus(t, putJSON(t, h.ts, "/api/v1/items/"+pid+"/locks", h.token,
		map[string]any{"fields": []string{"art"}, "locked": true}), 200, "pin art")

	roles := decode[ArtRoles](t, get(t, h.ts, "/api/v1/items/"+pid+"/art-roles", h.token))
	front, ok := roleNamed(roles, "front")
	if !ok {
		t.Fatalf("a pinned empty front slot is not reported: %+v", roles.Roles)
	}
	if front.Locked == nil || !*front.Locked {
		t.Errorf("front locked = %v, want true", front.Locked)
	}
	if front.Format != nil && *front.Format != "" {
		t.Errorf("front format = %v, want none: the pin has nothing behind it", front.Format)
	}
}

// TestEntityArtworkLock covers the pin endpoint: it reads and writes a
// catalog entity's pin without touching the cover, it is the way out of
// a cleared-and-pinned cover, and it refuses a playlist.
func TestEntityArtworkLock(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	page := h.items(t, "")
	var albumPid string
	for _, it := range page.Items {
		if it.AlbumPid != nil && *it.AlbumPid != "" {
			albumPid = *it.AlbumPid
			break
		}
	}
	if albumPid == "" {
		t.Fatal("no demo item carries an album entity")
	}
	base := "/api/v1/entities/album/" + albumPid + "/artwork"

	// Setting an album cover pins it, so it survives an enrichment run.
	wantStatus(t, metadataPutBytes(t, h.ts, base, h.token, tinyPNG(t)), 200, "set album cover")
	if !entityPinned(t, h, base+"/lock") {
		t.Fatal("a hand-set album cover is not pinned")
	}

	// Clearing carries the pin across: an album cover cleared by an
	// administrator means "there is no cover", not "give me the derived
	// one back", and the pin is what says so.
	wantStatus(t, h.deleteReq(t, base), 204, "clear album cover")
	if !entityPinned(t, h, base+"/lock") {
		t.Fatal("clearing an album cover dropped the pin the administrator set")
	}

	// Which is exactly the state the endpoint exists to undo. Setting a
	// cover cannot express it: that always writes the image slot too.
	wantStatus(t, putJSON(t, h.ts, base+"/lock", h.token, map[string]any{"locked": false}),
		200, "unpin")
	if entityPinned(t, h, base+"/lock") {
		t.Fatal("the pin survived an explicit unpin")
	}

	// A playlist is refused by construction. Its cover authority is
	// WaxDeck's own origin marker, and a pin left standing on one makes
	// the generated mosaic unwritable on every read, forever.
	created := h.postJSON(t, "/api/v1/playlists", map[string]any{"name": "pinned", "kind": "static"})
	if created.StatusCode != 201 {
		t.Fatalf("playlist create status = %d", created.StatusCode)
	}
	pl := decode[Playlist](t, created)
	plLock := "/api/v1/entities/playlist/" + pl.Pid + "/artwork/lock"
	wantStatus(t, get(t, h.ts, plLock, h.token), 400, "read a playlist pin")
	wantStatus(t, putJSON(t, h.ts, plLock, h.token, map[string]any{"locked": true}),
		400, "pin a playlist")
}

// TestProvenanceCarriesArtifactRows pins the meaning change the upstream
// overlay makes library-wide. An item holding a cover reports an "art"
// provenance row with no value, so a non-empty provenance list no longer
// means the item was curated - and the editor's scalar field table must
// not grow an "art" entry off the back of it.
func TestProvenanceCarriesArtifactRows(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	page := h.items(t, "")
	if len(page.Items) == 0 {
		t.Fatal("no items in the demo library")
	}
	pid := page.Items[0].Pid
	wantStatus(t, metadataPutBytes(t, h.ts, "/api/v1/items/"+pid+"/artwork", h.token, tinyPNG(t)),
		200, "set front")

	meta := h.itemMeta(t, pid)
	var art *FieldProvenance
	for i, p := range meta.Provenance {
		if p.Field == "art" {
			art = &meta.Provenance[i]
		}
	}
	if art == nil {
		t.Fatalf("no art provenance row for an item holding a cover: %+v", meta.Provenance)
	}
	if art.Source != "user" {
		t.Errorf("art row source = %q, want user", art.Source)
	}
	// The scalar field table is built from the editor's own vocabulary,
	// which holds neither art nor lyrics, and gates on a non-empty
	// value besides. Both halves matter: an "art" row reaching the field
	// list would draw an uneditable text box on every curated item.
	if _, ok := meta.Fields["art"]; ok {
		t.Errorf("the artifact row reached the editor's scalar fields: %+v", meta.Fields)
	}
}

// TestLyricsSourceVocabulary pins the vocabulary move. Upstream retired
// the lrc/embedded pair - which named the two file formats rather than
// the producer, and had nowhere to put a fetched copy - for the same
// words artwork uses. A hand-set copy reads "user" on both surfaces.
func TestLyricsSourceVocabulary(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	page := h.items(t, "")
	if len(page.Items) == 0 {
		t.Fatal("no items in the demo library")
	}
	pid := page.Items[0].Pid
	wantStatus(t, putJSON(t, h.ts, "/api/v1/items/"+pid+"/lyrics", h.token,
		map[string]any{"lrc": "[00:01.00]a line"}), 200, "set lyrics")

	ly := decode[Lyrics](t, get(t, h.ts, "/api/v1/items/"+pid+"/lyrics", h.token))
	if ly.Source != "user" {
		t.Errorf("lyrics source = %q, want user", ly.Source)
	}
	meta := h.itemMeta(t, pid)
	if meta.Lyrics == nil || meta.Lyrics.Source != "user" {
		t.Errorf("editor lyrics source = %+v, want user", meta.Lyrics)
	}
	// The retired words must not come back through either surface.
	for _, got := range []string{ly.Source, meta.Lyrics.Source} {
		if got == "lrc" || got == "embedded" {
			t.Errorf("source = %q, one of the retired format names", got)
		}
	}
}

func roleNamed(roles ArtRoles, role string) (ArtRoleInfo, bool) {
	for _, r := range roles.Roles {
		if strings.EqualFold(string(r.Role), role) {
			return r, true
		}
	}
	return ArtRoleInfo{}, false
}

func entityPinned(t *testing.T, h *harness, path string) bool {
	t.Helper()
	resp := get(t, h.ts, path, h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("artwork lock GET status = %d", resp.StatusCode)
	}
	return decode[ArtworkLock](t, resp).Locked
}
