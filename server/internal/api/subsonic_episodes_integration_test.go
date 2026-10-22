package api

import (
	"encoding/json"
	"net/http"
	"os"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// Subsonic clients read an episode's format off its suffix and
// contentType (DSub names its cached file by the suffix, Symfonium badges
// the format), so an episode carries real ones: the fetched file's, or
// for one the server has not fetched the type its feed declared, held to
// the relay's rule. getSong answers an episode by the id its streamId
// names.
func TestSubsonicEpisodesCarryTheirFormat(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	secret := newSubsonicSecret(t, h)
	const c = "test"
	feed := newFeedServer(t, 2)
	sub, _ := firstEpisode(t, h, feed.feedURL(), nil)
	eps := decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)).Items
	wantStatus(t, h.postJSON(t, "/api/v1/episodes/"+eps[0].Pid+"/fetch", nil), 202, "fetching the newest episode")
	drainFetches(t, h)
	_, video := firstEpisode(t, h, typedEnclosureHost(t, "video/mp4", "video/mp4", "video bytes"), nil)
	_, mislabeled := firstEpisode(t, h, typedEnclosureHost(t, "text/html", "application/octet-stream", "audio bytes"), nil)

	env := mustOK(t, h, secret, c, "getPodcasts", "&includeEpisodes=true")
	listed := map[string]map[string]any{}
	for _, ch := range jlist(jmap(env["podcasts"])["channel"]) {
		for _, ep := range jlist(jmap(ch)["episode"]) {
			id, _ := jmap(ep)["id"].(string)
			listed[id] = jmap(ep)
		}
	}
	for _, want := range []struct {
		name, pid, suffix, contentType string
	}{
		{"a fetched episode", eps[0].Pid, "mp3", "audio/mpeg"},
		{"an unfetched episode", eps[1].Pid, "mp3", "audio/mpeg"},
		{"a video enclosure", video.Pid, "mp4", "audio/mp4"},
		{"a feed declaring a page", mislabeled.Pid, "mp3", "audio/mpeg"},
	} {
		ep, ok := listed[want.pid]
		if !ok {
			t.Errorf("%s is not listed", want.name)
			continue
		}
		if ep["suffix"] != want.suffix || ep["contentType"] != want.contentType {
			t.Errorf("%s = suffix %v, contentType %v; want %s, %s",
				want.name, ep["suffix"], ep["contentType"], want.suffix, want.contentType)
		}
	}

	song := jmap(mustOK(t, h, secret, c, "getSong", "&id="+eps[1].Pid)["song"])
	if song["id"] != eps[1].Pid || song["parent"] != sub.Show.Pid || song["type"] != "podcast" ||
		song["suffix"] != "mp3" || song["contentType"] != "audio/mpeg" {
		t.Errorf("getSong of an episode = %v", song)
	}
	env = clientCall(t, h, secret, c, "getSong", "&id=ep-01JZX5N8QW3F4V9T2B7KD3M9R6")
	if env["status"] != "failed" || jmap(env["error"])["code"] != float64(70) {
		t.Errorf("getSong of an unknown episode = %v, want error 70", env)
	}
}

// A fetched episode's format is its file's own, not the one its feed
// declared: a feed that says mp3 over an Ogg file is listed as Ogg once
// the file is here.
func TestSubsonicFetchedEpisodesCarryTheirFilesFormat(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	secret := newSubsonicSecret(t, h)
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "vorbis", Codec: fixtures.CodecVorbis, Container: fixtures.ContainerOgg, Duration: 2 * time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}
	ogg, err := os.ReadFile(paths[0])
	if err != nil {
		t.Fatal(err)
	}
	_, ep := firstEpisode(t, h, typedEnclosureHost(t, "audio/mpeg", "application/octet-stream", string(ogg)), nil)
	song := func() map[string]any {
		t.Helper()
		return jmap(mustOK(t, h, secret, "test", "getSong", "&id="+ep.Pid)["song"])
	}
	if s := song(); s["suffix"] != "mp3" || s["contentType"] != "audio/mpeg" {
		t.Fatalf("before the fetch = suffix %v, contentType %v; want the declared mp3", s["suffix"], s["contentType"])
	}
	wantStatus(t, h.postJSON(t, "/api/v1/episodes/"+ep.Pid+"/fetch", nil), 202, "fetching the episode")
	drainFetches(t, h)
	if s := song(); s["suffix"] != "ogg" || s["contentType"] != "audio/ogg" {
		t.Errorf("after the fetch = suffix %v, contentType %v; want the file's ogg, audio/ogg", s["suffix"], s["contentType"])
	}
}

// getSong answers an episode from what the song carries, so the chapters
// document its feed names is not read for it.
func TestSubsonicGetSongOfAnEpisodeAsksNoChaptersHost(t *testing.T) {
	t.Parallel()
	doc := &docHost{status: http.StatusOK, body: `{"chapters":[{"startTime":0,"title":"One"}]}`}
	f := subscribeToChaptersFeed(t, doc, nil, "", nil)
	secret := newSubsonicSecret(t, f.h)
	if n := doc.asked(); n != 0 {
		t.Fatalf("the chapters host was asked %d times before getSong", n)
	}
	song := jmap(mustOK(t, f.h, secret, "test", "getSong", "&id="+f.episode.Pid)["song"])
	if song["id"] != f.episode.Pid || song["parent"] != f.episode.ShowPid || song["type"] != "podcast" ||
		song["title"] != "Chapter Pilot" || song["contentType"] != "audio/mpeg" {
		t.Errorf("getSong of an episode = %v", song)
	}
	if n := doc.asked(); n != 0 {
		t.Errorf("the chapters host was asked %d times for getSong", n)
	}
}

// getSong holds an episode to its show's advisory as every other read
// does: an episode of a show that declares itself explicit says so, and an
// account without explicit content is answered as for no such song.
func TestSubsonicGetSongOfAnEpisodeHoldsItsShowsAdvisory(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	cf := newCountsFeedAs(t, countsChannel{explicit: true}, []countsEpisode{{title: "Clean Words"}})
	sub, ep := firstEpisode(t, h, cf.feedURL(), nil)
	adult := jmap(mustOK(t, h, newSubsonicSecret(t, h), "test", "getSong", "&id="+ep.Pid)["song"])
	if adult["id"] != ep.Pid || adult["parent"] != sub.Show.Pid || adult["explicitStatus"] != "explicit" {
		t.Errorf("getSong as an account with explicit content = %v, want the show's advisory", adult)
	}
	kid := restrictedListener(t, h, "kid")
	secret := decodeStatus[AppPasswordCreated](t, reqAs(t, h, http.MethodPost, "/api/v1/users/me/app-passwords", kid,
		map[string]any{"label": "subsonic"}), 201, "minting an app password").Secret
	resp, err := http.Get(h.ts.URL + "/rest/getSong.view?apiKey=" + secret + "&v=1.16.1&c=test&f=json&id=" + ep.Pid)
	if err != nil {
		t.Fatal(err)
	}
	var wrapper map[string]map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&wrapper); err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	env := wrapper["subsonic-response"]
	if env["status"] != "failed" || jmap(env["error"])["code"] != float64(70) {
		t.Errorf("getSong as an account without explicit content = %v, want error 70", env)
	}
}

// getSong holds an episode to the podcast grant, as every other read of
// one does: an account granted other libraries only, though it followed
// the show while it could, is answered as for no such song.
func TestSubsonicGetSongOfAnEpisodeHoldsThePodcastGrant(t *testing.T) {
	t.Parallel()
	g := newPodcastGrants(t)
	formerID, former := g.account(t, "former", g.musicLib, g.podcastLib)
	wantStatus(t, reqAs(t, g.h, http.MethodPost, "/api/v1/podcasts", former, map[string]any{"url": g.feedURL(t)}), 201, "subscribing while granted")
	secret := decodeStatus[AppPasswordCreated](t, reqAs(t, g.h, http.MethodPost, "/api/v1/users/me/app-passwords", former,
		map[string]any{"label": "subsonic"}), 201, "minting an app password").Secret
	getSong := func(pid string) map[string]any {
		t.Helper()
		resp, err := http.Get(g.h.ts.URL + "/rest/getSong.view?apiKey=" + secret + "&v=1.16.1&c=test&f=json&id=" + pid)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		var wrapper map[string]map[string]any
		if err := json.NewDecoder(resp.Body).Decode(&wrapper); err != nil {
			t.Fatal(err)
		}
		return wrapper["subsonic-response"]
	}
	if env := getSong(g.unfetched); env["status"] != "ok" {
		t.Fatalf("getSong while granted = %v", env)
	}
	resp := g.h.patchJSON(t, "/api/v1/users/"+formerID, map[string]any{
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{g.musicLib}},
	})
	resp.Body.Close()
	for _, pid := range []string{g.fetched, g.unfetched} {
		if env := getSong(pid); env["status"] != "failed" || jmap(env["error"])["code"] != float64(70) {
			t.Errorf("getSong of %s without the podcast grant = %v, want error 70", pid, env)
		}
	}
}
