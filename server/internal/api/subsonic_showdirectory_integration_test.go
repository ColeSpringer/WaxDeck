package api

import (
	"fmt"
	"net/http"
	"slices"
	"strings"
	"testing"
)

// subsonicAs mints a Subsonic app password for a first-party session.
func subsonicAs(t *testing.T, h *harness, username, token string) subsonicAccount {
	t.Helper()
	return subsonicAccount{username: username, secret: decodeStatus[AppPasswordCreated](t, reqAs(t, h, http.MethodPost,
		"/api/v1/users/me/app-passwords", token, map[string]any{"label": "subsonic"}), 201, "minting an app password").Secret}
}

// listedEpisodes answers the episodes getPodcasts lists for one show, in
// its order, or nil when it lists no such channel.
func listedEpisodes(t *testing.T, h *harness, who subsonicAccount, show string) []map[string]any {
	t.Helper()
	env := clientCallAs(t, h, who, "getPodcasts", "&id="+show)
	if env["status"] != "ok" {
		return nil
	}
	var out []map[string]any
	for _, ch := range jlist(jmap(env["podcasts"])["channel"]) {
		for _, ep := range jlist(jmap(ch)["episode"]) {
			out = append(out, jmap(ep))
		}
	}
	return out
}

// isError70 reports whether an envelope is the protocol's not-found.
func isError70(env map[string]any) bool {
	return env["status"] == "failed" && jmap(env["error"])["code"] == float64(70)
}

// An episode names its show as its parent, so a client walking up from one
// asks for the show as a directory: it answers with the show's title and,
// as children, the very episodes getPodcasts lists for it, each in the
// song shape getPodcasts gives it.
func TestSubsonicShowIsTheDirectoryItsEpisodesName(t *testing.T) {
	t.Parallel()
	g := newPodcastGrants(t)
	admin := subsonicAccount{username: "admin", secret: newSubsonicSecret(t, g.h)}
	listed := listedEpisodes(t, g.h, admin, g.show)
	if len(listed) != 2 || listed[0]["parent"] != g.show {
		t.Fatalf("getPodcasts' episodes = %v, want the fixture's two under %s", listed, g.show)
	}

	env := clientCallAs(t, g.h, admin, "getMusicDirectory", "&id="+fmt.Sprint(listed[0]["parent"]))
	dir := jmap(env["directory"])
	if env["status"] != "ok" || dir["id"] != g.show || dir["name"] != "Fixture Cast" || dir["parent"] != nil {
		t.Fatalf("the show's directory = %v, want %s named Fixture Cast", env, g.show)
	}
	children := jlist(dir["child"])
	if len(children) != len(listed) {
		t.Fatalf("children = %v, want getPodcasts' %d episodes", children, len(listed))
	}
	for i, c := range children {
		got, want := jmap(c), listed[i]
		if got["isDir"] != false || got["type"] != "podcast" || got["parent"] != g.show {
			t.Errorf("child %d = %v, want a podcast song under the show", i, got)
		}
		for _, k := range []string{"id", "title", "artist", "album", "coverArt", "duration", "suffix", "contentType"} {
			if got[k] != want[k] {
				t.Errorf("child %d %s = %v, want getPodcasts' %v", i, k, got[k], want[k])
			}
		}
	}
	_, ct, body := rawSubsonic(t, g.h, "/rest/getMusicDirectory?apiKey="+admin.secret+"&id="+g.show)
	if ct != "application/xml" || !strings.Contains(body, `<directory id="`+g.show+`" name="Fixture Cast">`) ||
		strings.Count(body, `type="podcast"`) != 2 {
		t.Errorf("the show's directory in XML = %s", body)
	}
}

// The show is a directory only to a caller getPodcasts lists its episodes
// to. One who does not follow it, one who followed it but can no longer
// see the podcast library, and a show pid nobody holds are all error 70,
// the answer a directory that does not exist gets.
func TestSubsonicShowDirectoryHoldsWhatGetPodcastsHolds(t *testing.T) {
	t.Parallel()
	g := newPodcastGrants(t)
	admin := subsonicAccount{username: "admin", secret: newSubsonicSecret(t, g.h)}
	_, strangerToken := g.account(t, "stranger", g.musicLib, g.podcastLib)
	stranger := subsonicAs(t, g.h, "stranger", strangerToken)
	formerID, formerToken := g.account(t, "former", g.musicLib, g.podcastLib)
	wantStatus(t, reqAs(t, g.h, http.MethodPost, "/api/v1/podcasts", formerToken, map[string]any{"url": g.feedURL(t)}),
		201, "subscribing while granted")
	former := subsonicAs(t, g.h, "former", formerToken)
	if env := clientCallAs(t, g.h, former, "getMusicDirectory", "&id="+g.show); env["status"] != "ok" ||
		len(jlist(jmap(env["directory"])["child"])) != 2 {
		t.Fatalf("the show's directory while granted = %v, want its two episodes", env)
	}
	wantStatus(t, g.h.patchJSON(t, "/api/v1/users/"+formerID, map[string]any{
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{g.musicLib}},
	}), 200, "taking the podcast library away")

	for _, who := range []subsonicAccount{stranger, former} {
		if listed := listedEpisodes(t, g.h, who, g.show); listed != nil {
			t.Fatalf("getPodcasts lists %v to %s; the case proves nothing", listed, who.username)
		}
		if env := clientCallAs(t, g.h, who, "getMusicDirectory", "&id="+g.show); !isError70(env) {
			t.Errorf("the show's directory for %s = %v, want error 70", who.username, env)
		}
	}
	for _, id := range []string{"pc-01JZX5N8QW3F4V9T2B7KD3M9R6", "pc-", strings.ToLower(g.show), "ep-01JZX5N8QW3F4V9T2B7KD3M9R6"} {
		if env := clientCallAs(t, g.h, admin, "getMusicDirectory", "&id="+id); !isError70(env) {
			t.Errorf("the directory %s = %v, want error 70", id, env)
		}
	}
}

// kidWithAWithheldShow is an account that followed two shows while it had
// explicit content and then lost it: a mixed show with one flagged episode,
// and a show that declares itself explicit. It answers the two show pids.
func kidWithAWithheldShow(t *testing.T) (h *harness, kid subsonicAccount, mixed, adult string) {
	t.Helper()
	h = newPodcastHarness(t)
	id, token := listenerAccount(t, h, "kid", true)
	var shows []string
	for _, feed := range []*countsFeed{
		newCountsFeedAs(t, countsChannel{}, []countsEpisode{{title: "Clean Words"}, {title: "Rude Words", explicit: true}}),
		newCountsFeedAs(t, countsChannel{explicit: true}, []countsEpisode{{title: "Adult Hour"}}),
	} {
		sub := decodeStatus[Subscription](t, reqAs(t, h, http.MethodPost, "/api/v1/podcasts", token,
			map[string]any{"url": feed.feedURL()}), 201, "subscribing while allowed")
		shows = append(shows, sub.Show.Pid)
	}
	wantStatus(t, h.patchJSON(t, "/api/v1/users/"+id, map[string]any{
		"permissions": map[string]any{
			"download": true, "delete": false, "explicitContent": false,
			"sharedOutputs": true, "managePodcasts": true,
		},
	}), 200, "revoking explicit content")
	return h, subsonicAs(t, h, "kid", token), shows[0], shows[1]
}

// titles answers the titles of a list of songs or episodes, in order.
func titles(list []any) []string {
	var out []string
	for _, c := range list {
		out = append(out, fmt.Sprint(jmap(c)["title"]))
	}
	return out
}

// The advisory holds as getPodcasts holds it: a follower without explicit
// content is shown a show's unflagged episodes only, and nothing of a show
// that declares itself explicit, whose directory is error 70 to it.
func TestSubsonicShowDirectoryHoldsTheAdvisory(t *testing.T) {
	t.Parallel()
	h, kid, mixed, adult := kidWithAWithheldShow(t)
	var listed []string
	for _, ep := range listedEpisodes(t, h, kid, mixed) {
		listed = append(listed, fmt.Sprint(ep["title"]))
	}
	if !slices.Equal(listed, []string{"Clean Words"}) {
		t.Fatalf("getPodcasts lists %v to the kid, want the clean episode alone", listed)
	}
	env := clientCallAs(t, h, kid, "getMusicDirectory", "&id="+mixed)
	if got := titles(jlist(jmap(env["directory"])["child"])); env["status"] != "ok" || !slices.Equal(got, listed) {
		t.Errorf("the mixed show's directory for the kid = %v, want the clean episode alone", env)
	}
	if listed := listedEpisodes(t, h, kid, adult); listed != nil {
		t.Fatalf("getPodcasts lists %v of the explicit show to the kid", listed)
	}
	if env := clientCallAs(t, h, kid, "getMusicDirectory", "&id="+adult); !isError70(env) {
		t.Errorf("the explicit show's directory for the kid = %v, want error 70", env)
	}
}

// A show's directory holds what getPodcasts' channel holds, so it is
// bounded the same way: the newest episodes up to the channel's cap.
func TestSubsonicShowDirectoryIsBoundedLikeAChannel(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	var eps []countsEpisode
	for i := range 103 {
		eps = append(eps, countsEpisode{title: fmt.Sprintf("Episode %03d", i+1)})
	}
	sub := decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts",
		map[string]any{"url": newCountsFeedAs(t, countsChannel{}, eps).feedURL()}), 201, "subscribing")
	admin := subsonicAccount{username: "admin", secret: newSubsonicSecret(t, h)}
	listed := listedEpisodes(t, h, admin, sub.Show.Pid)
	children := jlist(jmap(clientCallAs(t, h, admin, "getMusicDirectory", "&id="+sub.Show.Pid)["directory"])["child"])
	if len(listed) != 100 || len(children) != len(listed) {
		t.Fatalf("getPodcasts lists %d, the directory %d; want the channel's 100 in both", len(listed), len(children))
	}
	for i, c := range children {
		if jmap(c)["id"] != listed[i]["id"] {
			t.Fatalf("child %d = %v, want getPodcasts' %v", i, jmap(c)["id"], listed[i]["id"])
		}
	}
	if listed[0]["title"] != "Episode 103" {
		t.Errorf("the first listed = %v, want the newest", listed[0]["title"])
	}
}

// A show withheld from the caller is passed over, not the whole answer:
// getPodcasts lists the other shows, with or without their episodes, and
// getNewestPodcasts their episodes, while the withheld show by id is error
// 70 everywhere, as a show getMusicDirectory will not open.
func TestSubsonicPodcastsPassOverAShowWithheldFromTheCaller(t *testing.T) {
	t.Parallel()
	h, kid, mixed, adult := kidWithAWithheldShow(t)
	env := clientCallAs(t, h, kid, "getPodcasts", "")
	channels := jlist(jmap(env["podcasts"])["channel"])
	if env["status"] != "ok" || len(channels) != 1 || jmap(channels[0])["id"] != mixed ||
		!slices.Equal(titles(jlist(jmap(channels[0])["episode"])), []string{"Clean Words"}) {
		t.Errorf("getPodcasts for the kid = %v, want the mixed show alone with its clean episode", env)
	}
	env = clientCallAs(t, h, kid, "getNewestPodcasts", "")
	if got := titles(jlist(jmap(env["newestPodcasts"])["episode"])); env["status"] != "ok" || !slices.Equal(got, []string{"Clean Words"}) {
		t.Errorf("getNewestPodcasts for the kid = %v, want the clean episode alone", env)
	}
	got := jlist(jmap(clientCallAs(t, h, kid, "getPodcasts", "&includeEpisodes=false")["podcasts"])["channel"])
	if len(got) != 1 || jmap(got[0])["id"] != mixed {
		t.Errorf("getPodcasts without episodes for the kid = %v, want the mixed show alone", got)
	}
	for _, call := range []struct{ view, extra string }{
		{"getPodcasts", "&id=" + adult},
		{"getPodcasts", "&includeEpisodes=false&id=" + adult},
		{"getMusicDirectory", "&id=" + adult},
		{"getArtistInfo", "&id=" + adult},
	} {
		if env := clientCallAs(t, h, kid, call.view, call.extra); !isError70(env) {
			t.Errorf("%s%s for the kid = %v, want error 70", call.view, call.extra, env)
		}
	}
	if env := clientCallAs(t, h, kid, "getArtistInfo", "&id="+mixed); env["status"] != "ok" || env["artistInfo"] == nil {
		t.Errorf("getArtistInfo of the show the kid may open = %v, want the empty info", env)
	}
}

// An episode with nothing to stream (unfetched, its feed naming a playlist
// the relay refuses) lists in getPodcasts without a streamId, and is no
// child of its show's directory, where a song carries no such sign.
func TestSubsonicShowDirectoryLeavesOutWhatCannotPlay(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	admin := subsonicAccount{username: "admin", secret: newSubsonicSecret(t, h)}
	sub, ep := firstEpisode(t, h, typedEnclosureHost(t, "audio/x-mpegurl", "audio/x-mpegurl", "#EXTM3U\n"), nil)
	listed := listedEpisodes(t, h, admin, sub.Show.Pid)
	if len(listed) != 1 || listed[0]["id"] != ep.Pid || listed[0]["streamId"] != nil {
		t.Fatalf("getPodcasts' episodes = %v, want %s alone, with no streamId", listed, ep.Pid)
	}
	env := clientCallAs(t, h, admin, "getMusicDirectory", "&id="+sub.Show.Pid)
	if env["status"] != "ok" || len(jlist(jmap(env["directory"])["child"])) != 0 {
		t.Errorf("the show's directory = %v, want no children", env)
	}
}
