package service

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// transcriptDoc is one episode's transcript as its host serves it.
type transcriptDoc struct{ typ, body string }

func vttDoc(body string) transcriptDoc { return transcriptDoc{"text/vtt", body} }

// transcriptShow subscribes to a show with one episode per document, each
// pointing its transcript at the document, served and declared under its
// type, and returns the episodes' pids in the documents' order and a count
// of the transcript fetches its host answers.
func transcriptShow(t *testing.T, docs ...transcriptDoc) (context.Context, *Library, *UserCtx, []string, *atomic.Int32) {
	t.Helper()
	var fetched atomic.Int32
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if n, ok := strings.CutPrefix(r.URL.Path, "/t/"); ok {
			fetched.Add(1)
			i, _ := strconv.Atoi(n)
			w.Header().Set("Content-Type", docs[i].typ)
			fmt.Fprint(w, docs[i].body)
			return
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		var items strings.Builder
		for i, doc := range docs {
			fmt.Fprintf(&items, `<item><title>Ep %[2]d</title><guid>tx-%[2]d</guid><pubDate>Mon, 0%[3]d Jan 2024 10:00:00 +0000</pubDate>
<enclosure url="http://%[1]s/%[2]d.mp3" type="audio/mpeg" length="10"/>
<podcast:transcript url="http://%[1]s/t/%[2]d" type="%[4]s"/></item>`, r.Host, i, i+1, doc.typ)
		}
		fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0" xmlns:podcast="https://podcastindex.org/namespace/1.0"><channel><title>Transcript Show</title>%s</channel></rss>`, items.String())
	}))
	t.Cleanup(ts.Close)
	dir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
	})
	sub, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: ts.URL + "/feed.xml"})
	if err != nil {
		t.Fatal(err)
	}
	eps, _, err := svc.Episodes(ctx, uc, sub.Show.PID, "", 50)
	if err != nil || len(eps) != len(docs) {
		t.Fatalf("episodes = %d (%v), want %d", len(eps), err, len(docs))
	}
	pids := make([]string, len(docs))
	for _, ep := range eps {
		var i int
		fmt.Sscanf(ep.Title, "Ep %d", &i)
		pids[i] = ep.PID
	}
	return ctx, svc, uc, pids, &fetched
}

// vttOf is a VTT document of n cues, each of text.
func vttOf(n int, text string) string {
	var b strings.Builder
	b.WriteString("WEBVTT\n\n")
	for i := range n {
		fmt.Fprintf(&b, "00:%02d:%02d.000 --> 00:%02d:%02d.500\n%s\n\n", i/60%60, i%60, i/60%60, i%60, text)
	}
	return b.String()
}

// A transcript past the cue cap, or one whose cues would make a row past
// the row cap, is refused as too large and none of its cues are kept: an
// 8 MiB document of one-character cues would otherwise sit in the
// database as an 18 MB row and be decoded whole on every read.
func TestAnOversizedTranscriptIsRefusedAndNotKept(t *testing.T) {
	t.Parallel()
	tiny := vttOf(1, "x")
	for len(tiny) < transcriptMaxBytes-64 {
		tiny += tiny[len("WEBVTT\n\n"):]
	}
	tiny = tiny[:strings.LastIndex(tiny[:transcriptMaxBytes-64], "\n\n")+2]
	docs := []transcriptDoc{vttDoc(tiny), vttDoc(vttOf(40_000, strings.Repeat("y", 120)))}
	ctx, svc, uc, pids, _ := transcriptShow(t, docs...)
	for i, pid := range pids {
		_, err := svc.Transcript(ctx, uc, pid)
		var se *Error
		if !errors.As(err, &se) || se.Kind != KindUpstream || FeedFailureReason(err) != reasonTooLarge ||
			se.Msg != transcriptSentences[reasonTooLarge] {
			t.Errorf("document %d (%d bytes): %v, want the too-large refusal", i, len(docs[i].body), err)
		}
		_, bare, _ := parseAPIPID(pid)
		row, err := svc.db.TranscriptCacheFor(ctx, string(bare))
		if err == nil && (!row.Negative || row.Cues != "") {
			t.Errorf("document %d: kept a row of %d bytes", i, len(row.Cues))
		} else if err != nil && !errors.Is(err, wdb.ErrNotFound) {
			t.Fatal(err)
		}
	}
}

// Every stored transcript holds the cache to its bound, and the one that
// goes is the one read longest ago: reading a transcript keeps it.
func TestTheTranscriptCacheHoldsItsBound(t *testing.T) {
	t.Parallel()
	doc := vttDoc(vttOf(20, "a word or two"))
	ctx, svc, uc, pids, _ := transcriptShow(t, doc, doc, doc)
	bare := make([]string, len(pids))
	for i, pid := range pids {
		_, b, _ := parseAPIPID(pid)
		bare[i] = string(b)
	}
	read := func(i int) {
		t.Helper()
		if tx, err := svc.Transcript(ctx, uc, pids[i]); err != nil || len(tx.Cues) != 20 {
			t.Fatalf("transcript %d = %d cues (%v)", i, len(tx.Cues), err)
		}
	}
	read(0)
	_, one, err := svc.db.TranscriptCacheSize(ctx)
	if err != nil || one == 0 {
		t.Fatalf("one row = %d bytes (%v)", one, err)
	}
	svc.transcriptCacheBytes = 2*one + one/2
	read(1)
	ago := func(d time.Duration) int64 { return time.Now().Add(-d).UnixNano() }
	if err := svc.db.TouchTranscriptCache(ctx, bare[0], ago(3*time.Hour)); err != nil {
		t.Fatal(err)
	}
	if err := svc.db.TouchTranscriptCache(ctx, bare[1], ago(2*time.Hour)); err != nil {
		t.Fatal(err)
	}
	read(0)
	if row, err := svc.db.TranscriptCacheFor(ctx, bare[0]); err != nil || row.ReadAtNS < ago(time.Minute) {
		t.Fatalf("a cached read left the row read at %d (%v)", row.ReadAtNS, err)
	}
	read(2)
	for i, want := range []bool{true, false, true} {
		_, err := svc.db.TranscriptCacheFor(ctx, bare[i])
		if kept := err == nil; kept != want {
			t.Errorf("transcript %d kept = %v, want %v", i, kept, want)
		}
	}
	if _, size, err := svc.db.TranscriptCacheSize(ctx); err != nil || size > svc.transcriptCacheBytes {
		t.Errorf("cache = %d bytes (%v), want at most %d", size, err, svc.transcriptCacheBytes)
	}
}

// One cue past the cue cap is refused as too large in every format, and
// keeps no cues, though its cues would fit in a row: a document of short
// cues is held to the count, not only to its size.
func TestATranscriptPastTheCueCapIsRefused(t *testing.T) {
	t.Parallel()
	var srt, segments strings.Builder
	for i := range transcriptMaxCues + 1 {
		fmt.Fprintf(&srt, "%d\n00:%02d:%02d,000 --> 00:%02d:%02d,500\nword\n\n", i+1, i/60%60, i%60, i/60%60, i%60)
		if i > 0 {
			segments.WriteByte(',')
		}
		fmt.Fprintf(&segments, `{"startTime":%d,"endTime":%d.5,"body":"word"}`, i, i)
	}
	docs := []transcriptDoc{
		vttDoc(vttOf(transcriptMaxCues+1, "word")),
		{"application/srt", srt.String()},
		{"application/json", `{"segments":[` + segments.String() + `]}`},
	}
	ctx, svc, uc, pids, _ := transcriptShow(t, docs...)
	for i, pid := range pids {
		_, err := svc.Transcript(ctx, uc, pid)
		if FeedFailureReason(err) != reasonTooLarge {
			t.Errorf("%s document of %d cues: %v, want the too-large refusal", docs[i].typ, transcriptMaxCues+1, err)
		}
		_, bare, _ := parseAPIPID(pid)
		if row, err := svc.db.TranscriptCacheFor(ctx, string(bare)); err == nil && row.Cues != "" {
			t.Errorf("%s document kept a row of %d bytes", docs[i].typ, len(row.Cues))
		}
	}
	at := vttDoc(vttOf(transcriptMaxCues, "word"))
	ctx, svc, uc, pids, _ = transcriptShow(t, at)
	if tx, err := svc.Transcript(ctx, uc, pids[0]); err != nil || len(tx.Cues) != transcriptMaxCues {
		t.Errorf("a document at the cap = %d cues (%v), want all %d", len(tx.Cues), err, transcriptMaxCues)
	}
}

// A cached row past the row cap is never decoded: the transcript is
// fetched again instead.
func TestACachedRowPastTheCapIsNotDecoded(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, pids, fetched := transcriptShow(t, vttDoc(vttOf(1, "fresh")))
	_, bare, _ := parseAPIPID(pids[0])
	planted, err := encodeTranscriptCues([]TranscriptCue{{Text: "planted"}})
	if err != nil {
		t.Fatal(err)
	}
	planted = strings.TrimSuffix(planted, "]") + strings.Repeat(`,{"Text":"planted"}`, transcriptRowMaxBytes/18) + "]"
	if len(planted) <= transcriptRowMaxBytes {
		t.Fatalf("planted row = %d bytes, want past %d", len(planted), transcriptRowMaxBytes)
	}
	if err := svc.db.PutTranscriptCache(ctx, wdb.TranscriptRow{
		EpisodePID: string(bare), Format: "vtt", Cues: planted, FetchedAtNS: time.Now().UnixNano(),
	}); err != nil {
		t.Fatal(err)
	}
	before := fetched.Load()
	tx, err := svc.Transcript(ctx, uc, pids[0])
	if err != nil || len(tx.Cues) != 1 || tx.Cues[0].Text != "fresh" {
		t.Fatalf("transcript = %d cues (%v), want the one fetched again", len(tx.Cues), err)
	}
	if fetched.Load() == before {
		t.Error("the transcript was not fetched again")
	}
}
