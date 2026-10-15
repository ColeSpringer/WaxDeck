package service

import (
	"path/filepath"
	"slices"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"

	"github.com/colespringer/waxdeck/fixtures"
)

// The duplicates listing reads its why off the catalog's own audit
// sentence, so the real audit is what pins it: every reason the catalog
// pairs entities for comes through, and a reworded sentence fails here
// rather than reaching the screen as an empty why.
func TestTheDuplicatesListingReadsEveryReasonTheAuditGives(t *testing.T) {
	t.Parallel()
	const mbid = "11111111-1111-4111-8111-111111111111"
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		for i, s := range []struct {
			dir, name, artist, album, artistID string
		}{
			// One name under two collation spellings.
			{"one", "a", "Beatles", "Abbey", ""},
			{"two", "b", "The Beatles", "Road", ""},
			// One album title by one artist, kept apart by its folders.
			{"Blue", "c", "Joni", "Blue", ""},
			{"Blue Again", "d", "Joni", "Blue", ""},
			// Two names carrying one MusicBrainz artist id.
			{"m1", "e", "Alpha", "Ax", mbid},
			{"m2", "f", "Beta", "Bx", mbid},
		} {
			tags := map[string]string{"TITLE": "Song " + s.name, "ARTIST": s.artist, "ALBUMARTIST": s.artist,
				"ALBUM": s.album, "TRACKNUMBER": "1"}
			if s.artistID != "" {
				tags["MUSICBRAINZ_ARTISTID"] = s.artistID
			}
			if _, err := fixtures.Generate(filepath.Join(c.Roots[0].Path, s.dir), fixtures.Spec{
				Name: s.name, Codec: fixtures.CodecFLAC, Duration: time.Duration(2+i) * time.Second, Tags: tags,
			}); err != nil {
				t.Fatal(err)
			}
		}
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	groups, err := svc.ListDuplicateGroups(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	var reasons []string
	for _, g := range groups {
		if g.Detail == "" {
			t.Errorf("%s group %+v has no why", g.EntityType, g)
		}
		if !slices.Contains(reasons, g.Detail) {
			reasons = append(reasons, g.Detail)
		}
	}
	slices.Sort(reasons)
	want := []string{model.ReasonSameAlbumName, "same collation key", "shared MBID"}
	slices.Sort(want)
	if !slices.Equal(reasons, want) {
		t.Fatalf("reasons = %q, want every reason the audit gives: %q", reasons, want)
	}
}
