package api

import (
	"fmt"
	"net/url"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// A merge answers the name it folded, the listing shows it with the
// entity it files under, and an unfold releases it: all or nothing, for
// administrators only.
func TestAMergedNameIsListedAndUnfolded(t *testing.T) {
	t.Parallel()
	dupes := t.TempDir()
	if _, err := fixtures.Generate(dupes,
		fixtures.Spec{Name: "golf", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second, Tags: map[string]string{
			"TITLE": "Golf Song", "ARTIST": "Fold Artist", "ALBUM": "Fold Album"}},
		fixtures.Spec{Name: "india", Codec: fixtures.CodecFLAC, Duration: 3 * time.Second, Tags: map[string]string{
			"TITLE": "India Song", "ARTIST": "The Fold Artist", "ALBUM": "Other Fold Album"}},
	); err != nil {
		t.Fatalf("generating duplicate fixtures: %v", err)
	}
	h := newHarness(t, service.Root{Name: "dupes", Path: dupes})
	var grp *DuplicateGroup
	groups := decode[DuplicateGroups](t, get(t, h.ts, "/api/v1/library/duplicates", h.token)).Groups
	for i := range groups {
		if groups[i].EntityType == "artist" && strings.Contains(groups[i].Survivor.Name, "Fold Artist") {
			grp = &groups[i]
		}
	}
	if grp == nil || len(grp.Losers) != 1 {
		t.Fatalf("no Fold Artist group in %+v", groups)
	}
	resp := h.postJSON(t, "/api/v1/library/duplicates/merge", map[string]any{
		"entityType": "artist", "survivorPid": grp.Survivor.Pid, "loserPids": []string{grp.Losers[0].Pid},
	})
	merged := decode[MergeResult](t, resp)
	key := strings.ToLower(grp.Losers[0].Name)
	if resp.StatusCode != 200 || len(merged.Folds) != 1 || merged.Folds[0] != key {
		t.Fatalf("merge = %d %+v, want the loser's name %q folded", resp.StatusCode, merged, key)
	}

	listed := func() []EntityFold {
		t.Helper()
		resp := get(t, h.ts, "/api/v1/library/folds", h.token)
		if resp.StatusCode != 200 {
			t.Fatalf("folds status = %d", resp.StatusCode)
		}
		return decode[EntityFoldPage](t, resp).Folds
	}
	folds := listed()
	if len(folds) != 1 {
		t.Fatalf("folds = %+v, want the merge's", folds)
	}
	if f := folds[0]; f.EntityType != "artist" || f.Key != key || f.Spelling != key ||
		f.EntityPid != "ar-"+grp.Survivor.Pid || f.EntityName != grp.Survivor.Name || f.CreatedAt.IsZero() {
		t.Fatalf("fold = %+v, want %q under the survivor %s", f, key, grp.Survivor.Pid)
	}

	for _, q := range []string{"limit=0", "limit=501", "cursor=" + url.QueryEscape("not a cursor")} {
		wantStatus(t, get(t, h.ts, "/api/v1/library/folds?"+q, h.token), 400, "folds with "+q)
	}
	wantStatus(t, h.postJSON(t, "/api/v1/library/folds/unfold", map[string]any{"entityType": "playlist", "keys": []string{key}}),
		400, "an unknown entity type")
	wantStatus(t, h.postJSON(t, "/api/v1/library/folds/unfold", map[string]any{"entityType": "artist", "keys": []string{}}),
		400, "no keys")

	resp = h.postJSON(t, "/api/v1/library/folds/unfold", map[string]any{"entityType": "artist", "keys": []string{key, "never folded"}})
	if e := decode[Error](t, resp); resp.StatusCode != 404 || e.Code != "not-found" || !strings.Contains(e.Message, "never folded") {
		t.Fatalf("unfolding a missing key = %d %+v, want not-found naming it", resp.StatusCode, e)
	}
	if len(listed()) != 1 {
		t.Fatal("a refused unfold forgot a fold")
	}

	resp = h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	wantStatus(t, resp, 201, "creating a member")
	sam := loginAs(t, h.ts, "sam", testPassword).Token
	wantStatus(t, get(t, h.ts, "/api/v1/library/folds", sam), 403, "a member's listing")
	wantStatus(t, reqAs(t, h, "POST", "/api/v1/library/folds/unfold", sam, map[string]any{"entityType": "artist", "keys": []string{key}}),
		403, "a member's unfold")

	wantStatus(t, h.postJSON(t, "/api/v1/library/folds/unfold", map[string]any{"entityType": "artist", "keys": []string{key}}),
		204, "the unfold")
	if folds := listed(); len(folds) != 0 {
		t.Fatalf("folds after the unfold = %+v, want none", folds)
	}
}

// Folds that spell alike carry what tells them apart: two copies of one
// release in two folders merge, and the fold names its folder within its
// library and that library, never the server's own directories.
func TestAFoldCarriesWhatTellsItApart(t *testing.T) {
	t.Parallel()
	dupes := t.TempDir()
	for i, dir := range []string{"Kilo", "Kilo Again"} {
		if _, err := fixtures.Generate(filepath.Join(dupes, dir), fixtures.Spec{
			Name: fmt.Sprintf("kilo%d", i), Codec: fixtures.CodecFLAC, Duration: time.Duration(2+i) * time.Second,
			Tags: map[string]string{"TITLE": fmt.Sprintf("Kilo Song %d", i), "ARTIST": "Kilo Artist",
				"ALBUMARTIST": "Kilo Artist", "ALBUM": "Kilo Album", "TRACKNUMBER": "1"},
		}); err != nil {
			t.Fatal(err)
		}
	}
	h := newHarness(t, service.Root{Name: "dupes", Path: dupes})
	var grp *DuplicateGroup
	groups := decode[DuplicateGroups](t, get(t, h.ts, "/api/v1/library/duplicates", h.token)).Groups
	for i := range groups {
		if groups[i].EntityType == "album" && groups[i].Survivor.Name == "Kilo Album" {
			grp = &groups[i]
		}
	}
	if grp == nil {
		t.Fatalf("no Kilo Album group in %+v", groups)
	}
	resp := h.postJSON(t, "/api/v1/library/duplicates/merge", map[string]any{
		"entityType": "album", "survivorPid": grp.Survivor.Pid, "loserPids": []string{grp.Losers[0].Pid},
	})
	merged := decode[MergeResult](t, resp)
	if resp.StatusCode != 200 || len(merged.Folds) != 1 {
		t.Fatalf("merge = %d %+v", resp.StatusCode, merged)
	}
	for _, f := range decode[EntityFoldPage](t, get(t, h.ts, "/api/v1/library/folds", h.token)).Folds {
		if f.Key != merged.Folds[0] {
			continue
		}
		if f.Spelling != "kilo artist - kilo album" || f.Folder == nil || *f.Folder != "Kilo Again" ||
			f.Library == nil || *f.Library != "dupes" || f.Facet != nil {
			t.Fatalf("fold = %+v (folder %v, library %v), want Kilo Again within dupes", f, deref(f.Folder), deref(f.Library))
		}
		return
	}
	t.Fatalf("the merge's fold %q is not listed", merged.Folds[0])
}
