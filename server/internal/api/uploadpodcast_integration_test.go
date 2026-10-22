package api

import (
	"context"
	"net/http"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

const podcastUploadRefusal = "podcasts are added by subscribing to a feed"

// wantPodcastRefused reads one door's answer: a plain invalid-request
// carrying the sentence that says where podcasts come from.
func wantPodcastRefused(t *testing.T, resp *http.Response, door string) {
	t.Helper()
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("%s: status = %d, want 400", door, resp.StatusCode)
	}
	e := decode[Error](t, resp)
	if e.Code != "invalid-request" || e.Message != podcastUploadRefusal {
		t.Fatalf("%s: error = %+v, want invalid-request %q", door, e, podcastUploadRefusal)
	}
}

// A podcast-labelled file became an episode of a show nobody follows:
// invisible to its uploader and refused the one verb that would clear it.
// Podcasts come from feeds, so every door an upload can enter by refuses
// the label, and the refusal creates nothing.
func TestUploadDoorsRefusePodcasts(t *testing.T) {
	t.Parallel()
	src := &fakeAcquireSource{playlistURL: "https://tube.example/watch?v=one"}
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.SourceProviders = append(cfg.SourceProviders, src)
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
		cfg.AllowPrivateFeedHosts = true
	})
	uploads := func() int {
		return len(decode[UploadPage](t, get(t, h.ts, "/api/v1/uploads", h.token)).Uploads)
	}
	tasks := func() int {
		return len(decode[ToolTaskPage](t, get(t, h.ts, "/api/v1/tools/tasks", h.token)).Tasks)
	}
	batches := func() int {
		var n int
		if err := h.store.Reader().QueryRowContext(context.Background(), `SELECT COUNT(*) FROM upload_batches`).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}

	t.Run("session", func(t *testing.T) {
		body := map[string]any{"fileName": "ep.mp3", "sizeBytes": 1024, "mediaType": "podcast"}
		wantPodcastRefused(t, h.postJSON(t, "/api/v1/uploads", body), "a podcast session")
		if n := uploads(); n != 0 {
			t.Fatalf("the refusal left %d sessions", n)
		}
		body["mediaType"] = "music"
		wantStatus(t, h.postJSON(t, "/api/v1/uploads", body), http.StatusCreated, "the same session as music")
	})

	t.Run("batch", func(t *testing.T) {
		body := map[string]any{"grouping": "tracks", "mediaType": "podcast"}
		wantPodcastRefused(t, h.postJSON(t, "/api/v1/uploads/batches", body), "a podcast batch")
		if n := batches(); n != 0 {
			t.Fatalf("the refusal left %d batches", n)
		}
		body["mediaType"] = "audiobook"
		wantStatus(t, h.postJSON(t, "/api/v1/uploads/batches", body), http.StatusCreated, "the same batch as an audiobook")
		if n := batches(); n != 1 {
			t.Fatalf("batches after the audiobook one = %d, want it alone", n)
		}
	})

	t.Run("acquisition", func(t *testing.T) {
		body := map[string]any{"url": "https://tube.example/watch?v=one", "mediaType": "podcast"}
		wantPodcastRefused(t, h.postJSON(t, "/api/v1/acquisitions", body), "a podcast acquisition")
		if n := tasks(); n != 0 {
			t.Fatalf("the refusal queued %d tasks", n)
		}
		body["mediaType"] = "music"
		wantStatus(t, h.postJSON(t, "/api/v1/acquisitions", body), http.StatusAccepted, "the same acquisition as music")
	})
}
