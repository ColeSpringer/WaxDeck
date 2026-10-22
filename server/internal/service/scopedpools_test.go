package service

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxdeck/fixtures"
)

// bulkTracks are short tracks numbered from to from+n by one artist in
// one genre, titled from prefix so they sort together. Each number has a
// length of its own, so no two are one recording to the scanner.
func bulkTracks(prefix string, from, n int) []fixtures.Spec {
	specs := make([]fixtures.Spec, 0, n)
	for i := from; i < from+n; i++ {
		specs = append(specs, fixtures.Spec{
			Name:     fmt.Sprintf("%s%04d", strings.ToLower(prefix), i),
			Codec:    fixtures.CodecFLAC,
			Duration: 100*time.Millisecond + time.Duration(i)*100*time.Microsecond,
			Tags:     map[string]string{"TITLE": fmt.Sprintf("%s %04d", prefix, i), "ARTIST": "Many Hands", "GENRE": "Bulk"},
		})
	}
	return specs
}

// A caller granted one library gets as full a metadata mix as one who
// sees everything, though the libraries they cannot see hold far more of
// the seed's artist and genre, ahead of theirs in every pool's order.
func TestAMetadataMixDrawsFromTheCallersOwnLibraries(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixtureWith(t, catalogFixtureOptions{extra: func(t *testing.T, dir string) {
		if _, err := fixtures.Generate(dir, bulkTracks("Aside", 0, 900)...); err != nil {
			t.Fatal(err)
		}
	}})
	dir := t.TempDir()
	vinyl, err := svc.AddLibrary(ctx, admin, AddLibraryInput{Name: "vinyl", Path: dir, Media: "music"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := fixtures.Generate(dir, bulkTracks("Zside", 900, 30)...); err != nil {
		t.Fatal(err)
	}
	for deadline := time.Now().Add(30 * time.Second); ; {
		_, err := svc.lib.Scan(ctx, waxbin.ScanRequest{})
		if err == nil {
			break
		}
		if KindOf(classify(err)) != KindConflict || time.Now().After(deadline) {
			t.Fatal(err)
		}
		time.Sleep(20 * time.Millisecond)
	}
	granted := &UserCtx{ID: "us-vinyl", CatalogPID: admin.CatalogPID,
		Libraries: map[string]bool{strings.TrimPrefix(vinyl.PID, PrefixLibrary+"-"): true}}
	seed, _ := fixtureTrackPID(t, ctx, svc, granted, "Zside 0900")
	for _, who := range []*UserCtx{admin, granted} {
		res, err := svc.SimilarTracksFor(ctx, who, seed, 19)
		if err != nil {
			t.Fatal(err)
		}
		if len(res.Items) != 19 {
			t.Errorf("a mix for %s = %d tracks, want 19", who.ID, len(res.Items))
		}
		if who == granted {
			for _, it := range res.Items {
				if !strings.HasPrefix(it.Title, "Zside") {
					t.Errorf("the granted caller's mix holds %q from a library it cannot see", it.Title)
				}
			}
		}
	}
}

// The pools carry the caller's tag rules too: a track a deny rule hides
// never reaches the caller's mix.
func TestAMetadataMixKeepsTheCallersContentRules(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newAdvisoryFixture(t)
	kid := &UserCtx{ID: uc.ID, CatalogPID: uc.CatalogPID, AllLibraries: true, Explicit: true,
		TagDeny: []TagRule{{Key: advisoryTagKey, Value: "1"}}}
	seed, _ := fixtureTrackPID(t, ctx, svc, uc, "Unsaid")
	res, err := svc.SimilarTracksFor(ctx, kid, seed, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Items) == 0 {
		t.Fatal("the mix is empty")
	}
	for _, it := range res.Items {
		if it.Title == "Flagged" {
			t.Fatalf("the mix = %+v, holding the track the deny rule hides", res.Items)
		}
	}
}
