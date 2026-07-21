package providers

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/match"
)

func matchFingerprint() match.Fingerprint {
	return match.Fingerprint{Value: "AQAAfingerprint", DurationSec: 215}
}

const acoustOKJSON = `{
  "status": "ok",
  "results": [
    {"score": 0.97,
     "recordings": [
       {"id": "rec-1", "releasegroups": [{"id": "rg-1"}, {"id": "rg-2"}]},
       {"id": "rec-2", "releasegroups": [{"id": "rg-3"}]}
     ]}
  ]
}`

func testAcoust(srv *httptest.Server, key string) *AcoustID {
	return NewAcoustID(AcoustIDConfig{
		BaseURL:     srv.URL,
		APIKey:      key,
		HTTPClient:  srv.Client(),
		MinInterval: time.Nanosecond,
	})
}

func TestAcoustIDLookup(t *testing.T) {
	var gotBody, gotCT atomic.Value
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/lookup" {
			t.Errorf("got %s %s, want POST /lookup", r.Method, r.URL.Path)
		}
		b, _ := io.ReadAll(r.Body)
		gotBody.Store(string(b))
		gotCT.Store(r.Header.Get("Content-Type"))
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(acoustOKJSON))
	}))
	defer srv.Close()

	hits, err := testAcoust(srv, "key123").LookupFingerprint(context.Background(), matchFingerprint())
	if err != nil {
		t.Fatal(err)
	}
	if ct, _ := gotCT.Load().(string); ct != "application/x-www-form-urlencoded" {
		t.Fatalf("Content-Type = %q, want application/x-www-form-urlencoded", ct)
	}
	body, _ := gotBody.Load().(string)
	for _, want := range []string{
		"client=key123",
		"duration=215",
		"fingerprint=AQAAfingerprint",
		"meta=recordingids+releasegroupids",
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("form body %q missing %q", body, want)
		}
	}
	if len(hits) != 2 {
		t.Fatalf("len(hits) = %d, want 2 (one per recording)", len(hits))
	}
	h0 := hits[0]
	if h0.RecordingMBID != "rec-1" || h0.Score != 0.97 {
		t.Fatalf("hit 0 wrong: %+v", h0)
	}
	if len(h0.ReleaseGroupMBIDs) != 2 || h0.ReleaseGroupMBIDs[0] != "rg-1" || h0.ReleaseGroupMBIDs[1] != "rg-2" {
		t.Fatalf("hit 0 release groups wrong: %+v", h0.ReleaseGroupMBIDs)
	}
	if hits[1].RecordingMBID != "rec-2" || len(hits[1].ReleaseGroupMBIDs) != 1 {
		t.Fatalf("hit 1 wrong: %+v", hits[1])
	}
}

func TestAcoustIDEmptyKeyShortCircuits(t *testing.T) {
	var requests atomic.Int64
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
	}))
	defer srv.Close()

	hits, err := testAcoust(srv, "").LookupFingerprint(context.Background(), matchFingerprint())
	if err != nil {
		t.Fatal(err)
	}
	if hits != nil {
		t.Fatalf("want nil hits, got %+v", hits)
	}
	if requests.Load() != 0 {
		t.Fatalf("server requests = %d, want 0", requests.Load())
	}
}

func TestAcoustIDStatusError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status": "error", "error": {"message": "invalid API key"}}`))
	}))
	defer srv.Close()

	_, err := testAcoust(srv, "badkey").LookupFingerprint(context.Background(), matchFingerprint())
	if err == nil || !strings.Contains(err.Error(), "invalid API key") {
		t.Fatalf("want status error carrying the message, got %v", err)
	}
}

func TestSourceDelegation(t *testing.T) {
	var lookups, searches atomic.Int64
	mbSrv := newMBServer(t, `{"releases": [{"id": "rel-1"}]}`, &lookups, &searches)
	defer mbSrv.Close()
	acSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(acoustOKJSON))
	}))
	defer acSrv.Close()

	src := &Source{MB: testMB(mbSrv, time.Nanosecond), Acoust: testAcoust(acSrv, "key123")}
	var _ match.CandidateSource = src

	rel, err := src.ReleaseByMBID(context.Background(), "rel-1")
	if err != nil || rel == nil || rel.Title != "Homework" {
		t.Fatalf("ReleaseByMBID via Source: rel=%+v err=%v", rel, err)
	}
	rels, err := src.SearchReleases(context.Background(), "Daft Punk", "Homework", 16)
	if err != nil || len(rels) != 1 {
		t.Fatalf("SearchReleases via Source: len=%d err=%v", len(rels), err)
	}
	hits, err := src.LookupFingerprint(context.Background(), matchFingerprint())
	if err != nil || len(hits) != 2 {
		t.Fatalf("LookupFingerprint via Source: len=%d err=%v", len(hits), err)
	}
}

func TestSourceFingerprintWithoutAcoustID(t *testing.T) {
	src := &Source{MB: NewMusicBrainz(MusicBrainzConfig{})}
	hits, err := src.LookupFingerprint(context.Background(), matchFingerprint())
	if err != nil || hits != nil {
		t.Fatalf("nil Acoust must be a clean miss, got hits=%+v err=%v", hits, err)
	}

	src.Acoust = NewAcoustID(AcoustIDConfig{})
	hits, err = src.LookupFingerprint(context.Background(), matchFingerprint())
	if err != nil || hits != nil {
		t.Fatalf("empty key must be a clean miss, got hits=%+v err=%v", hits, err)
	}
}
