package service

import (
	"context"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// A Library with nothing but the directory-mirror state wired, which is
// all these methods touch.
func newMirrorLibrary(bases ...string) *Library {
	return &Library{radioDirectoryMirrorList: bases}
}

func TestRadioDirectoryMirrorSelection(t *testing.T) {
	ctx := context.Background()

	// A configured base is an operator pointing at one instance on
	// purpose, so it answers alone: rotating away from a deliberate
	// choice would silently talk to a host nobody asked for.
	l := newMirrorLibrary("https://mirror-a.example", "https://mirror-b.example")
	l.radioDirectoryBase = "https://chosen.example/"
	got := l.radioDirectoryMirrors(ctx)
	if len(got) != 1 || got[0] != "https://chosen.example" {
		t.Fatalf("configured base = %v, want the one base with its slash trimmed", got)
	}

	// Without one, the mirror list is what gets tried, all of it.
	l = newMirrorLibrary("https://mirror-a.example", "https://mirror-b.example", "https://mirror-c.example")
	got = l.radioDirectoryMirrors(ctx)
	if len(got) != 3 {
		t.Fatalf("mirror list = %v, want all three", got)
	}
	seen := map[string]bool{}
	for _, base := range got {
		seen[base] = true
	}
	if len(seen) != 3 {
		t.Fatalf("mirror list = %v, want three distinct bases", got)
	}
}

func TestRadioDirectoryMirrorCooldown(t *testing.T) {
	ctx := context.Background()
	l := newMirrorLibrary("https://sick.example", "https://well.example")

	// A mirror that just failed sorts last rather than away: on an
	// afternoon where every mirror is having one, dropping them would
	// leave nothing to ask.
	l.coolRadioMirror("https://sick.example")
	for i := 0; i < 20; i++ {
		got := l.radioDirectoryMirrors(ctx)
		if len(got) != 2 {
			t.Fatalf("cooled mirrors = %v, want both", got)
		}
		if got[0] != "https://well.example" || got[1] != "https://sick.example" {
			t.Fatalf("cooled order = %v, want the failed mirror last", got)
		}
	}

	// An expired cooldown stops ordering anything, and clears itself so
	// the map cannot grow without bound.
	l.radioMirrorsMu.Lock()
	l.radioMirrorCold["https://sick.example"] = time.Now().Add(-time.Second)
	l.radioMirrorsMu.Unlock()
	l.radioDirectoryMirrors(ctx)
	l.radioMirrorsMu.Lock()
	_, still := l.radioMirrorCold["https://sick.example"]
	l.radioMirrorsMu.Unlock()
	if still {
		t.Fatal("an expired cooldown should be forgotten, not kept")
	}
}

func TestRadioMirrorBases(t *testing.T) {
	got := radioMirrorBases([]*net.SRV{
		{Target: "de1.api.radio-browser.info."},
		{Target: "at1.api.radio-browser.info"},
		{Target: "."},
		{Target: ""},
	})
	want := []string{"https://de1.api.radio-browser.info", "https://at1.api.radio-browser.info"}
	if len(got) != len(want) {
		t.Fatalf("bases = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("bases = %v, want %v", got, want)
		}
	}
}

func TestDecodeRadioDirectory(t *testing.T) {
	// A sick mirror answering 200 must not be mistaken for an answer.
	// `null` is the dangerous one: it unmarshals without error into no
	// rows, so it would read as "no stations match that name" while
	// healthy mirrors went unasked.
	for _, body := range []string{"", "null", "<html>down for maintenance</html>", "{}"} {
		if rows, err := decodeRadioDirectory([]byte(body)); err == nil {
			t.Errorf("body %q decoded to %v, want a refusal", body, rows)
		}
	}
	// An empty list is a real answer and stays one.
	rows, err := decodeRadioDirectory([]byte("[]"))
	if err != nil || rows == nil || len(rows) != 0 {
		t.Fatalf("empty list = (%v, %v), want no rows and no error", rows, err)
	}
	rows, err = decodeRadioDirectory([]byte(`[{"name":"Jazz24","url_resolved":"http://jazz.example/s"}]`))
	if err != nil || len(rows) != 1 || rows[0].Name != "Jazz24" {
		t.Fatalf("one station = (%v, %v)", rows, err)
	}
}

// A directory search is typeahead-shaped: every keystroke cancels the
// request before it. That says nothing about the mirror the cancelled
// request happened to be talking to, and cooling it would put a healthy
// host at the back of the queue for five minutes per letter typed.
func TestCancelledSearchDoesNotCoolMirrors(t *testing.T) {
	reached := make(chan struct{}, 1)
	hold := make(chan struct{})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		select {
		case reached <- struct{}{}:
		default:
		}
		<-hold
	}))
	t.Cleanup(func() { close(hold); srv.Close() })

	l := &Library{
		radioDirectoryMirrorList: []string{srv.URL},
		allowPrivateRadioHosts:   true,
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		_, _ = l.SearchRadioDirectory(ctx, nil, "jazz", 5)
	}()
	<-reached
	cancel()
	<-done

	l.radioMirrorsMu.Lock()
	cooled := len(l.radioMirrorCold)
	l.radioMirrorsMu.Unlock()
	if cooled != 0 {
		t.Fatalf("%d mirrors cooled by a cancelled search, want none", cooled)
	}
}

// A resolver that cannot answer is remembered, or every search pays the
// full lookup timeout before falling back to the round-robin name.
func TestFailedMirrorDiscoveryIsRemembered(t *testing.T) {
	l := &Library{}
	l.radioMirrorsMu.Lock()
	l.radioMirrors, l.radioMirrorsAt = nil, time.Now()
	l.radioMirrorsMu.Unlock()

	start := time.Now()
	got := l.radioDirectoryMirrors(context.Background())
	if elapsed := time.Since(start); elapsed > radioMirrorLookupTimeout/2 {
		t.Fatalf("a remembered failure took %v, want the cached answer", elapsed)
	}
	if len(got) != 1 || got[0] != defaultRadioDirectoryBase {
		t.Fatalf("mirrors = %v, want the round-robin fallback", got)
	}
}

// A search is typeahead-shaped, so the caller going away cancels the
// lookup instantly. Recording that as "there are no mirrors" would pin
// the round-robin name for five minutes, which is the failure the whole
// path exists to end.
func TestCancelledDiscoveryKeepsTheMirrorList(t *testing.T) {
	l := &Library{}
	l.radioMirrorsMu.Lock()
	l.radioMirrors = []string{"https://de1.example", "https://at1.example"}
	// Stale, so the next call would refresh.
	l.radioMirrorsAt = time.Now().Add(-2 * radioMirrorTTL)
	l.radioMirrorsMu.Unlock()

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	got := l.radioDirectoryMirrors(ctx)
	if len(got) != 2 {
		t.Fatalf("mirrors after a cancelled refresh = %v, want the two already known", got)
	}
	l.radioMirrorsMu.Lock()
	held := len(l.radioMirrors)
	l.radioMirrorsMu.Unlock()
	if held != 2 {
		t.Fatalf("the cached list was overwritten with %d entries", held)
	}
}

// A mirror answering 200 with something that is not a list is not a
// status worth printing at a listener.
func TestUndecodableMirrorsDoNotReportStatus200(t *testing.T) {
	var mirrors []string
	for range 3 {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			w.Write([]byte("null"))
		}))
		t.Cleanup(srv.Close)
		mirrors = append(mirrors, srv.URL)
	}
	l := &Library{radioDirectoryMirrorList: mirrors, allowPrivateRadioHosts: true}
	_, err := l.SearchRadioDirectory(context.Background(), nil, "jazz", 5)
	if err == nil {
		t.Fatal("three undecodable mirrors should not read as an answer")
	}
	if msg := err.(*Error).Msg; strings.Contains(msg, "status 200") {
		t.Fatalf("error message = %q, want no mention of a 200", msg)
	}
}
