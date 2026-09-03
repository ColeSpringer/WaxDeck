package api

import (
	"io"
	"testing"
)

// TestBPMEditsAndReadsBack follows a track's tempo through every
// surface it now has: the editor's own field, the item read, and the
// Subsonic song shape clients sort playlists by.
func TestBPMEditsAndReadsBack(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := h.items(t, "").Items[0].Pid

	// The vocabulary offers it, and says it writes back: BPM is a tag a
	// scan reads, not something anyone measured.
	vocab := decode[MetadataFields](t, get(t, h.ts, "/api/v1/metadata/fields", h.token))
	var music *KindFields
	for i := range vocab.Kinds {
		if vocab.Kinds[i].Kind == MediaTypeMusic {
			music = &vocab.Kinds[i]
		}
	}
	if music == nil {
		t.Fatal("no music kind in the field vocabulary")
	}
	var bpm *EditableField
	for i := range music.Fields {
		if music.Fields[i].Name == "bpm" {
			bpm = &music.Fields[i]
		}
	}
	if bpm == nil || !bpm.WriteBack {
		t.Fatalf("bpm field = %+v, want a write-back field", bpm)
	}
	// And the keys it owns are named, so a custom-tag editor can refuse
	// one before the round trip.
	if vocab.ReservedTagKeys == nil || !containsString(*vocab.ReservedTagKeys, "BPM") {
		t.Fatalf("reservedTagKeys = %v, want BPM among them", vocab.ReservedTagKeys)
	}

	resp := h.patchJSON(t, "/api/v1/items/"+pid+"/metadata", map[string]any{
		"fields": map[string]string{"bpm": "128"},
	})
	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("bpm edit status = %d: %s", resp.StatusCode, body)
	}

	if got := h.itemMeta(t, pid).Fields["bpm"]; got != "128" {
		t.Fatalf("editor bpm = %q, want 128", got)
	}
	item := decode[Item](t, get(t, h.ts, "/api/v1/items/"+pid, h.token))
	if item.Bpm == nil || *item.Bpm != 128 {
		t.Fatalf("item bpm = %v, want 128", item.Bpm)
	}

	// Subsonic carries it on the song, which is what a client sorting a
	// crate by tempo reads.
	var song struct {
		Song struct {
			ID  string `json:"id"`
			BPM int    `json:"bpm"`
		} `json:"song"`
	}
	subsonicJSON(t, h, "getSong", newSubsonicSecret(t, h), "&id="+pid, &song)
	if song.Song.ID != pid || song.Song.BPM != 128 {
		t.Fatalf("subsonic song = %+v, want bpm 128 on %s", song.Song, pid)
	}

	// Upstream owns the bounds and the refusal keeps its sentence.
	wantStatus(t, h.patchJSON(t, "/api/v1/items/"+pid+"/metadata", map[string]any{
		"fields": map[string]string{"bpm": "999999"}, "force": true,
	}), 400, "a tempo past the catalog's ceiling")
	wantStatus(t, h.patchJSON(t, "/api/v1/items/"+pid+"/metadata", map[string]any{
		"fields": map[string]string{"bpm": "120.5"}, "force": true,
	}), 400, "a fractional tempo")

	// And the key it owns is not also a custom tag.
	wantStatus(t, putJSON(t, h.ts, "/api/v1/items/"+pid+"/tags/BPM", h.token,
		map[string]any{"values": []string{"140"}}), 400, "BPM as a custom tag")
}
