package api

import (
	"io"
	"net/http"
	"slices"
	"strings"
	"testing"
)

const transcriptDocV1 = "WEBVTT\n\n00:00.000 --> 00:01.500\nMembers only\n"

// transcriptFixture is a subscription to a feed whose one episode points at
// a transcript document a docHost answers.
type transcriptFixture struct {
	h       *harness
	episode EpisodeSummary
}

func subscribeToTranscriptFeed(t *testing.T, doc *docHost, wrap func(http.Handler) http.Handler, pointer string, creds map[string]any) transcriptFixture {
	t.Helper()
	h := newPodcastHarness(t)
	body := map[string]any{"url": newTranscriptFeed(t, doc, wrap, pointer)}
	for k, v := range creds {
		body[k] = v
	}
	sub := decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", body), http.StatusCreated, "subscribe")
	eps := decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)).Items
	if len(eps) != 1 || eps[0].HasTranscript == nil || !*eps[0].HasTranscript {
		t.Fatalf("episodes = %+v, want one that announces a transcript", eps)
	}
	return transcriptFixture{h: h, episode: eps[0]}
}

// transcriptAs reads the episode's transcript with token.
func (f transcriptFixture) transcriptAs(t *testing.T, token string) (int, string) {
	t.Helper()
	resp := get(t, f.h.ts, "/api/v1/episodes/"+f.episode.Pid+"/transcript", token)
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	return resp.StatusCode, string(body)
}

// A credentialed show's transcript is read on the terms its audio is: for
// a subscriber and no one else. A non-subscriber is refused before the host
// is asked or the kept answer is read, so a subscriber's read never becomes
// theirs.
func TestTranscriptOfACredentialedShowIsForItsSubscribersOnly(t *testing.T) {
	t.Parallel()
	doc := &docHost{}
	doc.set(http.StatusOK, transcriptDocV1)
	f := subscribeToTranscriptFeed(t, doc, memberOnly, "", memberCreds)
	_, sam := listenerAccount(t, f.h, "sam", true)

	if code, body := f.transcriptAs(t, sam); code != http.StatusForbidden || !strings.Contains(body, `"forbidden"`) {
		t.Fatalf("a non-subscriber's transcript = %d: %s, want forbidden", code, body)
	}
	if n := doc.asked(); n != 0 {
		t.Fatalf("the host was asked %d times on a non-subscriber's behalf", n)
	}
	if code, body := f.transcriptAs(t, f.h.token); code != http.StatusOK || !strings.Contains(body, "Members only") {
		t.Fatalf("the subscriber's transcript = %d: %s", code, body)
	}
	if code, body := f.transcriptAs(t, sam); code != http.StatusForbidden || strings.Contains(body, "Members only") {
		t.Errorf("a non-subscriber after the subscriber's read = %d: %s, want forbidden", code, body)
	}
	if n := doc.asked(); n != 1 {
		t.Errorf("the host was asked %d times in all, want the subscriber's one", n)
	}
}

// An open show's transcript stays open to anyone who can see the podcast
// library, subscriber or not.
func TestAnOpenShowsTranscriptIsForEveryListener(t *testing.T) {
	t.Parallel()
	doc := &docHost{}
	doc.set(http.StatusOK, transcriptDocV1)
	f := subscribeToTranscriptFeed(t, doc, nil, "", nil)
	_, sam := listenerAccount(t, f.h, "sam", true)

	if code, body := f.transcriptAs(t, sam); code != http.StatusOK || !strings.Contains(body, "Members only") {
		t.Errorf("a non-subscriber's transcript of an open show = %d: %s", code, body)
	}
}

// The credentials go to the feed's own origin and nowhere else: a pointer
// at another host is read without them.
func TestTranscriptOnAnotherHostGetsNoCredentials(t *testing.T) {
	t.Parallel()
	doc, elsewhere := &docHost{}, &docHost{}
	elsewhere.set(http.StatusOK, transcriptDocV1)
	f := subscribeToTranscriptFeed(t, doc, memberOnly, newDocElsewhere(t, elsewhere, transcriptDoc), memberCreds)

	if code, body := f.transcriptAs(t, f.h.token); code != http.StatusOK || !strings.Contains(body, "Members only") {
		t.Fatalf("transcript = %d: %s, want the other host's document", code, body)
	}
	if auths := elsewhere.authorizations(); len(auths) != 1 || auths[0] != "" {
		t.Errorf("the other host was sent %q, want one request with no Authorization", auths)
	}
	if n := doc.asked(); n != 0 {
		t.Errorf("the feed's own host was asked %d times for a document it does not hold", n)
	}
}

// A document that sends the reader elsewhere takes the credentials no
// further, even to the same machine on another port, which an HTTP client's
// own rule lets them reach.
func TestTranscriptRedirectedAwayLosesTheCredentials(t *testing.T) {
	t.Parallel()
	doc, elsewhere := &docHost{}, &docHost{}
	elsewhere.set(http.StatusOK, transcriptDocV1)
	doc.redirectTo(newDocElsewhere(t, elsewhere, transcriptDoc))
	f := subscribeToTranscriptFeed(t, doc, memberOnly, "", memberCreds)

	if code, body := f.transcriptAs(t, f.h.token); code != http.StatusOK || !strings.Contains(body, "Members only") {
		t.Fatalf("transcript = %d: %s, want the document the redirect led to", code, body)
	}
	if auths := doc.authorizations(); len(auths) != 1 || auths[0] == "" {
		t.Errorf("the feed's host was sent %q, want one request with its credentials", auths)
	}
	if auths := elsewhere.authorizations(); len(auths) != 1 || auths[0] != "" {
		t.Errorf("the host the redirect led to was sent %q, want one request with no Authorization", auths)
	}
}

// A pointer at another host that sends the reader back to the feed's own
// host is read there with the credentials.
func TestTranscriptSentBackToTheOriginGetsTheCredentials(t *testing.T) {
	t.Parallel()
	doc, elsewhere := &docHost{}, &docHost{}
	doc.set(http.StatusOK, transcriptDocV1)
	h := newPodcastHarness(t)
	feed := newTranscriptFeed(t, doc, memberOnly, newDocElsewhere(t, elsewhere, transcriptDoc))
	elsewhere.redirectTo(strings.TrimSuffix(feed, "/feed.xml") + transcriptDoc)
	sub := decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{
		"url": feed, "username": "member", "password": "s3cret",
	}), http.StatusCreated, "subscribe")
	eps := decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)).Items
	if len(eps) != 1 {
		t.Fatalf("episodes = %+v, want one", eps)
	}
	f := transcriptFixture{h: h, episode: eps[0]}

	if code, body := f.transcriptAs(t, h.token); code != http.StatusOK || !strings.Contains(body, "Members only") {
		t.Fatalf("transcript = %d: %s, want the feed's own document", code, body)
	}
	if auths := elsewhere.authorizations(); len(auths) != 1 || auths[0] != "" {
		t.Errorf("the other host was sent %q, want one request with no Authorization", auths)
	}
	if auths := doc.authorizations(); len(auths) != 1 || auths[0] == "" {
		t.Errorf("the feed's host was sent %q, want one request with its credentials", auths)
	}
}

// A document that moves within the feed's own origin keeps them.
func TestTranscriptMovedWithinTheOriginKeepsTheCredentials(t *testing.T) {
	t.Parallel()
	doc := &docHost{}
	doc.set(http.StatusOK, transcriptDocV1)
	doc.moveTo("/moved/transcript.vtt")
	f := subscribeToTranscriptFeed(t, doc, memberOnly, "", memberCreds)

	if code, body := f.transcriptAs(t, f.h.token); code != http.StatusOK || !strings.Contains(body, "Members only") {
		t.Fatalf("transcript = %d: %s, want the document at its new path", code, body)
	}
	if auths := doc.authorizations(); len(auths) != 2 || auths[0] == "" || !slices.Equal(auths, []string{auths[0], auths[0]}) {
		t.Errorf("the feed's host was sent %q, want both asks with its credentials", auths)
	}
}
