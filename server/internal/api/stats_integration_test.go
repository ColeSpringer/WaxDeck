package api

import (
	"encoding/json"
	"io"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// The recap's audiobook top lists are always arrays, never null.
func TestYearInReviewCarriesAudiobookTops(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	resp := get(t, h.ts, "/api/v1/stats/year-in-review", h.token)
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("status = %d", resp.StatusCode)
	}
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	var body map[string]json.RawMessage
	if err := json.Unmarshal(raw, &body); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"topBooks", "topAuthors"} {
		var list []TopEntry
		if v, ok := body[key]; !ok || string(v) == "null" || json.Unmarshal(v, &list) != nil {
			t.Errorf("%s = %s, want an array", key, body[key])
		}
	}
}

// The stats reads take a medium and the nine top kinds, refuse what the
// contract does not name, and give each entry the pid and picture of what
// it is.
func TestStatsMediaAndTopKinds(t *testing.T) {
	t.Parallel()
	h := newPodcastHarnessWith(t, func(cfg *service.Config) {
		lib := cfg.Roots[0].Path
		if _, err := fixtures.GenerateBook(lib); err != nil {
			t.Fatal(err)
		}
		if _, err := fixtures.Generate(lib, fixtures.Spec{Name: "genre", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
			Tags: map[string]string{"TITLE": "Genre Song", "ARTIST": "Genre Artist", "ALBUM": "Genre Album", "GENRE": "Jazz"}}); err != nil {
			t.Fatal(err)
		}
	})
	feed := newFeedServer(t, 1)
	sub := decode[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()}))
	eps := decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token))
	items := map[string]ItemSummary{}
	for _, mt := range []string{"music", "audiobook"} {
		for _, it := range decode[ItemPage](t, get(t, h.ts, "/api/v1/library/items?mediaType="+mt, h.token)).Items {
			items[it.Title] = it
		}
	}
	genre, book := items["Genre Song"], items["The Fixture Book"]
	if genre.Pid == "" || book.Pid == "" || len(eps.Items) != 1 {
		t.Fatalf("fixture items missing: %+v, episodes %+v", items, eps.Items)
	}
	// A minute ago, but never before today's start, so the listens are
	// today's at any start time.
	now := time.Now().UTC()
	started := now.Add(-time.Minute).Truncate(time.Second)
	if today := now.Truncate(24 * time.Hour); started.Before(today) {
		started = today
	}
	var sessions []map[string]any
	for _, pid := range []string{genre.Pid, eps.Items[0].Pid, book.Pid} {
		sessions = append(sessions, map[string]any{"sessionId": "kinds-" + pid, "pid": pid,
			"startedAt": started.Format(time.RFC3339), "msPlayed": 60_000, "finished": true})
	}
	if res := decode[ListenIngestResult](t, h.postJSON(t, "/api/v1/listens", map[string]any{"sessions": sessions})); res.Accepted != 3 {
		t.Fatalf("ingest = %+v", res)
	}

	refused := func(path string) {
		t.Helper()
		resp := get(t, h.ts, path, h.token)
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != 400 || !strings.Contains(string(body), `"invalid-request"`) {
			t.Errorf("%s = %d %s, want 400 invalid-request", path, resp.StatusCode, body)
		}
	}
	for _, mt := range []string{"music", "podcast", "audiobook", "radio"} {
		stats := decode[ListeningStats](t, get(t, h.ts, "/api/v1/stats/listening?mediaType="+mt, h.token))
		want := 1
		if mt == "radio" {
			want = 0
		}
		if stats.Sessions != want || len(stats.ByMediaType) != want {
			t.Errorf("listening of %s = %+v, want %d session of it alone", mt, stats, want)
		}
		heat := decode[ListeningHeatmap](t, get(t, h.ts, "/api/v1/stats/heatmap?mediaType="+mt, h.token))
		if len(heat.Days) != want {
			t.Errorf("heatmap of %s = %+v", mt, heat)
		}
	}
	refused("/api/v1/stats/listening?mediaType=vinyl")
	refused("/api/v1/stats/heatmap?mediaType=vinyl")
	refused("/api/v1/stats/top?kind=vinyl")

	art := func(pid string) string { return "/api/v1/items/" + pid + "/art" }
	// An artist, author or show with no picture of its own draws its
	// most-listened item's.
	for _, c := range []struct {
		kind, pid, artPid string
	}{
		{"artists", deref(genre.ArtistPid), genre.Pid},
		{"albums", deref(genre.AlbumPid), ""},
		{"tracks", genre.Pid, ""},
		{"genres", "", ""},
		{"shows", sub.Show.Pid, eps.Items[0].Pid},
		{"episodes", eps.Items[0].Pid, ""},
		{"books", book.Pid, ""},
		{"authors", deref(book.ArtistPid), book.Pid},
		{"stations", "", ""},
	} {
		resp := get(t, h.ts, "/api/v1/stats/top?kind="+c.kind, h.token)
		if resp.StatusCode != 200 {
			t.Errorf("kind %s = %d", c.kind, resp.StatusCode)
			resp.Body.Close()
			continue
		}
		list := decode[TopList](t, resp)
		if string(list.Kind) != c.kind {
			t.Errorf("kind %s answers %q", c.kind, list.Kind)
		}
		if c.kind == "stations" {
			if len(list.Entries) != 0 {
				t.Errorf("stations = %+v, want none", list.Entries)
			}
			continue
		}
		if len(list.Entries) != 1 {
			t.Errorf("kind %s = %+v, want one entry", c.kind, list.Entries)
			continue
		}
		e := list.Entries[0]
		if c.pid == "" {
			if e.Pid != nil || e.ArtUrl != nil || e.Name != "Jazz" {
				t.Errorf("genre entry = %+v, want Jazz with no pid and no art", e)
			}
			continue
		}
		drawn := c.artPid
		if drawn == "" {
			drawn = c.pid
		}
		if e.Pid == nil || *e.Pid != c.pid || e.ArtUrl == nil || *e.ArtUrl != art(drawn) {
			t.Errorf("kind %s entry = %+v, want pid %s drawing %s", c.kind, e, c.pid, art(drawn))
			continue
		}
		// An artist or author entry hands out the artist's own pid, which
		// is what an artist mix seeds from.
		if (c.kind == "artists" || c.kind == "authors") && !strings.HasPrefix(*e.Pid, "ar-") {
			t.Errorf("kind %s pid = %v, want an artist pid", c.kind, e.Pid)
		}
	}

	// A track in the trash keeps its name and time, and hands out
	// neither a pid nor a picture.
	wantStatus(t, h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{genre.Pid}, "mode": "trash",
	}), 200, "delete to the trash")
	resp := get(t, h.ts, "/api/v1/stats/top?kind=tracks", h.token)
	raw, err := io.ReadAll(resp.Body)
	resp.Body.Close()
	if err != nil {
		t.Fatal(err)
	}
	var list struct {
		Entries []map[string]json.RawMessage `json:"entries"`
	}
	if err := json.Unmarshal(raw, &list); err != nil {
		t.Fatal(err)
	}
	if len(list.Entries) != 1 {
		t.Fatalf("tracks = %s, want the trashed track", raw)
	}
	e := list.Entries[0]
	_, hasPID := e["pid"]
	_, hasArt := e["artUrl"]
	if hasPID || hasArt || string(e["name"]) != `"Genre Song"` || string(e["ms"]) != "60000" {
		t.Errorf("trashed track entry = %s, want its name and time with no pid and no artUrl", raw)
	}
}
