package api

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// A station to hang announcements on. The stream URL is never opened:
// the relay is what fills the now-playing map in production, and these
// tests drive it directly so they exercise the save path rather than
// ICY parsing.
func savedSongStation(t *testing.T, h *harness, name string) RadioStation {
	t.Helper()
	resp := h.postJSON(t, "/api/v1/radio/stations", map[string]any{
		"name": name, "streamUrl": "http://198.51.100.9/" + strings.ToLower(name),
	})
	if resp.StatusCode != 201 {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		t.Fatalf("create station status = %d (%s)", resp.StatusCode, body)
	}
	return decode[RadioStation](t, resp)
}

func TestRadioSavedSongsKeepBothIdentities(t *testing.T) {
	h := newHarness(t)
	st := savedSongStation(t, h, "Deck FM")

	// A line the strict parse recognises stores the split, and one it
	// does not stores itself. Both save; neither refuses the tap.
	parsed := decode[RadioSavedSong](t, mustSave(t, h, st.Pid, "Charlie Parker - Ornithology"))
	if !strings.HasPrefix(parsed.Pid, "rw-") {
		t.Fatalf("saved pid = %q, want an rw- pid", parsed.Pid)
	}
	if parsed.Artist == nil || *parsed.Artist != "Charlie Parker" ||
		parsed.Title == nil || *parsed.Title != "Ornithology" {
		t.Fatalf("parsed save = %+v, want the split fields", parsed)
	}
	if parsed.NowPlaying != "Charlie Parker - Ornithology" {
		t.Fatalf("raw line = %q, want the announcement", parsed.NowPlaying)
	}
	if parsed.StationPid == nil || *parsed.StationPid != st.Pid || parsed.StationName != "Deck FM" {
		t.Fatalf("station snapshot = %+v", parsed)
	}

	raw := decode[RadioSavedSong](t, mustSave(t, h, st.Pid, "Deck FM overnight session"))
	if raw.Artist != nil || raw.Title != nil {
		t.Fatalf("unparsed save = %+v, want no split fields", raw)
	}
	if raw.NowPlaying != "Deck FM overnight session" {
		t.Fatalf("unparsed raw line = %q", raw.NowPlaying)
	}

	// Saving the same announcement again answers the row already held
	// rather than minting a second: the heart is a toggle.
	again := decode[RadioSavedSong](t, mustSave(t, h, st.Pid, "Charlie Parker - Ornithology"))
	if again.Pid != parsed.Pid {
		t.Fatalf("re-save pid = %q, want the held %q", again.Pid, parsed.Pid)
	}
	// And so does the same song announced with different noise around
	// it, which is the whole reason identity is normalized.
	noisy := decode[RadioSavedSong](t, mustSave(t, h, st.Pid, "charlie parker - Ornithology (Official Audio)"))
	if noisy.Pid != parsed.Pid {
		t.Fatalf("noisy re-save pid = %q, want the held %q", noisy.Pid, parsed.Pid)
	}

	page := decode[RadioSavedSongPage](t, get(t, h.ts, "/api/v1/radio/saved", h.token))
	if len(page.Songs) != 2 {
		t.Fatalf("listing = %d songs, want 2: %+v", len(page.Songs), page.Songs)
	}
	// Newest first.
	if page.Songs[0].Pid != raw.Pid || page.Songs[1].Pid != parsed.Pid {
		t.Fatalf("listing order = %q, %q; want newest first", page.Songs[0].Pid, page.Songs[1].Pid)
	}
}

func TestRadioSavedSongMarksWhatTheLibraryNowHolds(t *testing.T) {
	h := newHarness(t)
	st := savedSongStation(t, h, "Deck FM")

	held := decode[RadioSavedSong](t, mustSave(t, h, st.Pid, "Fixture Artist - Alpha Song"))
	missing := decode[RadioSavedSong](t, mustSave(t, h, st.Pid, "Charlie Parker - Ornithology"))

	page := decode[RadioSavedSongPage](t, get(t, h.ts, "/api/v1/radio/saved", h.token))
	byPID := map[string]RadioSavedSong{}
	for _, s := range page.Songs {
		byPID[s.Pid] = s
	}
	// The row the library has since acquired crosses itself off; the
	// one it has not is why the list exists.
	if got := byPID[held.Pid]; got.InLibraryPid == nil || !strings.HasPrefix(*got.InLibraryPid, "tr-") {
		t.Fatalf("matched row = %+v, want an inLibraryPid", got)
	}
	if got := byPID[missing.Pid]; got.InLibraryPid != nil {
		t.Fatalf("unmatched row = %+v, want no inLibraryPid", got)
	}
	// The marking is a read-time resolution and never stored, so the
	// save response itself carries none.
	if held.InLibraryPid != nil {
		t.Fatalf("save response carried inLibraryPid = %v, want none", held.InLibraryPid)
	}
}

func TestRadioSavedSongFlipsThePlayInfoHeart(t *testing.T) {
	h := newHarness(t)
	st := savedSongStation(t, h, "Deck FM")
	h.svc.NoteRadioTitle(st.Pid, "Charlie Parker - Ornithology")

	info := decode[RadioPlayInfo](t, get(t, h.ts, "/api/v1/radio/stations/"+st.Pid+"/play-info", h.token))
	if info.NowPlaying == nil || *info.NowPlaying != "Charlie Parker - Ornithology" {
		t.Fatalf("play-info nowPlaying = %v", info.NowPlaying)
	}
	if info.NowPlayingSaved != nil && *info.NowPlayingSaved {
		t.Fatal("play-info reports the song saved before anything saved it")
	}

	saved := decode[RadioSavedSong](t, mustSave(t, h, st.Pid, "Charlie Parker - Ornithology"))
	info = decode[RadioPlayInfo](t, get(t, h.ts, "/api/v1/radio/stations/"+st.Pid+"/play-info", h.token))
	if info.NowPlayingSaved == nil || !*info.NowPlayingSaved {
		t.Fatal("play-info does not report the song saved")
	}
	if info.NowPlayingSavedPid == nil || *info.NowPlayingSavedPid != saved.Pid {
		t.Fatalf("play-info savedPid = %v, want %q", info.NowPlayingSavedPid, saved.Pid)
	}

	// A rollover empties the heart without touching the list: the flag
	// describes what is announced, not what is kept.
	h.svc.NoteRadioTitle(st.Pid, "Miles Davis - Solar")
	info = decode[RadioPlayInfo](t, get(t, h.ts, "/api/v1/radio/stations/"+st.Pid+"/play-info", h.token))
	if info.NowPlayingSaved != nil && *info.NowPlayingSaved {
		t.Fatal("play-info reports the next song saved")
	}

	// Untapping empties it for the song that is kept.
	h.svc.NoteRadioTitle(st.Pid, "Charlie Parker - Ornithology")
	if resp := h.deleteReq(t, "/api/v1/radio/saved/"+saved.Pid); resp.StatusCode != 204 {
		t.Fatalf("delete status = %d", resp.StatusCode)
	}
	info = decode[RadioPlayInfo](t, get(t, h.ts, "/api/v1/radio/stations/"+st.Pid+"/play-info", h.token))
	if info.NowPlayingSaved != nil && *info.NowPlayingSaved {
		t.Fatal("play-info still reports the removed song saved")
	}
	// Removing one that is already gone is success, so an untap racing
	// a second device is not an error.
	if resp := h.deleteReq(t, "/api/v1/radio/saved/"+saved.Pid); resp.StatusCode != 204 {
		t.Fatalf("second delete status = %d, want 204", resp.StatusCode)
	}
}

func TestRadioSavedSongSnapshotsTheAnnouncedCover(t *testing.T) {
	png := pngPixel
	host := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "image/png")
		w.Write(png)
	}))
	t.Cleanup(host.Close)
	// The announced-art fetch rides the stream proxy's guarded client,
	// so a loopback fake needs the LAN escape hatch.
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.AllowPrivateRadioHosts = true
	})
	st := savedSongStation(t, h, "Deck FM")

	// The picture the station named in its own stream, resolved by the
	// play-info poll and then copied by the save.
	h.svc.NoteRadioMeta(st.Pid, "Charlie Parker - Ornithology", host.URL+"/cover.png")
	waitForSavedSnapshotArt(t, h, st.Pid)

	saved := decode[RadioSavedSong](t, mustSave(t, h, st.Pid, "Charlie Parker - Ornithology"))
	if !saved.HasArt {
		t.Fatal("saved song reports no art, want the announced cover snapshotted")
	}
	resp := get(t, h.ts, "/api/v1/radio/saved/"+saved.Pid+"/art", h.token)
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("art status = %d", resp.StatusCode)
	}
	body, _ := io.ReadAll(resp.Body)
	if string(body) != string(png) {
		t.Fatalf("art body = %d bytes, want the %d snapshotted", len(body), len(png))
	}
	if resp.Header.Get("Content-Type") != "image/png" {
		t.Fatalf("art content-type = %q", resp.Header.Get("Content-Type"))
	}
	if resp.Header.Get("X-Content-Type-Options") != "nosniff" || resp.Header.Get("Content-Security-Policy") == "" {
		t.Fatalf("art response is missing its hardening headers: %v", resp.Header)
	}
	// Varied by credential, unlike the station logo: this row belongs to
	// one listener and answers 404 to everyone else, so a cache holding
	// two of them must not answer one from the other's copy.
	if got := resp.Header.Get("Vary"); got != artVary {
		t.Fatalf("art Vary = %q, want %q", got, artVary)
	}
	etag := resp.Header.Get("ETag")
	if etag == "" {
		t.Fatal("art response carries no ETag")
	}
	req, _ := http.NewRequest("GET", h.ts.URL+"/api/v1/radio/saved/"+saved.Pid+"/art", nil)
	req.Header.Set("Authorization", "Bearer "+h.token)
	req.Header.Set("If-None-Match", etag)
	rev, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	rev.Body.Close()
	if rev.StatusCode != 304 {
		t.Fatalf("revalidation status = %d, want 304", rev.StatusCode)
	}
	if got := rev.Header.Get("Vary"); got != artVary {
		t.Fatalf("304 Vary = %q, want %q", got, artVary)
	}

	// A row saved with nothing to copy is the ordinary case and answers
	// 404, which the client draws as a monogram.
	artless := decode[RadioSavedSong](t, mustSave(t, h, st.Pid, "Nobody - Nothing At All"))
	if artless.HasArt {
		t.Fatal("a song with no cover on any rung reports art")
	}
	resp = get(t, h.ts, "/api/v1/radio/saved/"+artless.Pid+"/art", h.token)
	resp.Body.Close()
	if resp.StatusCode != 404 {
		t.Fatalf("artless art status = %d, want 404", resp.StatusCode)
	}
}

func TestRadioSavedSongsAreOnePerAccount(t *testing.T) {
	h := newHarness(t)
	st := savedSongStation(t, h, "Deck FM")
	mine := decode[RadioSavedSong](t, mustSave(t, h, st.Pid, "Charlie Parker - Ornithology"))

	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "sam", "password": testPassword,
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create user status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	sam := loginAs(t, h.ts, "sam", testPassword)

	if theirs := decode[RadioSavedSongPage](t, get(t, h.ts, "/api/v1/radio/saved", sam.Token)); len(theirs.Songs) != 0 {
		t.Fatalf("sam sees %d of admin's saved songs", len(theirs.Songs))
	}
	// Saving the same song is their own row, not a conflict with mine.
	req, _ := http.NewRequest("POST", h.ts.URL+"/api/v1/radio/saved",
		strings.NewReader(`{"stationPid":"`+st.Pid+`","nowPlaying":"Charlie Parker - Ornithology"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+sam.Token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != 201 {
		t.Fatalf("sam's save status = %d, want 201", resp.StatusCode)
	}
	if theirs := decode[RadioSavedSong](t, resp); theirs.Pid == mine.Pid {
		t.Fatal("sam's save answered admin's row")
	}
	// And their id never names mine: the art read is scoped too.
	art := get(t, h.ts, "/api/v1/radio/saved/"+mine.Pid+"/art", sam.Token)
	art.Body.Close()
	if art.StatusCode != 404 {
		t.Fatalf("cross-account art status = %d, want 404", art.StatusCode)
	}
	req, _ = http.NewRequest("DELETE", h.ts.URL+"/api/v1/radio/saved/"+mine.Pid, nil)
	req.Header.Set("Authorization", "Bearer "+sam.Token)
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if page := decode[RadioSavedSongPage](t, get(t, h.ts, "/api/v1/radio/saved", h.token)); len(page.Songs) != 1 {
		t.Fatalf("after sam's delete admin holds %d songs, want 1", len(page.Songs))
	}
}

func TestRadioSavedSongsPageAndRefuseBadInput(t *testing.T) {
	h := newHarness(t)
	st := savedSongStation(t, h, "Deck FM")
	for _, line := range []string{"A - One", "B - Two", "C - Three"} {
		mustSave(t, h, st.Pid, line)
	}

	first := decode[RadioSavedSongPage](t, get(t, h.ts, "/api/v1/radio/saved?limit=2", h.token))
	if len(first.Songs) != 2 || first.NextCursor == nil {
		t.Fatalf("first page = (%d songs, cursor %v), want 2 and a cursor", len(first.Songs), first.NextCursor)
	}
	next := decode[RadioSavedSongPage](t, get(t, h.ts, "/api/v1/radio/saved?limit=2&cursor="+*first.NextCursor, h.token))
	if len(next.Songs) != 1 || next.NextCursor != nil {
		t.Fatalf("last page = (%d songs, cursor %v), want 1 and no cursor", len(next.Songs), next.NextCursor)
	}

	wantStatus(t, get(t, h.ts, "/api/v1/radio/saved?cursor=tr-01JZX5N8QW3F4V9T2B7KD3M9R6", h.token), 400, "bad cursor")
	// A limit outside the contract's range is refused rather than
	// carried into the page slice, where a negative one is a panic and
	// an enormous one is a per-row library search per request.
	wantStatus(t, get(t, h.ts, "/api/v1/radio/saved?limit=-1", h.token), 400, "a negative limit")
	wantStatus(t, get(t, h.ts, "/api/v1/radio/saved?limit=0", h.token), 400, "a zero limit")
	wantStatus(t, get(t, h.ts, "/api/v1/radio/saved?limit=100000", h.token), 400, "an unbounded limit")
	// A station nobody has is a not-found: the snapshot comes from one
	// that exists at save time.
	wantStatus(t, h.postJSON(t, "/api/v1/radio/saved", map[string]any{
		"stationPid": "rs-01JZX5N8QW3F4V9T2B7KD3M9R6", "nowPlaying": "Ghost - Station",
	}), 404, "unknown station")
	// An announcement past the contract's bound is refused rather than
	// stored: this is the one field relayed verbatim from an untrusted
	// host into durable storage.
	wantStatus(t, h.postJSON(t, "/api/v1/radio/saved", map[string]any{
		"stationPid": st.Pid, "nowPlaying": strings.Repeat("x", 401),
	}), 400, "an over-long announcement")
}

// waitForSavedSnapshotArt polls play-info until the detached announced
// fetch has landed, which is what gives the save something to copy. The
// poll is the production trigger too: nothing about a save starts a
// fetch, deliberately.
func waitForSavedSnapshotArt(t *testing.T, h *harness, stationPID string) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for {
		info := decode[RadioPlayInfo](t, get(t, h.ts, "/api/v1/radio/stations/"+stationPID+"/play-info", h.token))
		if info.NowPlayingArtKey != nil {
			return
		}
		if time.Now().After(deadline) {
			t.Fatal("the announced artwork fetch never landed")
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func mustSave(t *testing.T, h *harness, stationPID, line string) *http.Response {
	t.Helper()
	resp := h.postJSON(t, "/api/v1/radio/saved", map[string]any{
		"stationPid": stationPID, "nowPlaying": line,
	})
	if resp.StatusCode != 201 {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		t.Fatalf("save %q status = %d (%s)", line, resp.StatusCode, body)
	}
	return resp
}
