package api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"io"
	"math/rand"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"golang.org/x/image/tiff"

	waxlabel "github.com/colespringer/waxlabel"
	"github.com/colespringer/waxlabel/tag"

	"github.com/colespringer/waxdeck/fixtures"
)

// metadataReq sends a JSON request with an explicit verb and token; the
// harness verbs always use the admin token, and the metadata suite also
// exercises a non-admin caller.
func metadataReq(t *testing.T, ts *httptest.Server, method, path, token string, body any) *http.Response {
	t.Helper()
	var reader *bytes.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		reader = bytes.NewReader(raw)
	} else {
		reader = bytes.NewReader(nil)
	}
	req, _ := http.NewRequest(method, ts.URL+path, reader)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

// metadataPutBytes sends a raw octet-stream PUT (the artwork verbs).
func metadataPutBytes(t *testing.T, ts *httptest.Server, path, token string, data []byte) *http.Response {
	t.Helper()
	req, _ := http.NewRequest("PUT", ts.URL+path, bytes.NewReader(data))
	req.Header.Set("Content-Type", "application/octet-stream")
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

// tinyPNG encodes a small valid PNG for the artwork tests.
func tinyPNG(t *testing.T) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 4, 4))
	for x := 0; x < 4; x++ {
		for y := 0; y < 4; y++ {
			img.Set(x, y, color.RGBA{R: uint8(40 * x), G: uint8(40 * y), B: 128, A: 255})
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func (h *harness) itemMeta(t *testing.T, pid string) ItemMetadata {
	t.Helper()
	resp := get(t, h.ts, "/api/v1/items/"+pid+"/metadata", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("metadata GET status = %d", resp.StatusCode)
	}
	return decode[ItemMetadata](t, resp)
}

func containsString(list []string, want string) bool {
	for _, s := range list {
		if s == want {
			return true
		}
	}
	return false
}

func wantStatus(t *testing.T, resp *http.Response, want int, what string) {
	t.Helper()
	if resp.StatusCode != want {
		t.Fatalf("%s status = %d, want %d", what, resp.StatusCode, want)
	}
	resp.Body.Close()
}

func TestMetadataFieldsVocabulary(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	resp := get(t, h.ts, "/api/v1/metadata/fields", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("fields status = %d", resp.StatusCode)
	}
	vocab := decode[MetadataFields](t, resp)
	if len(vocab.Kinds) != 3 {
		t.Fatalf("kinds = %d, want 3", len(vocab.Kinds))
	}
	byKind := map[MediaType]KindFields{}
	for _, k := range vocab.Kinds {
		byKind[k.Kind] = k
	}
	field := func(k KindFields, name string) *EditableField {
		for i := range k.Fields {
			if k.Fields[i].Name == name {
				return &k.Fields[i]
			}
		}
		return nil
	}
	music := byKind["music"]
	if f := field(music, "title"); f == nil || !f.WriteBack {
		t.Fatalf("music title = %+v, want writeBack true", f)
	}
	if f := field(music, "isrc"); f == nil || !f.WriteBack {
		t.Fatalf("music isrc = %+v, want writeBack true", f)
	}
	if f := field(music, "composer_sort"); f == nil || !f.WriteBack {
		t.Fatalf("music composer_sort = %+v, want writeBack true", f)
	}
	if len(music.CreditRoles) != 11 {
		t.Fatalf("music roles = %d, want 11", len(music.CreditRoles))
	}
	book := byKind["audiobook"]
	if f := field(book, "author"); f == nil || !f.WriteBack {
		t.Fatalf("book author = %+v, want writeBack true", f)
	}
	if f := field(book, "author_sort"); f == nil || !f.WriteBack {
		t.Fatalf("book author_sort = %+v, want writeBack true", f)
	}
	for _, dbOnly := range []string{"subtitle", "asin", "isbn", "publisher", "edition", "description", "mbid"} {
		if f := field(book, dbOnly); f == nil || f.WriteBack {
			t.Fatalf("book %s = %+v, want writeBack false", dbOnly, f)
		}
	}
	roleWriteBack := map[string]bool{}
	for _, r := range book.CreditRoles {
		roleWriteBack[r.Name] = r.WriteBack
	}
	if !roleWriteBack["narrator"] || roleWriteBack["translator"] || roleWriteBack["editor"] {
		t.Fatalf("book roles = %+v", roleWriteBack)
	}
	pod := byKind["podcast"]
	for _, f := range pod.Fields {
		if f.WriteBack {
			t.Fatalf("podcast field %s claims write-back", f.Name)
		}
	}
	if len(pod.CreditRoles) != 0 {
		t.Fatalf("podcast roles = %d, want 0", len(pod.CreditRoles))
	}
	entities := map[string][]EditableField{}
	for _, e := range vocab.EntityTypes {
		entities[e.EntityType] = e.Fields
	}
	if len(entities["album"]) != 7 || len(entities["artist"]) != 2 || len(entities["release-group"]) != 3 {
		t.Fatalf("entity vocabulary = %+v", entities)
	}
	// The edition columns are advertised: country fans out to member
	// files, media stays database-only (MEDIA is per-medium, so an
	// album-level fan-out would stamp one value across mixed media).
	albumField := func(name string) *EditableField {
		for i := range entities["album"] {
			if entities["album"][i].Name == name {
				return &entities["album"][i]
			}
		}
		return nil
	}
	if f := albumField("country"); f == nil || !f.WriteBack {
		t.Fatalf("album country = %+v, want writeBack true", f)
	}
	if f := albumField("media"); f == nil || f.WriteBack {
		t.Fatalf("album media = %+v, want writeBack false", f)
	}
}

func TestMetadataEditorLifecycle(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	page := h.items(t, "")
	if len(page.Items) != 4 {
		t.Fatalf("scanned %d items, want 4", len(page.Items))
	}
	alpha, bravo := page.Items[0].Pid, page.Items[1].Pid
	charlie, delta := page.Items[2].Pid, page.Items[3].Pid

	// The full read shape on an untouched track.
	md := h.itemMeta(t, alpha)
	if md.Pid != alpha || md.MediaType != "music" {
		t.Fatalf("metadata identity = %+v", md)
	}
	if md.Fields["title"] != "Alpha Song" || md.Fields["artist"] != "Fixture Artist" || md.Fields["album"] != "Fixture Album" {
		t.Fatalf("fields = %+v", md.Fields)
	}
	if md.VirtualTrack || md.Unofficial || md.HasArtwork {
		t.Fatalf("flags = %+v", md)
	}
	// Present and empty, never null: a client reads "no issues", not
	// "the server did not look".
	if md.WriteBackIssues == nil || len(md.WriteBackIssues) != 0 {
		t.Fatalf("writeBackIssues = %+v", md.WriteBackIssues)
	}
	if len(md.LockedFields) != 0 || len(md.CustomTags) != 0 {
		t.Fatalf("fresh item carries locks or tags: %+v", md)
	}
	// Declared by the contract all along; the server sent neither, while
	// the same handles rode every item listing beside it.
	if md.ArtistPid == nil || !strings.HasPrefix(*md.ArtistPid, "ar-") {
		t.Errorf("metadata artistPid = %v, want the item's artist entity", md.ArtistPid)
	}
	if md.AlbumPid == nil || !strings.HasPrefix(*md.AlbumPid, "al-") {
		t.Errorf("metadata albumPid = %v, want the item's album entity", md.AlbumPid)
	}
	// And they agree with the listing's.
	if got := page.Items[0]; got.ArtistPid == nil || *got.ArtistPid != *md.ArtistPid {
		t.Errorf("listing artistPid = %v, editor %v", got.ArtistPid, md.ArtistPid)
	}
	// The third handle, minted with its own prefix. A scanned track gets
	// a release group off its album chain, so the fixtures carry one.
	if md.ReleaseGroupPid == nil || !strings.HasPrefix(*md.ReleaseGroupPid, "rg-") {
		t.Errorf("metadata releaseGroupPid = %v, want the item's release group", md.ReleaseGroupPid)
	} else if resp := h.patchJSON(t, "/api/v1/entities/release-group/"+*md.ReleaseGroupPid,
		map[string]any{"edits": map[string]string{"sort": "Fixture Album, The"}}); resp.StatusCode != 200 {
		// The pid the read mints is a pid the write takes back.
		resp.Body.Close()
		t.Errorf("editing the release group the read named = %d, want 200", resp.StatusCode)
	} else {
		resp.Body.Close()
	}

	// A scalar edit persists and locks by default.
	resp := h.patchJSON(t, "/api/v1/items/"+alpha+"/metadata", map[string]any{
		"fields": map[string]string{"title": "Alpha Prime"},
	})
	if resp.StatusCode != 200 {
		t.Fatalf("edit status = %d", resp.StatusCode)
	}
	if res := decode[MetadataEditResult](t, resp); !res.Applied {
		t.Fatal("edit did not report applied")
	}
	md = h.itemMeta(t, alpha)
	if md.Fields["title"] != "Alpha Prime" {
		t.Fatalf("title = %q, want Alpha Prime", md.Fields["title"])
	}
	if !containsString(md.LockedFields, "title") {
		t.Fatalf("lockedFields = %v, want title", md.LockedFields)
	}
	foundProv := false
	for _, p := range md.Provenance {
		if p.Field == "title" && p.Source == "user" && p.Locked {
			foundProv = true
		}
	}
	if !foundProv {
		t.Fatalf("provenance = %+v, want a locked user title row", md.Provenance)
	}

	// The lock holds against a second edit without force.
	resp = h.patchJSON(t, "/api/v1/items/"+alpha+"/metadata", map[string]any{
		"fields": map[string]string{"title": "Alpha Zwei"},
	})
	if resp.StatusCode != 409 {
		t.Fatalf("locked edit status = %d, want 409", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "field-locked" {
		t.Fatalf("locked edit code = %q, want field-locked", e.Code)
	}
	resp = h.patchJSON(t, "/api/v1/items/"+alpha+"/metadata", map[string]any{
		"fields": map[string]string{"title": "Alpha Zwei"}, "force": true,
	})
	wantStatus(t, resp, 200, "forced edit")
	if got := h.itemMeta(t, alpha).Fields["title"]; got != "Alpha Zwei" {
		t.Fatalf("forced title = %q", got)
	}

	// Identifier validation and normalization: a bad ISRC is rejected; a
	// loose (lowercase) one is accepted and comes back in the canonical
	// uppercase form the facade now normalizes to before storing.
	resp = h.patchJSON(t, "/api/v1/items/"+alpha+"/metadata", map[string]any{
		"fields": map[string]string{"isrc": "NOPE"},
	})
	wantStatus(t, resp, 400, "bad isrc")
	resp = h.patchJSON(t, "/api/v1/items/"+alpha+"/metadata", map[string]any{
		"fields": map[string]string{"isrc": "usrc17607839"},
	})
	wantStatus(t, resp, 200, "good isrc")
	if got := h.itemMeta(t, alpha).Fields["isrc"]; got != "USRC17607839" {
		t.Fatalf("curated isrc = %q, want normalized USRC17607839", got)
	}

	// Composer sort-name: a track-only field the new pin makes editable,
	// surfaced back through the open fields map alongside the composer.
	resp = h.patchJSON(t, "/api/v1/items/"+alpha+"/metadata", map[string]any{
		"fields": map[string]string{"composer": "Ada Composer", "composer_sort": "Composer, Ada"},
	})
	wantStatus(t, resp, 200, "composer sort edit")
	md = h.itemMeta(t, alpha)
	if md.Fields["composer"] != "Ada Composer" || md.Fields["composer_sort"] != "Composer, Ada" {
		t.Fatalf("composer fields = %+v", md.Fields)
	}

	// A field outside the kind's vocabulary is rejected.
	resp = h.patchJSON(t, "/api/v1/items/"+alpha+"/metadata", map[string]any{
		"fields": map[string]string{"narrator": "Nobody"},
	})
	wantStatus(t, resp, 400, "off-vocabulary field")

	// author_sort is a book-only field: it is not editable on a track.
	resp = h.patchJSON(t, "/api/v1/items/"+alpha+"/metadata", map[string]any{
		"fields": map[string]string{"author_sort": "Nobody"},
	})
	wantStatus(t, resp, 400, "book sort field on a track")

	// Bulk edit lands on every unlocked item.
	resp = h.postJSON(t, "/api/v1/items/bulk-edit", map[string]any{
		"itemPids": []string{bravo, charlie},
		"fields":   map[string]string{"genre": "Ambient"},
	})
	if resp.StatusCode != 200 {
		t.Fatalf("bulk status = %d", resp.StatusCode)
	}
	bulk := decode[BulkEditResult](t, resp)
	if len(bulk.Edited) != 2 || len(bulk.Skipped) != 0 {
		t.Fatalf("bulk result = %+v", bulk)
	}
	if got := h.itemMeta(t, bravo).Fields["genre"]; got != "Ambient" {
		t.Fatalf("bulk genre = %q", got)
	}

	// skipLocked reports the locked item instead of failing the batch.
	resp = h.postJSON(t, "/api/v1/items/bulk-edit", map[string]any{
		"itemPids": []string{alpha, delta},
		"fields":   map[string]string{"title": "Bulk Title"}, "skipLocked": true,
	})
	if resp.StatusCode != 200 {
		t.Fatalf("skipLocked bulk status = %d", resp.StatusCode)
	}
	bulk = decode[BulkEditResult](t, resp)
	if len(bulk.Edited) != 1 || bulk.Edited[0] != delta || len(bulk.Skipped) != 1 || bulk.Skipped[0] != alpha {
		t.Fatalf("skipLocked result = %+v", bulk)
	}

	// Without skipLocked the locked item fails the whole batch.
	resp = h.postJSON(t, "/api/v1/items/bulk-edit", map[string]any{
		"itemPids": []string{alpha, charlie},
		"fields":   map[string]string{"title": "Bulk Again"},
	})
	if resp.StatusCode != 409 {
		t.Fatalf("locked bulk status = %d, want 409", resp.StatusCode)
	}
	resp.Body.Close()

	// Credits: set one role, read it back deduplicated.
	resp = h.putJSON(t, "/api/v1/items/"+alpha+"/credits", map[string]any{
		"role": "producer", "names": []string{"Pat Producer", "Pat Producer", "Quinn Q"},
	})
	wantStatus(t, resp, 200, "credits set")
	md = h.itemMeta(t, alpha)
	var producer *Credit
	for i := range md.Credits {
		if md.Credits[i].Role == "producer" {
			producer = &md.Credits[i]
		}
	}
	if producer == nil || len(producer.Names) != 2 {
		t.Fatalf("producer credits = %+v", md.Credits)
	}
	if !containsString(md.LockedFields, "credit.producer") {
		t.Fatalf("lockedFields = %v, want credit.producer", md.LockedFields)
	}
	resp = h.putJSON(t, "/api/v1/items/"+alpha+"/credits", map[string]any{
		"role": "narrator", "names": []string{"Nobody"},
	})
	wantStatus(t, resp, 400, "book role on a track")

	// Custom tags: set, read, clear; reserved keys are refused.
	resp = h.putJSON(t, "/api/v1/items/"+alpha+"/tags/mood", map[string]any{
		"values": []string{"chill", "warm"},
	})
	if resp.StatusCode != 200 {
		t.Fatalf("tag set status = %d", resp.StatusCode)
	}
	tagRes := decode[TagEditResult](t, resp)
	if tagRes.Key != "MOOD" || tagRes.Stored != 2 {
		t.Fatalf("tag result = %+v", tagRes)
	}
	md = h.itemMeta(t, alpha)
	foundTag := false
	for _, tg := range md.CustomTags {
		if tg.Key == "MOOD" && len(tg.Values) == 2 {
			foundTag = true
		}
	}
	if !foundTag || !containsString(md.LockedFields, "tag.MOOD") {
		t.Fatalf("custom tags = %+v, locks = %v", md.CustomTags, md.LockedFields)
	}
	resp = h.putJSON(t, "/api/v1/items/"+alpha+"/tags/title", map[string]any{"values": []string{"x"}})
	wantStatus(t, resp, 400, "reserved tag key")
	wantStatus(t, h.deleteReq(t, "/api/v1/items/"+alpha+"/tags/mood"), 204, "tag clear")
	for _, tg := range h.itemMeta(t, alpha).CustomTags {
		if tg.Key == "MOOD" {
			t.Fatal("cleared tag still present")
		}
	}

	// Lyrics: LRC parses, the malformed line is reported, write-back
	// writes the sidecar, the lock holds, clear removes everything.
	resp = h.putJSON(t, "/api/v1/items/"+alpha+"/lyrics", map[string]any{
		"lrc":       "[00:01.00]Hello\n[00:02.50]World\nnot a timestamp line",
		"plain":     "Hello\nWorld",
		"writeBack": true,
	})
	if resp.StatusCode != 200 {
		t.Fatalf("lyrics set status = %d", resp.StatusCode)
	}
	lyRes := decode[MetadataEditResult](t, resp)
	if lyRes.WriteBackFailures != nil && len(*lyRes.WriteBackFailures) > 0 {
		t.Fatalf("lyrics write-back failures = %+v", *lyRes.WriteBackFailures)
	}
	if lyRes.Warnings == nil || len(*lyRes.Warnings) != 1 || !strings.Contains((*lyRes.Warnings)[0], "line 3") {
		t.Fatalf("lyrics warnings = %+v, want the dropped line 3", lyRes.Warnings)
	}
	sidecar := filepath.Join(h.library, "alpha.lrc")
	raw, err := os.ReadFile(sidecar)
	if err != nil {
		t.Fatalf("sidecar missing: %v", err)
	}
	if !strings.Contains(string(raw), "Hello") {
		t.Fatalf("sidecar content = %q", raw)
	}
	md = h.itemMeta(t, alpha)
	if md.Lyrics == nil || !md.Lyrics.Synced || md.Lyrics.Source != "user" {
		t.Fatalf("lyrics state = %+v", md.Lyrics)
	}
	resp = get(t, h.ts, "/api/v1/items/"+alpha+"/lyrics", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("lyrics read status = %d", resp.StatusCode)
	}
	ly := decode[Lyrics](t, resp)
	if ly.Synced == nil || len(*ly.Synced) != 2 {
		t.Fatalf("lyrics read = %+v", ly)
	}
	resp = h.putJSON(t, "/api/v1/items/"+alpha+"/lyrics", map[string]any{"plain": "Only plain"})
	wantStatus(t, resp, 409, "locked lyrics without force")
	resp = h.putJSON(t, "/api/v1/items/"+alpha+"/lyrics", map[string]any{"plain": "Only plain", "force": true})
	wantStatus(t, resp, 200, "forced lyrics replace")
	md = h.itemMeta(t, alpha)
	if md.Lyrics == nil || md.Lyrics.Synced || deref(md.Lyrics.Lrc) != "Only plain" {
		t.Fatalf("plain lyrics state = %+v", md.Lyrics)
	}
	wantStatus(t, h.deleteReq(t, "/api/v1/items/"+alpha+"/lyrics"), 204, "lyrics clear")
	if md = h.itemMeta(t, alpha); md.Lyrics != nil {
		t.Fatalf("cleared lyrics still present: %+v", md.Lyrics)
	}
	resp = h.putJSON(t, "/api/v1/items/"+alpha+"/lyrics", map[string]any{})
	wantStatus(t, resp, 400, "empty lyrics body")

	// Artwork: a real image sticks, junk is refused, clear reverts.
	pngBytes := tinyPNG(t)
	resp = metadataPutBytes(t, h.ts, "/api/v1/items/"+alpha+"/artwork", h.token, pngBytes)
	wantStatus(t, resp, 200, "artwork set")
	if !h.itemMeta(t, alpha).HasArtwork {
		t.Fatal("hasArtwork stayed false after set")
	}
	resp = get(t, h.ts, "/api/v1/items/"+alpha+"/art", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("art read status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	resp = metadataPutBytes(t, h.ts, "/api/v1/items/"+alpha+"/artwork", h.token, []byte("this is not an image at all"))
	wantStatus(t, resp, 415, "non-image artwork")
	wantStatus(t, h.deleteReq(t, "/api/v1/items/"+alpha+"/artwork"), 204, "artwork clear")
	if h.itemMeta(t, alpha).HasArtwork {
		t.Fatal("hasArtwork stayed true after clear")
	}

	// The locks endpoint locks, unlocks, and rejects junk fields.
	resp = h.putJSON(t, "/api/v1/items/"+alpha+"/locks", map[string]any{
		"fields": []string{"genre"}, "locked": true,
	})
	if resp.StatusCode != 200 {
		t.Fatalf("lock status = %d", resp.StatusCode)
	}
	locks := decode[LocksResult](t, resp)
	if !containsString(locks.LockedFields, "genre") {
		t.Fatalf("locks = %+v, want genre", locks)
	}
	resp = h.putJSON(t, "/api/v1/items/"+alpha+"/locks", map[string]any{
		"fields": []string{"genre"}, "locked": false,
	})
	locks = decode[LocksResult](t, resp)
	if containsString(locks.LockedFields, "genre") {
		t.Fatalf("locks after unlock = %+v", locks)
	}
	resp = h.putJSON(t, "/api/v1/items/"+alpha+"/locks", map[string]any{
		"fields": []string{"bogus"}, "locked": true,
	})
	wantStatus(t, resp, 400, "junk lock field")

	// Release status: mark, observe the locked tag, clear.
	resp = h.putJSON(t, "/api/v1/items/"+alpha+"/release-status", map[string]any{"unofficial": true})
	wantStatus(t, resp, 200, "mark unofficial")
	md = h.itemMeta(t, alpha)
	if !md.Unofficial {
		t.Fatal("unofficial mark did not surface")
	}
	foundTag = false
	for _, tg := range md.CustomTags {
		if tg.Key == "RELEASESTATUS" {
			foundTag = true
		}
	}
	if !foundTag {
		t.Fatalf("RELEASESTATUS tag missing: %+v", md.CustomTags)
	}
	resp = h.putJSON(t, "/api/v1/items/"+alpha+"/release-status", map[string]any{"unofficial": false})
	wantStatus(t, resp, 200, "clear unofficial")
	if h.itemMeta(t, alpha).Unofficial {
		t.Fatal("unofficial mark did not clear")
	}

	// Entity edits: the album's sort name lands with provenance; bad
	// identifiers, unknown fields, and genre entities are refused.
	resp = get(t, h.ts, "/api/v1/library/search?q=Fixture", h.token)
	sr := decode[SearchResults](t, resp)
	if len(sr.Albums) == 0 {
		t.Fatal("search found no album entity")
	}
	albumPid := sr.Albums[0].Pid
	if !strings.HasPrefix(albumPid, "al-") {
		t.Fatalf("album pid = %q", albumPid)
	}
	resp = h.patchJSON(t, "/api/v1/entities/album/"+albumPid, map[string]any{
		"edits": map[string]string{"sort": "Fixture Album, The"},
	})
	wantStatus(t, resp, 200, "entity edit")
	resp = get(t, h.ts, "/api/v1/entities/album/"+albumPid+"/curation", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("curation status = %d", resp.StatusCode)
	}
	cur := decode[EntityCuration](t, resp)
	foundSort := false
	for _, c := range cur.Curated {
		if c.Field == "sort" && c.Source == "user" && c.Locked && deref(c.Value) == "Fixture Album, The" {
			foundSort = true
		}
	}
	if !foundSort {
		t.Fatalf("curation = %+v, want a locked user sort row", cur.Curated)
	}
	resp = h.patchJSON(t, "/api/v1/entities/album/"+albumPid, map[string]any{
		"edits": map[string]string{"barcode": "12ab"},
	})
	wantStatus(t, resp, 400, "bad barcode")
	resp = h.patchJSON(t, "/api/v1/entities/album/"+albumPid, map[string]any{
		"edits": map[string]string{"bogus": "x"},
	})
	wantStatus(t, resp, 400, "off-vocabulary entity field")
	resp = h.patchJSON(t, "/api/v1/entities/genre/"+albumPid, map[string]any{
		"edits": map[string]string{"sort": "x"},
	})
	wantStatus(t, resp, 400, "genre entity edit")

	// A non-admin reads everything and mutates nothing.
	resp = h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	wantStatus(t, resp, 201, "create sam")
	sam := loginAs(t, h.ts, "sam", testPassword).Token
	resp = get(t, h.ts, "/api/v1/items/"+alpha+"/metadata", sam)
	if resp.StatusCode != 200 {
		t.Fatalf("non-admin metadata read = %d", resp.StatusCode)
	}
	resp.Body.Close()
	resp = get(t, h.ts, "/api/v1/metadata/fields", sam)
	if resp.StatusCode != 200 {
		t.Fatalf("non-admin fields read = %d", resp.StatusCode)
	}
	resp.Body.Close()
	forbidden := []struct {
		method, path string
		body         any
	}{
		{"PATCH", "/api/v1/items/" + alpha + "/metadata", map[string]any{"fields": map[string]string{"title": "Nope"}}},
		{"POST", "/api/v1/items/bulk-edit", map[string]any{"itemPids": []string{alpha}, "fields": map[string]string{"title": "Nope"}}},
		{"PUT", "/api/v1/items/" + alpha + "/credits", map[string]any{"role": "producer", "names": []string{"Nope"}}},
		{"PUT", "/api/v1/items/" + alpha + "/release-status", map[string]any{"unofficial": true}},
		{"PUT", "/api/v1/items/" + alpha + "/locks", map[string]any{"fields": []string{"title"}, "locked": true}},
		{"PATCH", "/api/v1/entities/album/" + albumPid, map[string]any{"edits": map[string]string{"sort": "Nope"}}},
		{"POST", "/api/v1/items/" + alpha + "/metadata/commit", map[string]any{"fields": map[string]string{"title": "Nope"}}},
	}
	for _, f := range forbidden {
		resp := metadataReq(t, h.ts, f.method, f.path, sam, f.body)
		if resp.StatusCode != 403 {
			t.Fatalf("non-admin %s %s = %d, want 403", f.method, f.path, resp.StatusCode)
		}
		resp.Body.Close()
	}
}

// The handle is legitimately absent, and absent means "this track's
// album has no release group" rather than "the server did not look".
func TestMetadataReleaseGroupAbsentForAnAlbumlessTrack(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	// No ALBUM and no MusicBrainz ids: the release-group key is derived
	// from an mbid when there is one, whatever the album title says, so
	// a loose track with an mbid would still get a group and this case
	// would prove nothing.
	if _, err := fixtures.Generate(h.library, fixtures.Spec{
		Name: "loose", Codec: fixtures.CodecMP3, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Loose Cut", "ARTIST": "Nobody In Particular"},
	}); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)

	var loose string
	for _, it := range h.items(t, "").Items {
		if it.Title == "Loose Cut" {
			loose = it.Pid
		}
	}
	if loose == "" {
		t.Fatal("the albumless fixture did not scan")
	}
	md := h.itemMeta(t, loose)
	if md.AlbumPid != nil {
		t.Errorf("albumless track carries albumPid %v", *md.AlbumPid)
	}
	if md.ReleaseGroupPid != nil {
		t.Errorf("albumless track carries releaseGroupPid %v, want absent", *md.ReleaseGroupPid)
	}
}

// writeBackIssues is the editor's answer to "do this item's tags match
// the catalog", and its whole lifecycle is the drift appearing when a
// write-back cannot land and clearing when one does.
func TestMetadataWriteBackIssues(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	h := newHarness(t)

	// Resolved by the fixture's own name rather than by extension: the
	// demo library happens to hold one mp3 today, and a second preset
	// would otherwise silently lock an unrelated file and fail this test
	// somewhere far from the cause.
	var mp3 string
	if err := filepath.WalkDir(h.library, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		if strings.HasPrefix(filepath.Base(path), "bravo") &&
			strings.EqualFold(filepath.Ext(path), ".mp3") {
			if mp3 != "" {
				return fmt.Errorf("two candidate files: %s and %s", mp3, path)
			}
			mp3 = path
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if mp3 == "" {
		t.Fatal("no bravo mp3 in the demo library")
	}
	var item string
	for _, it := range h.items(t, "").Items {
		if it.Title == "Bravo Song" {
			item = it.Pid
		}
	}
	if item == "" {
		t.Fatal("no Bravo Song item")
	}

	// Both the file and its directory: the tag writer replaces the file
	// atomically, so a writable directory would let it succeed anyway.
	dir := filepath.Dir(mp3)
	if err := os.Chmod(mp3, 0o444); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(dir, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = os.Chmod(dir, 0o755)
		_ = os.Chmod(mp3, 0o644)
	})

	resp := h.patchJSON(t, "/api/v1/items/"+item+"/metadata", map[string]any{
		"fields":    map[string]string{"title": "Bravo Unsynced"},
		"writeBack": true,
	})
	// The catalog edit commits whatever the file does; the failure rides
	// in the outcome, not in the status.
	if resp.StatusCode != 200 {
		resp.Body.Close()
		t.Fatalf("edit status = %d, want 200", resp.StatusCode)
	}
	res := decode[MetadataEditResult](t, resp)
	if res.WriteBackFailures == nil || len(*res.WriteBackFailures) == 0 {
		t.Fatalf("edit reported no write-back failure: %+v", res)
	}

	md := h.itemMeta(t, item)
	if len(md.WriteBackIssues) != 1 {
		t.Fatalf("writeBackIssues = %+v, want one", md.WriteBackIssues)
	}
	issue := md.WriteBackIssues[0]
	// The catalog names the code in snake_case; the contract is kebab.
	if issue.Code != "tag-write-unsynced" {
		t.Errorf("issue code = %q, want tag-write-unsynced", issue.Code)
	}
	if issue.FilePid == "" {
		t.Error("issue carries no filePid")
	}
	if strings.Contains(issue.FilePid, "/") {
		t.Errorf("issue filePid = %q, want a pid rather than a path", issue.FilePid)
	}
	// The admin read carries the writer's own error, which names the
	// path; that is the whole reason the next assertion exists.
	if issue.Detail == nil || !strings.Contains(*issue.Detail, h.library) {
		t.Errorf("admin detail = %v, want the writer's error", issue.Detail)
	}

	// The same read by somebody who is not an administrator says what
	// went wrong without saying where the library lives. This endpoint is
	// open to anyone who can see the item, unlike the diagnostics
	// listing, so the path must not ride along.
	resp = h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "wb-reader", "password": testPassword,
	})
	wantStatus(t, resp, 201, "create non-admin reader")
	reader := loginAs(t, h.ts, "wb-reader", testPassword).Token
	resp = get(t, h.ts, "/api/v1/items/"+item+"/metadata", reader)
	if resp.StatusCode != 200 {
		resp.Body.Close()
		t.Fatalf("non-admin metadata read = %d, want 200", resp.StatusCode)
	}
	plain := decode[ItemMetadata](t, resp)
	if len(plain.WriteBackIssues) != 1 {
		t.Fatalf("non-admin writeBackIssues = %+v, want one", plain.WriteBackIssues)
	}
	seen := plain.WriteBackIssues[0]
	if seen.Code != "tag-write-unsynced" || seen.FilePid != issue.FilePid {
		t.Errorf("non-admin issue = %+v, want the same code and file", seen)
	}
	if seen.Detail != nil {
		t.Errorf("non-admin detail = %q, want it withheld", *seen.Detail)
	}

	// A clean write-back clears it: the field is drift, not history.
	if err := os.Chmod(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(mp3, 0o644); err != nil {
		t.Fatal(err)
	}
	resp = h.patchJSON(t, "/api/v1/items/"+item+"/metadata", map[string]any{
		// force, because the first edit locked the field on its way past.
		"fields":    map[string]string{"title": "Bravo Synced"},
		"writeBack": true,
		"force":     true,
	})
	if resp.StatusCode != 200 {
		resp.Body.Close()
		t.Fatalf("second edit status = %d, want 200", resp.StatusCode)
	}
	res = decode[MetadataEditResult](t, resp)
	if res.WriteBackFailures != nil && len(*res.WriteBackFailures) != 0 {
		t.Fatalf("second edit still failed write-back: %+v", *res.WriteBackFailures)
	}
	if got := h.itemMeta(t, item).WriteBackIssues; len(got) != 0 {
		t.Errorf("writeBackIssues after a clean sync = %+v, want empty", got)
	}
}

func TestMetadataBookChapters(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	if _, err := fixtures.GenerateChapteredBook(h.library); err != nil {
		t.Fatal(err)
	}
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)

	books := h.items(t, "?mediaType=audiobook")
	if len(books.Items) != 2 {
		t.Fatalf("scanned %d books, want 2", len(books.Items))
	}
	var single, multi string
	for _, it := range books.Items {
		switch it.Title {
		case "The Chaptered Fixture":
			single = it.Pid
		case "The Fixture Book":
			multi = it.Pid
		}
	}
	if single == "" || multi == "" {
		t.Fatalf("books = %+v", books.Items)
	}

	// The read shape carries the embedded chapters and book fields.
	md := h.itemMeta(t, single)
	if md.MediaType != "audiobook" || md.Fields["author"] != "Ada Author" {
		t.Fatalf("book metadata = %+v", md)
	}
	if md.Chapters == nil || len(*md.Chapters) != 3 {
		t.Fatalf("embedded chapters = %+v", md.Chapters)
	}

	// author_sort is a book-only sort-name field the new pin makes
	// editable; it round-trips through the open fields map.
	resp := h.patchJSON(t, "/api/v1/items/"+single+"/metadata", map[string]any{
		"fields": map[string]string{"author_sort": "Author, Ada"},
	})
	wantStatus(t, resp, 200, "author sort edit")
	if got := h.itemMeta(t, single).Fields["author_sort"]; got != "Author, Ada" {
		t.Fatalf("author_sort = %q, want Author, Ada", got)
	}

	// Replacement chapters land on the single-file book and win on read.
	resp = h.putJSON(t, "/api/v1/books/"+single+"/chapters", map[string]any{
		"chapters": []map[string]any{
			{"index": 0, "startMs": 0, "endMs": 3000, "title": "One"},
			{"index": 1, "startMs": 3000, "title": "Two"},
		},
	})
	wantStatus(t, resp, 200, "chapters set")
	md = h.itemMeta(t, single)
	if md.Chapters == nil || len(*md.Chapters) != 2 {
		t.Fatalf("user chapters = %+v", md.Chapters)
	}
	// SetBookChapters sends book-timeline offsets directly and the read
	// reports them the same way, so both starts round-trip exactly.
	gotCh := *md.Chapters
	if deref(gotCh[0].Title) != "One" || gotCh[0].StartMs != 0 {
		t.Fatalf("chapter 0 = %+v, want title One start 0", gotCh[0])
	}
	if deref(gotCh[1].Title) != "Two" || gotCh[1].StartMs != 3000 {
		t.Fatalf("chapter 1 = %+v, want title Two start 3000", gotCh[1])
	}
	if !containsString(md.LockedFields, "chapters") {
		t.Fatalf("lockedFields = %v, want chapters", md.LockedFields)
	}

	// The default lock holds without force.
	resp = h.putJSON(t, "/api/v1/books/"+single+"/chapters", map[string]any{
		"chapters": []map[string]any{{"index": 0, "startMs": 0, "title": "Solo"}},
	})
	wantStatus(t, resp, 409, "locked chapters")

	// Overlapping chapters are rejected before anything writes.
	resp = h.putJSON(t, "/api/v1/books/"+single+"/chapters", map[string]any{
		"chapters": []map[string]any{
			{"index": 0, "startMs": 0, "endMs": 4000, "title": "A"},
			{"index": 1, "startMs": 3000, "title": "B"},
		},
		"force": true,
	})
	wantStatus(t, resp, 400, "overlapping chapters")

	// Multi-file books now accept a flat book-timeline chapter list; the
	// server splits it across the parts. "The Fixture Book" has three parts
	// of 4s, 5s, and 6s (book timeline [0,4000), [4000,9000), [9000,15000)).
	// The middle chapter deliberately spans the first part boundary and the
	// final chapter starts inside the second part, so a correct split must
	// distribute the flat list across parts and reassemble book-timeline
	// spans on read.
	resp = h.putJSON(t, "/api/v1/books/"+multi+"/chapters", map[string]any{
		"chapters": []map[string]any{
			{"index": 0, "startMs": 0, "endMs": 2000, "title": "Prologue"},
			{"index": 1, "startMs": 2000, "endMs": 7000, "title": "Middle"},
			{"index": 2, "startMs": 7000, "title": "Finale"},
		},
	})
	wantStatus(t, resp, 200, "multi-file chapters set")
	md = h.itemMeta(t, multi)
	if md.Chapters == nil || len(*md.Chapters) != 3 {
		t.Fatalf("multi-file user chapters = %+v", md.Chapters)
	}
	multiCh := *md.Chapters
	if deref(multiCh[0].Title) != "Prologue" || multiCh[0].StartMs != 0 {
		t.Fatalf("multi chapter 0 = %+v, want Prologue@0", multiCh[0])
	}
	// The middle chapter spans the first part boundary yet round-trips on the
	// book timeline, proving the split-and-reassemble is book-timeline honest.
	if deref(multiCh[1].Title) != "Middle" || multiCh[1].StartMs != 2000 || derefInt64(multiCh[1].EndMs) != 7000 {
		t.Fatalf("multi chapter 1 = %+v, want Middle [2000,7000)", multiCh[1])
	}
	if deref(multiCh[2].Title) != "Finale" || multiCh[2].StartMs != 7000 {
		t.Fatalf("multi chapter 2 = %+v, want Finale@7000", multiCh[2])
	}

	// An empty list restores the embedded chapters.
	resp = h.putJSON(t, "/api/v1/books/"+single+"/chapters", map[string]any{
		"chapters": []map[string]any{}, "force": true,
	})
	wantStatus(t, resp, 200, "chapters restore")
	md = h.itemMeta(t, single)
	if md.Chapters == nil || len(*md.Chapters) != 3 {
		t.Fatalf("restored chapters = %+v", md.Chapters)
	}

	// Database-only book fields persist and surface on the read.
	resp = h.patchJSON(t, "/api/v1/items/"+single+"/metadata", map[string]any{
		"fields": map[string]string{"publisher": "Fixture House", "isbn": "978-0-306-40615-7"},
	})
	wantStatus(t, resp, 200, "book field edit")
	md = h.itemMeta(t, single)
	if md.Fields["publisher"] != "Fixture House" {
		t.Fatalf("publisher = %q", md.Fields["publisher"])
	}
	if md.Fields["isbn"] == "" {
		t.Fatal("curated isbn did not surface")
	}
	resp = h.patchJSON(t, "/api/v1/items/"+single+"/metadata", map[string]any{
		"fields": map[string]string{"isbn": "978-0-306-40615-8"},
	})
	wantStatus(t, resp, 400, "bad isbn checksum")
}

// derefIntOr reads an optional pixel count, absent meaning unmeasured.
func derefIntOr(p *int) int {
	if p == nil {
		return 0
	}
	return *p
}

// tinyTIFF encodes a small valid TIFF. Go's http.DetectContentType has no
// TIFF entry (its table is BMP, GIF, JPEG, PNG, WebP and ICO), so these
// bytes are the case that separates the two recognizers: only the
// catalog's own decodes them.
func tinyTIFF(t *testing.T) []byte {
	return tiffImage(t, 6, 5)
}

// tiffImage encodes a valid TIFF of the given dimensions.
func tiffImage(t *testing.T, w, h int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for x := 0; x < w; x++ {
		for y := 0; y < h; y++ {
			img.Set(x, y, color.RGBA{R: uint8(30 * x), G: 90, B: uint8(40 * y), A: 255})
		}
	}
	var buf bytes.Buffer
	if err := tiff.Encode(&buf, img, nil); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// The artwork guard asks the catalog's own recognizer, which is the one
// that decides what can be stored: decode for the six formats it has a
// decoder for, container magic for the exotics it does not. Nothing a
// caller can say widens it, which is what keeps an error page out of a
// cover slot and out of every backing file behind it.
func TestSetArtworkTakesWhatTheCatalogRecognizes(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	page := h.items(t, "")
	if len(page.Items) == 0 {
		t.Fatal("the fixture library scanned no items")
	}
	pid := page.Items[0].Pid
	base := "/api/v1/items/" + pid + "/artwork"

	tiffBytes := tinyTIFF(t)

	// Bytes that are not a picture stay out, whatever the request looks
	// like. An HTML error page is the case worth naming: a proxy answers
	// one where a picture was expected, and with write-back on it would
	// otherwise be embedded into every backing file.
	resp := metadataPutBytes(t, h.ts, base, h.token,
		[]byte("<html><head><title>502 Bad Gateway</title></head></html>"))
	wantStatus(t, resp, 415, "an error page as a cover")

	resp = metadataPutBytes(t, h.ts, base+"?role=front", h.token, []byte("this is not an image at all"))
	wantStatus(t, resp, 415, "junk as a cover")

	// TIFF decodes here and nowhere else in this process: Go's sniff table
	// stops at BMP, so this is the case that proves the guard asks the
	// catalog rather than the standard library.
	resp = metadataPutBytes(t, h.ts, base, h.token, tiffBytes)
	wantStatus(t, resp, 200, "a TIFF cover")

	// Stored, measured, thumbnailed, and reported as what it is - not as
	// the jpeg the mime table used to claim for everything it did not know.
	resp = get(t, h.ts, "/api/v1/items/"+pid+"/art-roles", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("art-roles status = %d", resp.StatusCode)
	}
	roles := decode[ArtRoles](t, resp)
	var front *ArtRoleInfo
	for i := range roles.Roles {
		if string(roles.Roles[i].Role) == "front" {
			front = &roles.Roles[i]
		}
	}
	if front == nil {
		t.Fatalf("no front role after the TIFF set: %+v", roles.Roles)
	}
	if deref(front.Format) != "tiff" {
		t.Errorf("stored format = %q, want tiff", deref(front.Format))
	}
	if derefIntOr(front.Width) != 6 || derefIntOr(front.Height) != 5 {
		t.Errorf("stored size = %dx%d, want 6x5", derefIntOr(front.Width), derefIntOr(front.Height))
	}

	// And the byte endpoint labels it honestly, both whole and scaled.
	// The 6x5 source is smaller than the smallest legal size, so the
	// scaling legs get a 40x30. TIFF is the format the catalog decodes
	// and no client paints, so every sized request re-encodes it - the
	// one that fits inside its box at the source's own size, and the
	// smaller one as a real thumbnail. Both come back PNG, since only a
	// JPEG source re-encodes as JPEG. Asking for no size at all is the
	// request that means "the original", and that still answers the
	// stored bytes as themselves.
	resp = metadataPutBytes(t, h.ts, "/api/v1/items/"+pid+"/artwork", h.token, tiffImage(t, 40, 30))
	wantStatus(t, resp, 200, "a TIFF big enough to scale")
	for path, want := range map[string]string{
		"/api/v1/items/" + pid + "/art":         "image/tiff",
		"/api/v1/items/" + pid + "/art?size=64": "image/png",
		"/api/v1/items/" + pid + "/art?size=16": "image/png",
	} {
		resp = get(t, h.ts, path, h.token)
		if resp.StatusCode != 200 {
			t.Fatalf("%s status = %d", path, resp.StatusCode)
		}
		got := resp.Header.Get("Content-Type")
		resp.Body.Close()
		if !strings.HasPrefix(got, want) {
			t.Errorf("%s content type = %q, want %s", path, got, want)
		}
	}
}

// bigAVIF is an ISOBMFF header with the AVIF brand and enough padding to
// pass the thumbnail-slot cap, standing in for the exotic covers the
// catalog stores without decoding. Nothing here decodes it either, which
// is the point: with no dimensions to scale from, the resolver can only
// serve it whole.
func bigAVIF(size int) []byte {
	data := make([]byte, size)
	copy(data, []byte{0, 0, 0, 0x18})
	copy(data[4:], "ftypavif")
	return data
}

// bigPNG encodes a PNG of a given square side, padded past the
// thumbnail-slot cap so a size request at or above that side is answered
// with the source itself - measured, and therefore never refused.
func bigPNG(t *testing.T, side int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, side, side))
	// Seeded noise, so the picture is the same every run and the encoder
	// has nothing to compress it down past the bound with.
	rng := rand.New(rand.NewSource(1))
	for x := 0; x < side; x++ {
		for y := 0; y < side; y++ {
			img.Set(x, y, color.RGBA{
				R: uint8(rng.Intn(256)), G: uint8(rng.Intn(256)),
				B: uint8(rng.Intn(256)), A: 255,
			})
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// A cover the server could not measure is served whole, and a thumbnail
// slot is not where a whole one belongs. The bound is on the answer
// rather than on the picture: asking for the original always gets it,
// however large, and so does asking for a size a measured picture
// already fits.
func TestArtRefusesAnUnscalableOriginalAsAThumbnail(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	page := h.items(t, "")
	if len(page.Items) == 0 {
		t.Fatal("the fixture library scanned no items")
	}
	pid := page.Items[0].Pid

	resp := metadataPutBytes(t, h.ts, "/api/v1/items/"+pid+"/artwork", h.token, bigAVIF(3<<20))
	wantStatus(t, resp, 200, "an AVIF cover")

	// Whole: the caller asked for the picture, not for a thumbnail -
	// and it arrives as what it is, not as the jpeg fallback.
	resp = get(t, h.ts, "/api/v1/items/"+pid+"/art", h.token)
	if got := resp.Header.Get("Content-Type"); !strings.HasPrefix(got, "image/avif") {
		t.Errorf("unscaled AVIF content type = %q, want image/avif", got)
	}
	readAll(t, resp, 200, "unscaled art")

	// Sized: there is no thumbnail of this picture, which is a different
	// answer from three megabytes into a 64-pixel tile.
	resp = get(t, h.ts, "/api/v1/items/"+pid+"/art?size=64", h.token)
	wantStatus(t, resp, 404, "a thumbnail of an unscalable original")

	resp = get(t, h.ts, "/api/v1/items/"+pid+"/art?size=2048", h.token)
	wantStatus(t, resp, 404, "the largest thumbnail rung")

	// A picture that can be scaled is unaffected at every rung - including
	// the rungs at or above its own longest edge, where the resolver has
	// nothing to scale down to and answers the source itself. Those bytes
	// are over the bound and must still be served: the caller asked for a
	// box this picture already fits.
	big := bigPNG(t, 1000)
	if len(big) <= 2<<20 {
		t.Fatalf("the measured fixture is %d bytes, under the bound this test is about", len(big))
	}
	resp = metadataPutBytes(t, h.ts, "/api/v1/items/"+pid+"/artwork", h.token, big)
	wantStatus(t, resp, 200, "a measured cover over the bound")
	for _, size := range []int{64, 1024, 2048} {
		path := fmt.Sprintf("/api/v1/items/%s/art?size=%d", pid, size)
		readAll(t, get(t, h.ts, path, h.token), 200, path)
	}
}

// The other way a thumbnail slot can be handed the whole original: a
// measured source whose decode fails at scale time, which the resolver
// answers with the source itself. The bound is on the answer, so it has
// to catch that fallback too, not only the never-measured exotics.
func TestArtRefusesAnUndecodableMeasuredOriginalAsAThumbnail(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	page := h.items(t, "")
	if len(page.Items) == 0 {
		t.Fatal("the fixture library scanned no items")
	}
	pid := page.Items[0].Pid

	// A PNG whose header measures but whose pixel data does not decode:
	// the store records 1000x1000, and the thumbnailer fails on it.
	img := bigPNG(t, 1000)
	for i := 2 << 10; i < len(img)-8; i++ {
		img[i] = 0
	}
	resp := metadataPutBytes(t, h.ts, "/api/v1/items/"+pid+"/artwork", h.token, img)
	wantStatus(t, resp, 200, "a measured cover that cannot decode")

	readAll(t, get(t, h.ts, "/api/v1/items/"+pid+"/art", h.token), 200, "the whole original")

	resp = get(t, h.ts, "/api/v1/items/"+pid+"/art?size=64", h.token)
	wantStatus(t, resp, 404, "a thumbnail of an undecodable measured original")
}

// readAll asserts a status and drains the body, which a test that leaves
// a large one unread would otherwise turn into a "superfluous
// response.WriteHeader" line in an otherwise clean run.
func readAll(t *testing.T, resp *http.Response, want int, what string) []byte {
	t.Helper()
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("reading %s: %v", what, err)
	}
	if resp.StatusCode != want {
		t.Fatalf("%s status = %d, want %d", what, resp.StatusCode, want)
	}
	return body
}

// TestMetadataAcquisitionOrigin covers the read-only origin block: it is
// present for any item the catalog holds origin evidence for, absent for
// one it does not, and its URL is redacted before it leaves the server.
//
// Redaction is unconditional because the metadata read answers everyone
// who can see the item, not just a curator, and the stored value is
// whatever the acquisition or the file's own SOURCE_URL tag said.
func TestMetadataAcquisitionOrigin(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	// A SOURCE_URL tag is what makes the scan record origin evidence at
	// all; the row it writes reads `manual`, since the tag says the item
	// came from somewhere without saying by what mechanism.
	// Durations distinct from the demo library's and from each other:
	// identical essence dedups to one item, as UploadSources notes.
	specs := []fixtures.Spec{
		{
			Name: "acquired", Codec: fixtures.CodecFLAC, Duration: 4 * time.Second,
			Tags: map[string]string{
				"TITLE": "Acquired Cut", "ARTIST": "Nobody In Particular",
				"SOURCE_URL": "https://feeder:hunter2@feeds.example.test/show/ep-12.mp3?token=abc123",
				"SOURCE_ID":  "ep-12",
			},
		},
		{
			Name: "sideloaded", Codec: fixtures.CodecFLAC, Duration: 4500 * time.Millisecond,
			Tags: map[string]string{
				"TITLE": "Sideloaded Cut", "ARTIST": "Nobody In Particular",
				"SOURCE_URL": "file:///srv/incoming/ep-13.mp3",
			},
		},
		{
			Name: "ripped", Codec: fixtures.CodecFLAC, Duration: 5 * time.Second,
			Tags: map[string]string{
				"TITLE": "Ripped Cut", "ARTIST": "Nobody In Particular",
			},
		},
	}
	if _, err := fixtures.Generate(h.library, specs...); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)

	pids := map[string]string{}
	for _, it := range h.items(t, "").Items {
		pids[it.Title] = it.Pid
	}
	for _, title := range []string{"Acquired Cut", "Sideloaded Cut", "Ripped Cut"} {
		if pids[title] == "" {
			t.Fatalf("the %q fixture did not scan", title)
		}
	}

	acquired := h.itemMeta(t, pids["Acquired Cut"]).Acquisition
	if acquired == nil {
		t.Fatal("an item with a SOURCE_URL tag carries no acquisition block")
	}
	if acquired.SourceType != "manual" {
		t.Errorf("sourceType = %q, want manual (tag evidence names no mechanism)", acquired.SourceType)
	}
	if acquired.SourceUrl == nil {
		t.Fatal("an http origin was not emitted")
	}
	if got, want := *acquired.SourceUrl, "https://feeds.example.test/show/ep-12.mp3"; got != want {
		t.Errorf("sourceUrl = %q, want %q: userinfo and query must not leave the server", got, want)
	}
	if acquired.AcquiredAt.IsZero() {
		t.Error("acquiredAt is zero; the catalog stamps scan time when the tags carry no date")
	}

	sideloaded := h.itemMeta(t, pids["Sideloaded Cut"]).Acquisition
	if sideloaded == nil {
		t.Fatal("an item with a non-http SOURCE_URL tag carries no acquisition block")
	}
	if sideloaded.SourceUrl != nil {
		t.Errorf("sourceUrl = %q for a file:// origin, want absent", *sideloaded.SourceUrl)
	}

	if ripped := h.itemMeta(t, pids["Ripped Cut"]).Acquisition; ripped != nil {
		t.Errorf("a plainly ripped item carries an acquisition block: %+v", ripped)
	}
}

// metadataCommit posts a compound commit and decodes the result. It
// takes the 200 the operation answers for a refused part too: the part
// list is the answer, not the status code.
func metadataCommit(t *testing.T, h *harness, pid string, body map[string]any) MetadataCommitResult {
	t.Helper()
	resp := h.postJSON(t, "/api/v1/items/"+pid+"/metadata/commit", body)
	if resp.StatusCode != 200 {
		t.Fatalf("commit status = %d, want 200", resp.StatusCode)
	}
	return decode[MetadataCommitResult](t, resp)
}

// commitStatuses is the parts list flattened to "part[detail]=status",
// which is what the ordering and skipping assertions read.
func commitStatuses(result MetadataCommitResult) []string {
	out := make([]string, 0, len(result.Parts))
	for _, p := range result.Parts {
		entry := string(p.Part)
		if p.Detail != nil {
			entry += "[" + *p.Detail + "]"
		}
		out = append(out, entry+"="+string(p.Status))
	}
	return out
}

// TestMetadataCommitRunsEveryStagedPart is the compound save's happy
// path: one request carries the whole draft, the parts run in the
// editor's own order, and every one of them lands in the catalog.
func TestMetadataCommitRunsEveryStagedPart(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := h.items(t, "").Items[0].Pid

	result := metadataCommit(t, h, pid, map[string]any{
		"fields":     map[string]string{"title": "Committed Title", "genre": "Ambient"},
		"credits":    []map[string]any{{"role": "producer", "names": []string{"Rae Okada"}}},
		"lyrics":     map[string]any{"plain": "one line"},
		"tagSets":    map[string]any{"MOOD": []string{"calm"}, "AAA": []string{"first"}},
		"tagRemoves": []string{"NOTHING_HERE"},
		"unofficial": true,
		"lock":       false,
	})

	// Sorted tag sets, because a JSON object carries no order of its own
	// and the parts list has to be reproducible.
	want := []string{
		"fields=committed",
		"credit[producer]=committed",
		"lyrics=committed",
		"tagSet[AAA]=committed",
		"tagSet[MOOD]=committed",
		"tagRemove[NOTHING_HERE]=committed",
		"releaseStatus=committed",
	}
	if got := commitStatuses(result); !slices.Equal(got, want) {
		t.Fatalf("parts = %v, want %v", got, want)
	}

	md := h.itemMeta(t, pid)
	if md.Fields["title"] != "Committed Title" || md.Fields["genre"] != "Ambient" {
		t.Errorf("fields = %+v, want the committed values", md.Fields)
	}
	producers := ""
	for _, c := range md.Credits {
		if c.Role == "producer" {
			producers = strings.Join(c.Names, ", ")
		}
	}
	if producers != "Rae Okada" {
		t.Errorf("producer credit = %q, want Rae Okada (credits: %+v)", producers, md.Credits)
	}
	if md.Lyrics == nil {
		t.Error("lyrics did not commit")
	}
	if !md.Unofficial {
		t.Error("release status did not commit")
	}
	tags := map[string][]string{}
	for _, tg := range md.CustomTags {
		tags[tg.Key] = tg.Values
	}
	if len(tags["MOOD"]) != 1 || len(tags["AAA"]) != 1 {
		t.Errorf("tags = %+v, want both sets stored", tags)
	}
}

// TestMetadataCommitStopsAtTheFirstRefusal pins the semantics the
// sequential save has: parts run until one is refused, that one carries
// its own error, and the rest are reported as never attempted. The
// refusal is a 200, because the earlier parts committed and a status
// code would throw their outcome away.
func TestMetadataCommitStopsAtTheFirstRefusal(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := h.items(t, "").Items[0].Pid

	// Lock a custom tag, then stage a draft whose second part touches it.
	resp := h.putJSON(t, "/api/v1/items/"+pid+"/locks",
		map[string]any{"fields": []string{"tag.MOOD"}, "locked": true})
	wantStatus(t, resp, 200, "lock the tag")

	result := metadataCommit(t, h, pid, map[string]any{
		"fields":     map[string]string{"title": "Landed First"},
		"tagSets":    map[string]any{"MOOD": []string{"calm"}},
		"unofficial": true,
		"lock":       false,
	})

	want := []string{
		"fields=committed",
		"tagSet[MOOD]=refused",
		"releaseStatus=skipped",
	}
	if got := commitStatuses(result); !slices.Equal(got, want) {
		t.Fatalf("parts = %v, want %v", got, want)
	}
	refused := result.Parts[1]
	if refused.Refusal == nil {
		t.Fatal("a refused part carries no error")
	}
	if refused.Refusal.Code != "field-locked" {
		t.Errorf("refusal code = %q, want field-locked (no new codes here)", refused.Refusal.Code)
	}

	// The part before the refusal really committed, and the one after it
	// really did not.
	md := h.itemMeta(t, pid)
	if md.Fields["title"] != "Landed First" {
		t.Errorf("title = %q, want the committed value", md.Fields["title"])
	}
	if md.Unofficial {
		t.Error("a skipped part was applied")
	}
}

// TestMetadataCommitRefusesAnEmptyDraft covers the body checks that
// commit nothing at all, which are the ones that answer a status code
// rather than a part.
func TestMetadataCommitRefusesAnEmptyDraft(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := h.items(t, "").Items[0].Pid

	for _, tc := range []struct {
		name string
		body map[string]any
	}{
		{"nothing staged", map[string]any{"lock": false}},
		{"empty fields map", map[string]any{"fields": map[string]string{}}},
		{"lyrics and their removal at once", map[string]any{
			"lyrics": map[string]any{"plain": "words"}, "clearLyrics": true,
		}},
		{"lyrics with no text", map[string]any{"lyrics": map[string]any{}}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			resp := h.postJSON(t, "/api/v1/items/"+pid+"/metadata/commit", tc.body)
			wantStatus(t, resp, 400, tc.name)
		})
	}

	resp := h.postJSON(t, "/api/v1/items/tr-01JZX5N8QW3F4V9T2B7KD3M9R6/metadata/commit",
		map[string]any{"fields": map[string]string{"title": "Nope"}})
	wantStatus(t, resp, 404, "an unknown item")
}

// TestMetadataCommitReportsWriteBackFailures is the reason a refusal is
// a 200: what the committed parts could not write to disk is what the
// editor's banner is made of, and a status code would discard it.
func TestMetadataCommitReportsWriteBackFailures(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	h := newHarness(t)

	var pid string
	for _, it := range h.items(t, "").Items {
		if it.Title == "Alpha Song" {
			pid = it.Pid
		}
	}
	if pid == "" {
		t.Fatal("no Alpha Song item")
	}
	// Both the file and its directory: the tag writer replaces the file
	// atomically, so a writable directory would let it succeed anyway.
	alpha := filepath.Join(h.library, "alpha.flac")
	if _, err := os.Stat(alpha); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(alpha, 0o444); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(h.library, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = os.Chmod(h.library, 0o755)
		_ = os.Chmod(alpha, 0o644)
	})

	result := metadataCommit(t, h, pid, map[string]any{
		"fields":     map[string]string{"title": "Write Me Back"},
		"unofficial": true,
		"writeBack":  true,
		"lock":       false,
	})
	if got := commitStatuses(result); !slices.Equal(got, []string{"fields=committed", "releaseStatus=committed"}) {
		t.Fatalf("parts = %v, want both committed", got)
	}
	if result.WriteBackFailures == nil || len(*result.WriteBackFailures) == 0 {
		t.Fatal("an unwritable file produced no write-back failure")
	}
	// The catalog write still landed; write-back trouble rides along.
	if h.itemMeta(t, pid).Fields["title"] != "Write Me Back" {
		t.Error("the catalog edit did not commit")
	}
}

// TestMetadataCommitEnforcesItsDeclaredBounds keeps the collection caps
// the contract declares from having no owner: the generated binding
// does not enforce them, and every sibling edit surface checks its own
// at the door. Without this a caller who may curate one item hands the
// orchestrator an arbitrarily long step list, each step a catalog write.
func TestMetadataCommitEnforcesItsDeclaredBounds(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := h.items(t, "").Items[0].Pid

	credits := make([]map[string]any, 51)
	for i := range credits {
		credits[i] = map[string]any{"role": "producer", "names": []string{"X"}}
	}
	tagSets := map[string]any{}
	for i := 0; i < 101; i++ {
		tagSets[fmt.Sprintf("K%03d", i)] = []string{"v"}
	}
	removes := make([]string, 101)
	for i := range removes {
		removes[i] = fmt.Sprintf("K%03d", i)
	}

	for _, tc := range []struct {
		name string
		body map[string]any
	}{
		{"too many credit roles", map[string]any{"credits": credits}},
		{"too many tag sets", map[string]any{"tagSets": tagSets}},
		{"too many tag removals", map[string]any{"tagRemoves": removes}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			resp := h.postJSON(t, "/api/v1/items/"+pid+"/metadata/commit", tc.body)
			wantStatus(t, resp, 400, tc.name)
		})
	}
}

// TestMetadataCommitWordsARefusalLikeTheEndpointItStandsIn is the
// parity the sequential fallback rests on: the same refusal has to read
// the same whichever path the session took, because it is drawn in
// front of the person who typed the value.
func TestMetadataCommitWordsARefusalLikeTheEndpointItStandsIn(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := h.items(t, "").Items[0].Pid

	resp := h.putJSON(t, "/api/v1/items/"+pid+"/locks",
		map[string]any{"fields": []string{"title"}, "locked": true})
	wantStatus(t, resp, 200, "lock the title")

	// The per-field endpoint's own words.
	resp = h.patchJSON(t, "/api/v1/items/"+pid+"/metadata",
		map[string]any{"fields": map[string]string{"title": "Nope"}, "lock": false})
	if resp.StatusCode != 409 {
		t.Fatalf("sequential edit status = %d, want 409", resp.StatusCode)
	}
	sequential := decode[Error](t, resp)

	result := metadataCommit(t, h, pid, map[string]any{
		"fields": map[string]string{"title": "Nope"}, "lock": false,
	})
	if len(result.Parts) != 1 || result.Parts[0].Refusal == nil {
		t.Fatalf("parts = %+v, want one refused part", result.Parts)
	}
	compound := *result.Parts[0].Refusal
	if compound.Code != sequential.Code || compound.Message != sequential.Message {
		t.Errorf("compound refusal = %+v, want the sequential path's %+v", compound, sequential)
	}
	if !strings.Contains(compound.Message, "title") {
		t.Errorf("refusal message = %q, want it to name the locked field", compound.Message)
	}
}

// TestMetadataAcquisitionEdit covers the correction verbs. The origin
// used to be read-only, which left a wrong one permanently wrong: the
// automatic recorder is merge-wise and never lowers a field, so an
// empty value in a later event keeps whatever stands. These two write
// every editable column as sent and take the row off outright.
func TestMetadataAcquisitionEdit(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	// A SOURCE_URL tag is what makes the scan record an origin at all,
	// and the row it writes reads `manual` with the tag's own url and
	// id - which is the wrong-origin case this surface exists for.
	// Duration distinct from every other preset, for the
	// fingerprint-dedup reason DemoLibrary gives.
	if _, err := fixtures.Generate(h.library, fixtures.Spec{
		Name: "misattributed", Codec: fixtures.CodecFLAC, Duration: 6200 * time.Millisecond,
		Tags: map[string]string{
			"TITLE": "Misattributed Cut", "ARTIST": "Nobody In Particular",
			"SOURCE_URL": "https://wrong.example.test/show/ep-99.mp3",
			"SOURCE_ID":  "ep-99",
		},
	}); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)

	pid := ""
	for _, it := range h.items(t, "").Items {
		if it.Title == "Misattributed Cut" {
			pid = it.Pid
		}
	}
	if pid == "" {
		t.Fatal("the misattributed fixture did not scan")
	}
	before := h.itemMeta(t, pid).Acquisition
	if before == nil || before.SourceType != "manual" {
		t.Fatalf("scanned origin = %+v, want a manual tag-derived row", before)
	}
	if before.SourceId == nil || *before.SourceId != "ep-99" {
		t.Fatalf("scanned sourceId = %v, want the tag's", before.SourceId)
	}
	if before.Locked != nil && *before.Locked {
		t.Fatal("a tag-derived origin arrived locked")
	}

	// The correction. provider is sent, sourceId deliberately is not:
	// an absent column is cleared, which is the rule that makes lowering
	// a wrong value possible at all.
	stamp := time.Date(2024, 3, 4, 5, 6, 7, 0, time.UTC)
	resp := putJSON(t, h.ts, "/api/v1/items/"+pid+"/acquisition", h.token, map[string]any{
		"sourceType": "rss",
		"sourceUrl":  "https://right.example.test/feed/ep-1.mp3",
		"provider":   "rss",
		"acquiredAt": stamp.Format(time.RFC3339),
	})
	wantStatus(t, resp, 200, "correct the origin")

	after := h.itemMeta(t, pid).Acquisition
	if after == nil {
		t.Fatal("the corrected item carries no origin")
	}
	if after.SourceType != "rss" {
		t.Errorf("sourceType = %q, want rss", after.SourceType)
	}
	if after.SourceUrl == nil || *after.SourceUrl != "https://right.example.test/feed/ep-1.mp3" {
		t.Errorf("sourceUrl = %v, want the corrected one", after.SourceUrl)
	}
	if after.SourceId != nil {
		t.Errorf("sourceId = %q, want the absent column cleared", *after.SourceId)
	}
	if after.AcquiredAt == nil || !after.AcquiredAt.Equal(stamp) {
		t.Errorf("acquiredAt = %v, want %v", after.AcquiredAt, stamp)
	}
	// The lock is on by default, which is what stops the next scan
	// re-deriving the wrong row from tags still in the file.
	if after.Locked == nil || !*after.Locked {
		t.Error("the correction left the origin unlocked")
	}
	if md := h.itemMeta(t, pid); !containsString(md.LockedFields, "acquisition") {
		t.Errorf("lockedFields = %v, want acquisition", md.LockedFields)
	}

	// A second correction over the standing lock is refused, and goes
	// through with force.
	resp = putJSON(t, h.ts, "/api/v1/items/"+pid+"/acquisition", h.token,
		map[string]any{"sourceType": "youtube"})
	wantStatus(t, resp, 409, "correct a locked origin")
	resp = putJSON(t, h.ts, "/api/v1/items/"+pid+"/acquisition", h.token,
		map[string]any{"sourceType": "youtube", "force": true})
	wantStatus(t, resp, 200, "force over the lock")
	if got := h.itemMeta(t, pid).Acquisition; got == nil || got.SourceType != "youtube" {
		t.Fatalf("forced origin = %+v, want youtube", got)
	}
	// The forced write cleared every absent column, the acquiredAt
	// included - it carries forward only because it is the one field
	// absence means "keep" for.
	if got := h.itemMeta(t, pid).Acquisition; got.AcquiredAt == nil || !got.AcquiredAt.Equal(stamp) {
		t.Errorf("acquiredAt after a forced rewrite = %v, want the standing stamp", got.AcquiredAt)
	}

	// An unrecognized type is refused rather than stored, and so is
	// `local`, which is spelled by having no row at all.
	for _, bad := range []string{"telepathy", "local", ""} {
		resp = putJSON(t, h.ts, "/api/v1/items/"+pid+"/acquisition", h.token,
			map[string]any{"sourceType": bad, "force": true})
		wantStatus(t, resp, 400, "set sourceType "+bad)
	}

	// The redacted-URL trap. The read strips userinfo, query and
	// fragment, so a client is never shown the stored string in full -
	// and a form that resent what it displayed would replace a
	// ?v=XYZ with the truncated form. An absent sourceUrl therefore
	// keeps what stands; only an explicit empty string clears it.
	wantStatus(t, putJSON(t, h.ts, "/api/v1/items/"+pid+"/acquisition", h.token, map[string]any{
		"sourceType": "youtube",
		"sourceUrl":  "https://www.youtube.test/watch?v=dQw4w9WgXcQ",
		"force":      true,
	}), 200, "state a URL carrying a query")
	if got := h.itemMeta(t, pid).Acquisition; got.SourceUrl == nil ||
		*got.SourceUrl != "https://www.youtube.test/watch" {
		t.Fatalf("read-back sourceUrl = %v, want the redacted form", got.SourceUrl)
	}
	// Correcting only the provider, the way the sheet does when nobody
	// touched the address box.
	wantStatus(t, putJSON(t, h.ts, "/api/v1/items/"+pid+"/acquisition", h.token, map[string]any{
		"sourceType": "youtube", "provider": "waxtap", "force": true,
	}), 200, "correct the provider alone")
	// Write it back, which is the only way to read the stored string in
	// full: the file gets it verbatim while the API read redacts.
	wantStatus(t, putJSON(t, h.ts, "/api/v1/items/"+pid+"/acquisition", h.token, map[string]any{
		"sourceType": "youtube", "provider": "waxtap", "writeBack": true, "force": true,
	}), 200, "and again with write-back")
	// The query survived two corrections that never mentioned the URL.
	if got := acquisitionTagsOf(t, filepath.Join(h.library, "misattributed.flac")); got["SOURCE_URL"] !=
		"https://www.youtube.test/watch?v=dQw4w9WgXcQ" {
		t.Errorf("the untouched URL did not survive a correction: %v", got)
	}
	// An explicit empty string is how it comes off.
	wantStatus(t, putJSON(t, h.ts, "/api/v1/items/"+pid+"/acquisition", h.token, map[string]any{
		"sourceType": "manual", "sourceUrl": "", "force": true,
	}), 200, "clear the URL explicitly")
	if got := h.itemMeta(t, pid).Acquisition; got.SourceUrl != nil {
		t.Errorf("sourceUrl = %q after an explicit clear", *got.SourceUrl)
	}

	// Write-back is what makes a correction outlive a rescan without
	// leaning on the lock: the file's own tags carry it, so the scan
	// re-derives the corrected row rather than the wrong one.
	resp = putJSON(t, h.ts, "/api/v1/items/"+pid+"/acquisition", h.token, map[string]any{
		"sourceType": "rss",
		"sourceUrl":  "https://right.example.test/feed/ep-1.mp3",
		"sourceId":   "ep-1",
		"writeBack":  true,
		"force":      true,
	})
	wantStatus(t, resp, 200, "correct with write-back")
	if got := acquisitionTagsOf(t, filepath.Join(h.library, "misattributed.flac")); got["SOURCE_ID"] != "ep-1" ||
		got["SOURCE_URL"] != "https://right.example.test/feed/ep-1.mp3" {
		t.Errorf("file tags after write-back = %v", got)
	}

	// The clear takes the row off, and is idempotent.
	wantStatus(t, h.deleteReq(t, "/api/v1/items/"+pid+"/acquisition?force=true"), 204, "clear the origin")
	if got := h.itemMeta(t, pid).Acquisition; got != nil {
		t.Fatalf("origin after the clear = %+v, want absent", got)
	}
	wantStatus(t, h.deleteReq(t, "/api/v1/items/"+pid+"/acquisition?force=true"), 204, "clear again")
}

// A non-curator gets the same refusal here as on every other item-scoped
// mutation: the origin is curated metadata, not a read.
func TestMetadataAcquisitionEditNeedsCurate(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	page := h.items(t, "")
	if len(page.Items) == 0 {
		t.Fatal("no items in the demo library")
	}
	pid := page.Items[0].Pid
	wantStatus(t, h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "listener", "password": "long-enough-pw",
	}), 201, "create non-admin user")
	listener := loginAs(t, h.ts, "listener", "long-enough-pw").Token

	wantStatus(t, reqAs(t, h, "PUT", "/api/v1/items/"+pid+"/acquisition", listener,
		map[string]any{"sourceType": "rss"}), 403, "a listener correcting an origin")
	wantStatus(t, reqAs(t, h, "DELETE", "/api/v1/items/"+pid+"/acquisition", listener, nil),
		403, "a listener clearing an origin")
}

// acquisitionTagsOf reads a file's origin tags back off disk, which is
// the only place a write-back can be confirmed: the read surface
// redacts the URL and reports the catalog's row, not the file's.
func acquisitionTagsOf(t *testing.T, path string) map[string]string {
	t.Helper()
	doc, err := waxlabel.ParseFile(context.Background(), path)
	if err != nil {
		t.Fatalf("reading %s: %v", filepath.Base(path), err)
	}
	out := map[string]string{}
	for key, name := range map[tag.Key]string{
		tag.SourceURL: "SOURCE_URL", tag.SourceID: "SOURCE_ID",
	} {
		if vals, ok := doc.Get(key); ok && len(vals) > 0 {
			out[name] = vals[0]
		}
	}
	return out
}
