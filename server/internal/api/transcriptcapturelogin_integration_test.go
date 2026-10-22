package api

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// A credentialed show's transcript is captured on the terms it is read:
// fetched with the show's login for a subscriber, so the episode turns
// up in transcript search, and refused for anyone else before the host is
// asked.
func TestATranscriptCaptureSendsTheShowsLogin(t *testing.T) {
	t.Parallel()
	doc := &docHost{}
	doc.set(http.StatusOK, transcriptDocV1)
	f := subscribeToTranscriptFeed(t, doc, memberOnly, "", memberCreds)
	_, sam := listenerAccount(t, f.h, "sam", true)
	path := "/api/v1/episodes/" + f.episode.Pid + "/transcript"

	wantStatus(t, reqAs(t, f.h, http.MethodPost, path, sam, nil), http.StatusForbidden, "a non-subscriber's capture")
	if n := doc.asked(); n != 0 {
		t.Fatalf("the host was asked %d times on a non-subscriber's behalf", n)
	}
	wantStatus(t, reqAs(t, f.h, http.MethodPost, path, f.h.token, nil), http.StatusNoContent, "the subscriber's capture")
	hits := decode[SearchResults](t, get(t, f.h.ts, "/api/v1/library/search?q=Members", f.h.token)).Episodes
	if len(hits) != 1 || hits[0].Pid != f.episode.Pid {
		t.Errorf("transcript search after the capture = %+v, want the episode", hits)
	}
}

// Capture runs under the caps the read does and says so in the read's
// words, which name no figure: a transcript too large to read is too large
// to capture.
func TestATranscriptTooLargeToReadIsTooLargeToCapture(t *testing.T) {
	t.Parallel()
	big := "WEBVTT\n\n00:00.000 --> 00:01.000\n" + strings.Repeat("word ", 9<<20/5) + "\n"
	host := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/vtt")
		_, _ = io.WriteString(w, big)
	}))
	t.Cleanup(host.Close)
	f := subscribeToTranscriptFeed(t, &docHost{}, nil, host.URL+"/big.vtt", nil)
	path := "/api/v1/episodes/" + f.episode.Pid + "/transcript"
	const sentence = "That transcript is larger than this server accepts."
	wantFeedRefusal(t, reqAs(t, f.h, http.MethodPost, path, f.h.token, nil), http.StatusBadGateway,
		"feed-unreachable", "too-large", sentence, host.URL)
	wantFeedRefusal(t, get(t, f.h.ts, path, f.h.token), http.StatusBadGateway,
		"feed-unreachable", "too-large", sentence, host.URL)
}
