package api

import (
	"bytes"
	"encoding/json"
	"image"
	"image/color"
	"image/png"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

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
	if len(music.CreditRoles) != 11 {
		t.Fatalf("music roles = %d, want 11", len(music.CreditRoles))
	}
	book := byKind["audiobook"]
	if f := field(book, "author"); f == nil || !f.WriteBack {
		t.Fatalf("book author = %+v, want writeBack true", f)
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
	if len(entities["album"]) != 5 || len(entities["artist"]) != 2 || len(entities["release-group"]) != 3 {
		t.Fatalf("entity vocabulary = %+v", entities)
	}
}

func TestMetadataEditorLifecycle(t *testing.T) {
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
	if md.WriteBackIssues == nil || len(md.WriteBackIssues) != 0 {
		t.Fatalf("writeBackIssues = %+v", md.WriteBackIssues)
	}
	if len(md.LockedFields) != 0 || len(md.CustomTags) != 0 {
		t.Fatalf("fresh item carries locks or tags: %+v", md)
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

	// A field outside the kind's vocabulary is rejected.
	resp = h.patchJSON(t, "/api/v1/items/"+alpha+"/metadata", map[string]any{
		"fields": map[string]string{"narrator": "Nobody"},
	})
	wantStatus(t, resp, 400, "off-vocabulary field")

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
	}
	for _, f := range forbidden {
		resp := metadataReq(t, h.ts, f.method, f.path, sam, f.body)
		if resp.StatusCode != 403 {
			t.Fatalf("non-admin %s %s = %d, want 403", f.method, f.path, resp.StatusCode)
		}
		resp.Body.Close()
	}
}

func TestMetadataBookChapters(t *testing.T) {
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

	// Replacement chapters land on the single-file book and win on read.
	resp := h.putJSON(t, "/api/v1/books/"+single+"/chapters", map[string]any{
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
	// The book-timeline offsets survive the new flat-timeline SetChapters: a
	// single-file book sends file-relative offsets and upstream's legacy-shape
	// sniff maps them onto the timeline, so both starts round-trip exactly.
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

	// Multi-file books keep their part boundaries, an upstream limit.
	resp = h.putJSON(t, "/api/v1/books/"+multi+"/chapters", map[string]any{
		"chapters": []map[string]any{{"index": 0, "startMs": 0, "title": "Nope"}},
	})
	wantStatus(t, resp, 400, "multi-file chapters")

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
