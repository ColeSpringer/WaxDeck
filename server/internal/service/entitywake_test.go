package service

import (
	"context"
	"sync"
	"testing"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
)

// catalogWoken reports whether the feed, once level with the log, left a
// catalog wake pending, and takes it.
func catalogWoken(t *testing.T, ctx context.Context, svc *Library) bool {
	t.Helper()
	feedCaughtUp(t, ctx, svc)
	select {
	case <-svc.catalogWake:
		return true
	default:
		return false
	}
}

// entityOnlyRows reads the change rows past since and fails unless they
// name the entity type and no item or podcast, so a wake that follows is
// the entity row's own.
func entityOnlyRows(t *testing.T, ctx context.Context, svc *Library, since int64, entityType string) {
	t.Helper()
	rows, err := svc.lib.Changes(ctx, since)
	if err != nil {
		t.Fatal(err)
	}
	named := false
	for _, ch := range rows {
		switch ch.EntityType {
		case entityType:
			named = true
		case "item", "podcast":
			t.Fatalf("the write logged a %s row, which wakes clients on its own", ch.EntityType)
		}
	}
	if !named {
		t.Fatalf("the write logged no %s row: %+v", entityType, rows)
	}
}

// portraitProvider answers every artist target with one image.
type portraitProvider struct {
	mu    sync.Mutex
	asked int
	img   []byte
}

func (p *portraitProvider) Name() string                    { return "faces" }
func (p *portraitProvider) Capabilities() enrich.Capability { return enrich.CapArtistArt }
func (p *portraitProvider) Enrich(_ context.Context, req enrich.Request) (*enrich.Candidate, error) {
	if req.Type != enrich.TargetArtist {
		return nil, nil
	}
	p.mu.Lock()
	p.asked++
	p.mu.Unlock()
	return &enrich.Candidate{
		Confidence: 0.7,
		Art: map[model.ArtRole]*model.ArtImage{model.ArtRoleFront: {
			Data:        p.img,
			Format:      "png",
			Attribution: model.Attribution{SourceURL: "https://faces.example/fixture.png"},
		}},
	}, nil
}

// A portrait set by hand writes an artist row and no item row, and a
// client drawing that artist has to hear of it.
func TestAnArtistPortraitWakesClients(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	_, artist := fixtureEntityPIDs(t, ctx, svc, uc)
	// Settled first: a row the scan's sweep writes late would read as the
	// write's own.
	settleCatalogFeed(t, svc)
	catalogWoken(t, ctx, svc)
	head := feedTail(svc)

	if _, err := svc.Editor.SetEntityArtwork(ctx, uc, "artist", artist, "front", coverPNG(t, 40), false); err != nil {
		t.Fatal(err)
	}
	entityOnlyRows(t, ctx, svc, head, "artist")
	if !catalogWoken(t, ctx, svc) {
		t.Fatal("an artist's new portrait woke no client")
	}
}

// So does a portrait the enrichment pass fetched.
func TestABackfilledPortraitWakesClients(t *testing.T) {
	t.Parallel()
	faces := &portraitProvider{img: coverPNG(t, 90)}
	ctx, svc, _ := newCatalogFixtureWith(t, catalogFixtureOptions{enrichers: []enrich.Provider{faces}})
	settleCatalogFeed(t, svc)
	catalogWoken(t, ctx, svc)
	head := feedTail(svc)

	pid, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{})
	if err != nil {
		t.Fatal(err)
	}
	waitForJob(t, ctx, svc, pid)
	faces.mu.Lock()
	asked := faces.asked
	faces.mu.Unlock()
	if asked == 0 {
		t.Fatal("the pass asked for no portrait")
	}
	entityOnlyRows(t, ctx, svc, head, "artist")
	if !catalogWoken(t, ctx, svc) {
		t.Fatal("a backfilled portrait woke no client")
	}
}

// Every catalog entity a client draws wakes the catalog topic, in the
// change log's own spellings; rows no mirror or listing reads do not.
func TestEntityRowsWakeTheCatalogTopic(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	// Settled first, so no row of the fixture's own wakes the topic
	// between a case's clearing of the wake and its reading of it.
	settleCatalogFeed(t, svc)
	for _, tc := range []struct {
		entityType string
		want       bool
	}{
		{"item", true},
		{"podcast", true},
		{"artist", true},
		{"album", true},
		{"release_group", true},
		{"genre", true},
		{"series", true},
		{"file", false},
		{"play_state", false},
		{"playlist", false},
	} {
		catalogWoken(t, ctx, svc)
		// Seq 0 leaves the feed's position alone, and no time makes the row
		// one from before the boot, which resets and refreshes nothing.
		svc.advanceFeed(ctx, model.Change{EntityType: tc.entityType, EntityPID: "x", Op: model.OpUpdate})
		select {
		case <-svc.catalogWake:
			if !tc.want {
				t.Errorf("a %s row woke the catalog topic", tc.entityType)
			}
		default:
			if tc.want {
				t.Errorf("a %s row woke nothing", tc.entityType)
			}
		}
	}
}
