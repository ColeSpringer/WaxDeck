package service

import (
	"bytes"
	"context"
	"errors"
	"image"
	"image/color"
	"image/png"
	"testing"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// coverPNG encodes a distinct solid square, standing in for one album's
// artwork. The color varies the bytes, so the catalog hashes each one
// differently -- which is what the mosaic's deduplication keys on.
func coverPNG(t *testing.T, shade uint8) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 120, 120))
	for y := range 120 {
		for x := range 120 {
			img.Set(x, y, color.RGBA{shade, uint8(255 - int(shade)), shade / 2, 255})
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// fixtureItemPIDs returns the fixture library's item pids in listing
// order, which is the order a playlist built from them holds.
func fixtureItemPIDs(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) []string {
	t.Helper()
	page, err := svc.Items(ctx, uc, ItemFilter{}, "", 50)
	if err != nil {
		t.Fatalf("listing items: %v", err)
	}
	if len(page.Items) < 4 {
		t.Fatalf("fixture has %d items, want at least 4", len(page.Items))
	}
	pids := make([]string, 0, len(page.Items))
	for _, it := range page.Items {
		pids = append(pids, it.PID)
	}
	return pids
}

// giveCovers attaches artwork to the named items. Same bytes for every
// item when only one cover is passed.
func giveCovers(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, pids []string, covers ...[]byte) {
	t.Helper()
	for i, apiPID := range pids {
		raw := covers[i%len(covers)]
		it, err := svc.getVisibleItem(ctx, uc, apiPID)
		if err != nil {
			t.Fatalf("resolving %s: %v", apiPID, err)
		}
		if err := svc.lib.SetItemArt(ctx, it.PID, model.ArtRoleFront, raw, waxbin.ArtEditOptions{
			Lock: model.LockOff, Force: true,
		}); err != nil {
			t.Fatalf("setting art on %s: %v", apiPID, err)
		}
	}
}

// playlistWith creates a static playlist holding the given items and
// returns its API pid.
func playlistWith(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, name string, pids []string) string {
	t.Helper()
	pl, err := svc.CreatePlaylist(ctx, uc, PlaylistCreate{
		Name: name, Kind: "static", Visibility: "private", ItemPIDs: pids,
	})
	if err != nil {
		t.Fatalf("creating playlist: %v", err)
	}
	return pl.PID
}

// playlistArt reads a playlist's stored cover through the same endpoint
// path a client uses.
func playlistArt(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, plPID string) ArtBlob {
	t.Helper()
	blob, err := svc.Art(ctx, uc, plPID, "", 0)
	if err != nil {
		t.Fatalf("reading playlist art: %v", err)
	}
	return blob
}

// TestPlaylistMosaicFromDistinctCovers is the default cover: four
// members with four different covers tile into one square image, stored
// on the playlist so it serves through the same art path, thumbnail
// cache, and ETag as every other cover.
func TestPlaylistMosaicFromDistinctCovers(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)[:4]
	giveCovers(t, ctx, svc, uc, pids,
		coverPNG(t, 20), coverPNG(t, 90), coverPNG(t, 160), coverPNG(t, 230))

	plPID := playlistWith(t, ctx, svc, uc, "Four covers", pids)
	blob := playlistArt(t, ctx, svc, uc, plPID)
	cfg, format, err := image.DecodeConfig(bytes.NewReader(blob.Bytes))
	if err != nil {
		t.Fatalf("the stored cover does not decode: %v", err)
	}
	if format != "jpeg" || cfg.Width != coverMosaicSize || cfg.Height != coverMosaicSize {
		t.Errorf("cover = %s %dx%d, want a %d-square jpeg mosaic",
			format, cfg.Width, cfg.Height, coverMosaicSize)
	}
	// The playlist reports the cover, so a grid knows to fetch it.
	got, err := svc.PlaylistByPID(ctx, uc, plPID)
	if err != nil {
		t.Fatal(err)
	}
	if !got.HasArt {
		t.Error("hasArt = false with a cover stored")
	}
}

// TestPlaylistCoverDoesNotTileOneAlbum is the deduplication rule: a
// playlist drawn from a single album resolves the same cover for every
// member, and tiling it four times would look like a bug rather than a
// mosaic. It shows the cover once instead.
func TestPlaylistCoverDoesNotTileOneAlbum(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)[:4]
	shared := coverPNG(t, 120)
	giveCovers(t, ctx, svc, uc, pids, shared)

	plPID := playlistWith(t, ctx, svc, uc, "One album", pids)
	blob := playlistArt(t, ctx, svc, uc, plPID)
	if !bytes.Equal(blob.Bytes, shared) {
		cfg, format, err := image.DecodeConfig(bytes.NewReader(blob.Bytes))
		t.Fatalf("cover is not the single member cover (got %s %dx%d, err %v); "+
			"four copies of one album's art is not a mosaic", format, cfg.Width, cfg.Height, err)
	}
}

// TestPlaylistCoverFollowsMembership pins the refresh: the fingerprint
// is over the member list, so adding a member with different art
// rebuilds the cover, and a read that changes nothing does not.
func TestPlaylistCoverFollowsMembership(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)
	giveCovers(t, ctx, svc, uc, pids[:4],
		coverPNG(t, 20), coverPNG(t, 90), coverPNG(t, 160), coverPNG(t, 230))

	// Three members: below the mosaic threshold, so the first cover shows.
	plPID := playlistWith(t, ctx, svc, uc, "Growing", pids[:3])
	before := playlistArt(t, ctx, svc, uc, plPID)

	// A read that changes nothing leaves the cover alone.
	if _, err := svc.PlaylistItems(ctx, uc, plPID, "", 50); err != nil {
		t.Fatal(err)
	}
	steady := playlistArt(t, ctx, svc, uc, plPID)
	if !bytes.Equal(before.Bytes, steady.Bytes) {
		t.Error("the cover was rebuilt by a read that changed no members")
	}

	// A fourth distinct cover crosses the threshold and tiles.
	if err := svc.AddPlaylistItems(ctx, uc, plPID, pids[3:4]); err != nil {
		t.Fatal(err)
	}
	after := playlistArt(t, ctx, svc, uc, plPID)
	if bytes.Equal(before.Bytes, after.Bytes) {
		t.Error("the cover did not follow the membership change")
	}
	cfg, _, err := image.DecodeConfig(bytes.NewReader(after.Bytes))
	if err != nil || cfg.Width != coverMosaicSize {
		t.Errorf("cover after the fourth member = %dx%d (err %v), want the mosaic",
			cfg.Width, cfg.Height, err)
	}
}

// TestPlaylistCustomCoverWinsAndClearsBack is the whole provenance
// point: the catalog cannot tell an upload from a mosaic (both are a
// front-role row on the playlist that sets HasArt), so without the
// recorded origin a membership change would silently overwrite the
// owner's cover, and clearing it would leave the playlist bare.
func TestPlaylistCustomCoverWinsAndClearsBack(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)[:4]
	giveCovers(t, ctx, svc, uc, pids,
		coverPNG(t, 20), coverPNG(t, 90), coverPNG(t, 160), coverPNG(t, 230))
	plPID := playlistWith(t, ctx, svc, uc, "Mine", pids)
	mosaic := playlistArt(t, ctx, svc, uc, plPID)

	custom := coverPNG(t, 200)
	if _, err := svc.SetEntityArtwork(ctx, uc, "playlist", plPID, "", custom, false); err != nil {
		t.Fatalf("uploading a playlist cover: %v", err)
	}
	if got := playlistArt(t, ctx, svc, uc, plPID); !bytes.Equal(got.Bytes, custom) {
		t.Fatal("the uploaded cover is not what the art endpoint serves")
	}

	// A membership change must not take the owner's cover away.
	if err := svc.RemovePlaylistItemAt(ctx, uc, plPID, len(pids)-1); err != nil {
		t.Fatal(err)
	}
	if got := playlistArt(t, ctx, svc, uc, plPID); !bytes.Equal(got.Bytes, custom) {
		t.Error("a membership change overwrote the owner's cover with a mosaic")
	}
	// Put the fourth member back, so the regenerated cover is the mosaic
	// again rather than the single-cover fallback three members give.
	if err := svc.AddPlaylistItems(ctx, uc, plPID, pids[3:4]); err != nil {
		t.Fatal(err)
	}

	// Clearing hands the slot back to the generated cover.
	if err := svc.ClearEntityArtwork(ctx, uc, "playlist", plPID, ""); err != nil {
		t.Fatalf("clearing the playlist cover: %v", err)
	}
	back := playlistArt(t, ctx, svc, uc, plPID)
	if bytes.Equal(back.Bytes, custom) {
		t.Fatal("the cleared cover is still being served")
	}
	cfg, _, err := image.DecodeConfig(bytes.NewReader(back.Bytes))
	if err != nil || cfg.Width != coverMosaicSize {
		t.Errorf("cover after the clear = %dx%d (err %v), want the mosaic back", cfg.Width, cfg.Height, err)
	}
	if len(mosaic.Bytes) == 0 {
		t.Error("the fixture never produced a mosaic to compare against")
	}
}

// TestPlaylistArtHonorsVisibility is why the playlist case goes through
// resolvePlaylist rather than straight to the art level like an album
// or artist: a playlist pid is user-facing and appears in the owner's
// own listings, so a private playlist's cover has to read as absent to
// everyone else.
func TestPlaylistArtHonorsVisibility(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)[:4]
	giveCovers(t, ctx, svc, uc, pids,
		coverPNG(t, 20), coverPNG(t, 90), coverPNG(t, 160), coverPNG(t, 230))
	plPID := playlistWith(t, ctx, svc, uc, "Private", pids)
	playlistArt(t, ctx, svc, uc, plPID)

	acct, err := svc.CreateAccount(ctx, AccountCreate{Username: "listener", Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	other, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Art(ctx, other, plPID, "", 0); KindOf(err) != KindNotFound {
		t.Fatalf("another user's read of a private playlist's cover = %v, want not-found", err)
	}
	// Editing it is refused too, not merely hidden.
	if _, err := svc.SetEntityArtwork(ctx, other, "playlist", plPID, "", coverPNG(t, 10), false); err == nil {
		t.Error("a non-owner uploaded a cover onto someone else's playlist")
	}

	// Sharing it opens the read, and still not the write.
	shared := "shared"
	if _, err := svc.UpdatePlaylist(ctx, uc, plPID, PlaylistUpdate{Visibility: &shared}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Art(ctx, other, plPID, "", 0); err != nil {
		t.Errorf("a shared playlist's cover should read for everyone: %v", err)
	}
	if err := svc.ClearEntityArtwork(ctx, other, "playlist", plPID, ""); KindOf(err) != KindForbidden {
		t.Errorf("a non-owner clearing a shared playlist's cover = %v, want forbidden", err)
	}
}

// TestPlaylistDeleteDropsCover covers the upstream fix on our own data:
// art rows key on plain rowids, so a cover outliving its playlist would
// surface on whatever later inherited the id. The catalog drops the art
// with the playlist; this drops the provenance row beside it.
func TestPlaylistDeleteDropsCover(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)[:4]
	giveCovers(t, ctx, svc, uc, pids,
		coverPNG(t, 20), coverPNG(t, 90), coverPNG(t, 160), coverPNG(t, 230))
	plPID := playlistWith(t, ctx, svc, uc, "Doomed", pids)
	playlistArt(t, ctx, svc, uc, plPID)

	_, catalogPID, _ := parseAPIPID(plPID)
	if _, err := svc.db.PlaylistCoverFor(ctx, string(catalogPID)); err != nil {
		t.Fatalf("no cover state recorded before the delete: %v", err)
	}
	if err := svc.DeletePlaylist(ctx, uc, plPID); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.db.PlaylistCoverFor(ctx, string(catalogPID)); !errors.Is(err, wdb.ErrNotFound) {
		t.Errorf("cover state survived the delete: %v", err)
	}
	if _, err := svc.lib.ResolveArt(ctx,
		model.EntityRef{Type: model.ArtPlaylist, PID: catalogPID}, model.ArtRoleFront, 0); err == nil {
		t.Error("the deleted playlist's art row is still resolvable")
	}
}

// TestPlaylistWithoutCoveredMembers leaves the slot empty rather than
// storing a blank tile, so a client draws its own placeholder -- and
// settles there. Generating nothing is a real answer for this member
// list, so a later read must not read the empty slot as a missing
// cover and re-resolve every member again.
func TestPlaylistWithoutCoveredMembers(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)[:2]
	plPID := playlistWith(t, ctx, svc, uc, "Bare", pids)
	if _, err := svc.PlaylistItems(ctx, uc, plPID, "", 50); err != nil {
		t.Fatal(err)
	}
	got, err := svc.PlaylistByPID(ctx, uc, plPID)
	if err != nil {
		t.Fatal(err)
	}
	if got.HasArt {
		t.Error("hasArt = true for a playlist whose members carry no art")
	}
	if _, err := svc.Art(ctx, uc, plPID, "", 0); err == nil {
		t.Error("the art endpoint answered for a playlist with no cover")
	}

	_, catalogPID, _ := parseAPIPID(plPID)
	first, err := svc.db.PlaylistCoverFor(ctx, string(catalogPID))
	if err != nil {
		t.Fatalf("no cover state recorded for an art-less playlist: %v", err)
	}
	if _, err := svc.PlaylistItems(ctx, uc, plPID, "", 50); err != nil {
		t.Fatal(err)
	}
	second, err := svc.db.PlaylistCoverFor(ctx, string(catalogPID))
	if err != nil {
		t.Fatal(err)
	}
	if second.UpdatedAtNS != first.UpdatedAtNS {
		t.Error("an art-less playlist regenerated its cover on a second read")
	}
}

// TestPlaylistCoverFollowsMemberArtwork is the staleness the member-pid
// fingerprint cannot see on its own: a member replacing its own cover in
// place moves no membership, so without the artwork epoch the mosaic
// built from the old art would survive until the membership next
// changed.
func TestPlaylistCoverFollowsMemberArtwork(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)[:4]
	giveCovers(t, ctx, svc, uc, pids,
		coverPNG(t, 20), coverPNG(t, 90), coverPNG(t, 160), coverPNG(t, 230))
	plPID := playlistWith(t, ctx, svc, uc, "Repainted", pids)
	before := playlistArt(t, ctx, svc, uc, plPID)

	// Swap one member's cover through the editor, which is what bumps the
	// epoch. The membership is untouched.
	if _, err := svc.SetItemArtwork(ctx, uc, pids[0], "", coverPNG(t, 250), false, false); err != nil {
		t.Fatalf("replacing a member cover: %v", err)
	}
	if _, err := svc.PlaylistItems(ctx, uc, plPID, "", 50); err != nil {
		t.Fatal(err)
	}
	after := playlistArt(t, ctx, svc, uc, plPID)
	if bytes.Equal(before.Bytes, after.Bytes) {
		t.Error("the mosaic kept a member's old cover after it was replaced")
	}

	// And it settles: a read that follows no artwork change rebuilds
	// nothing.
	_, catalogPID, _ := parseAPIPID(plPID)
	first, err := svc.db.PlaylistCoverFor(ctx, string(catalogPID))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.PlaylistItems(ctx, uc, plPID, "", 50); err != nil {
		t.Fatal(err)
	}
	second, err := svc.db.PlaylistCoverFor(ctx, string(catalogPID))
	if err != nil {
		t.Fatal(err)
	}
	if second.UpdatedAtNS != first.UpdatedAtNS {
		t.Error("the cover rebuilt on a read that followed no artwork change")
	}
}

// TestPlaylistCustomCoverIgnoresMemberArtwork keeps the epoch from
// reaching an owner's upload: it is not built from the members, so
// nothing about them should displace it.
func TestPlaylistCustomCoverIgnoresMemberArtwork(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)[:4]
	giveCovers(t, ctx, svc, uc, pids,
		coverPNG(t, 20), coverPNG(t, 90), coverPNG(t, 160), coverPNG(t, 230))
	plPID := playlistWith(t, ctx, svc, uc, "Mine only", pids)

	custom := coverPNG(t, 200)
	if _, err := svc.SetEntityArtwork(ctx, uc, "playlist", plPID, "", custom, false); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.SetItemArtwork(ctx, uc, pids[0], "", coverPNG(t, 250), false, false); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.PlaylistItems(ctx, uc, plPID, "", 50); err != nil {
		t.Fatal(err)
	}
	if got := playlistArt(t, ctx, svc, uc, plPID); !bytes.Equal(got.Bytes, custom) {
		t.Error("a member artwork change displaced the owner's cover")
	}
}

// TestSmartPlaylistRuleChangeRefreshesCover covers the rule edit: a new
// rule is a new member list, and the caller often goes back to the
// playlist grid, which loads no members and so would otherwise show the
// cover the old rule produced.
func TestSmartPlaylistRuleChangeRefreshesCover(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)[:4]
	giveCovers(t, ctx, svc, uc, pids,
		coverPNG(t, 20), coverPNG(t, 90), coverPNG(t, 160), coverPNG(t, 230))

	// A rule matching everything: four distinct covers, so a mosaic.
	wide := SmartRule{
		Root:  RuleNode{Type: "condition", Field: "mediaType", Op: "is", Value: "music"},
		Sorts: []RuleSort{{Field: "title"}},
	}
	pl, err := svc.CreatePlaylist(ctx, uc, PlaylistCreate{
		Name: "Smart cover", Kind: "smart", Visibility: "private", Rule: &wide,
	})
	if err != nil {
		t.Fatalf("creating a smart playlist: %v", err)
	}
	if _, err := svc.PlaylistItems(ctx, uc, pl.PID, "", 50); err != nil {
		t.Fatal(err)
	}
	before := playlistArt(t, ctx, svc, uc, pl.PID)

	// Narrow it to one artist, which drops the member set to a different
	// shape. The cover must follow on the update itself.
	narrow := SmartRule{
		Root:  RuleNode{Type: "condition", Field: "artist", Op: "is", Value: "Brass Nine"},
		Sorts: []RuleSort{{Field: "title"}},
	}
	got, err := svc.UpdatePlaylist(ctx, uc, pl.PID, PlaylistUpdate{Rule: &narrow})
	if err != nil {
		t.Fatalf("replacing the rule: %v", err)
	}
	if !got.HasArt {
		t.Error("hasArt = false right after a rule edit that still matches covered tracks")
	}
	after := playlistArt(t, ctx, svc, uc, pl.PID)
	if bytes.Equal(before.Bytes, after.Bytes) {
		t.Error("the cover still shows what the old rule matched")
	}
}

// exoticCover is a minimally valid AVIF header. The catalog accepts
// AVIF and HEIC covers by magic sniff rather than by decoding them, so a
// stored cover no Go decoder can read is a real state, not a corruption.
func exoticCover() []byte {
	out := make([]byte, 64)
	copy(out[4:], "ftypavif")
	return out
}

// TestPlaylistCoverSkipsUnusableMemberArt keeps one bad stored cover from
// costing the whole mosaic. A member whose art no decoder here reads (or
// whose header claims more pixels than the budget allows) is filtered out
// of the candidates, so four members with one bad cover fall back to the
// single-cover shape rather than failing to compose -- and the result is
// recorded, so the next read does not resolve every member again.
func TestPlaylistCoverSkipsUnusableMemberArt(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)[:4]
	good := coverPNG(t, 40)
	giveCovers(t, ctx, svc, uc, pids[:3], good, coverPNG(t, 120), coverPNG(t, 200))
	// An AVIF cover: the catalog stores exotics by magic sniff (no Go
	// decoder exists for them), so this is the real shape of a stored
	// cover that cannot be composited.
	giveCovers(t, ctx, svc, uc, pids[3:4], exoticCover())

	plPID := playlistWith(t, ctx, svc, uc, "One bad tile", pids)
	blob := playlistArt(t, ctx, svc, uc, plPID)
	// Three usable covers is below the mosaic threshold, so the first one
	// shows; the point is that a cover is served at all.
	if !bytes.Equal(blob.Bytes, good) {
		cfg, format, err := image.DecodeConfig(bytes.NewReader(blob.Bytes))
		t.Fatalf("cover = %s %dx%d (err %v), want the first usable member cover",
			format, cfg.Width, cfg.Height, err)
	}

	_, catalogPID, _ := parseAPIPID(plPID)
	first, err := svc.db.PlaylistCoverFor(ctx, string(catalogPID))
	if err != nil {
		t.Fatalf("no cover state recorded: %v", err)
	}
	if _, err := svc.PlaylistItems(ctx, uc, plPID, "", 50); err != nil {
		t.Fatal(err)
	}
	second, err := svc.db.PlaylistCoverFor(ctx, string(catalogPID))
	if err != nil {
		t.Fatal(err)
	}
	if second.UpdatedAtNS != first.UpdatedAtNS {
		t.Error("the cover was rebuilt on a second read; an unusable member should settle")
	}
}
