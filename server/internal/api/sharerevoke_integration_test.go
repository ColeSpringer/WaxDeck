package api

import (
	"context"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// slotsHeld is how many transfers hold key's place in a gate.
func slotsHeld(g *relayGate, key string) int {
	g.mu.Lock()
	defer g.mu.Unlock()
	return g.live[key]
}

// waitForSlots polls a gate until key holds want, failing after timeout.
func waitForSlots(t *testing.T, g *relayGate, key string, want int, timeout time.Duration, what string) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for {
		got := slotsHeld(g, key)
		if got == want {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("%s: %d slots still held after %v, want %d", what, got, timeout, want)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

// Revoking a link ends the transfers running on it at once, whatever each
// is waiting on: a visitor who has stopped reading a relayed episode or a
// download, and a relay waiting on a host gone quiet. The bounds that
// otherwise end those (a minute of a stalled write, half a minute of
// silence from the host) are not waited for, and the slots come back.
func TestRevokingALinkEndsTransfersThatAreWaiting(t *testing.T) {
	t.Parallel()
	const within = 3 * time.Second

	t.Run("a visitor who stopped reading a relayed episode", func(t *testing.T) {
		t.Parallel()
		h := newPodcastHarness(t)
		ep := episodesByTitle(t, h, newEndlessFeed(t, 1, 0).feedURL())["Episode 1"]
		share, other := shareOf(t, h, ep.Pid, nil), shareOf(t, h, ep.Pid, nil)
		owner := adminUserID(t, h)
		for range 2 {
			stalledVisitor(t, h.ts.URL, share.Url+"/stream?i=0")
		}
		stalledVisitor(t, h.ts.URL, other.Url+"/stream?i=0")
		waitForSlots(t, &h.srv.shareStreams, barePID(share.Pid), 2, within, "the visitors arriving")
		waitForSlots(t, &h.srv.shareStreams, barePID(other.Pid), 1, within, "another link's visitor arriving")

		wantStatus(t, h.deleteReq(t, "/api/v1/shares/"+share.Pid), 204, "revoking the link")
		waitForSlots(t, &h.srv.shareStreams, barePID(share.Pid), 0, within, "the link's slots after the revoke")
		waitForSlots(t, &h.srv.relayStreams, owner, 1, within, "the owner's relay slots after the revoke")
		if got := slotsHeld(&h.srv.shareStreams, barePID(other.Pid)); got != 1 {
			t.Errorf("another link holds %d slots after the revoke, want its visitor kept", got)
		}
	})

	t.Run("a visitor who stopped reading a download", func(t *testing.T) {
		t.Parallel()
		h := newHarnessDirect(t)
		base := tightServer(t, h)
		pid, _ := longTrack(t, h)
		share := shareOf(t, h, pid, map[string]any{"allowDownload": true})
		stalledVisitor(t, base, share.Url+"/download?i=0")
		waitForSlots(t, &h.srv.shareStreams, barePID(share.Pid), 1, within, "the visitor arriving")

		wantStatus(t, h.deleteReq(t, "/api/v1/shares/"+share.Pid), 204, "revoking the link")
		waitForSlots(t, &h.srv.shareStreams, barePID(share.Pid), 0, within, "the link's slots after the revoke")
	})

	t.Run("a relay waiting on a host gone quiet", func(t *testing.T) {
		t.Parallel()
		h := newPodcastHarness(t)
		feed := scriptedEpisodeHost(t, func(conn net.Conn, gone <-chan struct{}) {
			io.WriteString(conn, chunkedHead)
			writeChunk(conn, scriptedPart)
			<-gone
		})
		_, ep := firstEpisode(t, h, feed, nil)
		share := shareOf(t, h, ep.Pid, nil)
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		resp := openStream(t, ctx, h.ts.URL+share.Url+"/stream?i=0")
		defer resp.Body.Close()
		if _, err := io.ReadFull(resp.Body, make([]byte, scriptedPart)); err != nil {
			t.Fatalf("the stream did not start: %v", err)
		}
		ended := make(chan error, 1)
		go func() {
			_, err := io.Copy(io.Discard, resp.Body)
			ended <- err
		}()

		wantStatus(t, h.deleteReq(t, "/api/v1/shares/"+share.Pid), 204, "revoking the link")
		select {
		case err := <-ended:
			if err == nil {
				t.Error("the transfer ended as though the episode were whole")
			}
		case <-time.After(within):
			t.Fatalf("the relay was still waiting on its host %v after the link was revoked", within)
		}
		waitForSlots(t, &h.srv.shareStreams, barePID(share.Pid), 0, within, "the link's slots after the revoke")
	})
}

// A link that reaches its expiry ends the transfers running on it just as
// a revoke does, a paused visitor's included.
func TestAnExpiringLinkEndsTransfersThatAreWaiting(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	ep := episodesByTitle(t, h, newEndlessFeed(t, 1, 0).feedURL())["Episode 1"]
	owner, err := h.svc.UserCtxByID(context.Background(), adminUserID(t, h))
	if err != nil {
		t.Fatal(err)
	}
	info, err := h.svc.CreateShare(context.Background(), owner, ep.Pid, 4*time.Second, false, 0)
	if err != nil {
		t.Fatal(err)
	}
	link := "/s/" + h.srv.shares.Mint(barePID(info.ID))
	stalledVisitor(t, h.ts.URL, link+"/stream?i=0")
	waitForSlots(t, &h.srv.shareStreams, barePID(info.ID), 1, 2*time.Second, "the visitor arriving")

	waitForSlots(t, &h.srv.shareStreams, barePID(info.ID), 0, 6*time.Second, "the link's slots after it expired")
}

// shareAsNewUser makes a plain account and a link to pid as them, and
// answers the account's id with the link.
func shareAsNewUser(t *testing.T, h *harness, username, pid string, extra map[string]any) (accountID string, link Share) {
	t.Helper()
	account := decodeStatus[UserAccount](t, h.postJSON(t, "/api/v1/users", map[string]any{"username": username, "password": testPassword}), 201, "creating "+username)
	body := map[string]any{"pid": pid}
	for k, v := range extra {
		body[k] = v
	}
	resp := reqAs(t, h, "POST", "/api/v1/shares", loginAs(t, h.ts, username, testPassword).Token, body)
	return account.Id, decodeStatus[Share](t, resp, 201, "sharing as "+username)
}

// A link whose owner is disabled stops serving what is already running on
// it at the next link check, which is the one thing that reaches it: no
// revoke is sent and no registry hears of it. The stream or download is
// cut, not finished.
func TestDisablingTheOwnerEndsTheirLinksRunningTransfers(t *testing.T) {
	t.Parallel()
	const within = 5 * time.Second
	disable := func(t *testing.T, h *harness, accountID string) {
		t.Helper()
		wantStatus(t, h.patchJSON(t, "/api/v1/users/"+accountID, map[string]any{"disabled": true}), 200, "disabling the owner")
	}

	t.Run("a relayed episode", func(t *testing.T) {
		t.Parallel()
		h := newPodcastHarness(t)
		h.srv.streamRecheckEvery = 50 * time.Millisecond
		ep := episodesByTitle(t, h, newEndlessFeed(t, 1, 5*time.Millisecond).feedURL())["Episode 1"]
		owner, link := shareAsNewUser(t, h, "dana", ep.Pid, nil)
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		resp := openStream(t, ctx, h.ts.URL+link.Url+"/stream?i=0")
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("stream = %d", resp.StatusCode)
		}
		if _, err := io.ReadFull(resp.Body, make([]byte, 64<<10)); err != nil {
			t.Fatalf("the stream did not start: %v", err)
		}
		disable(t, h, owner)
		ended := make(chan error, 1)
		go func() {
			_, err := io.Copy(io.Discard, resp.Body)
			ended <- err
		}()
		select {
		case err := <-ended:
			if err == nil {
				t.Error("the stream ended as though the episode were whole")
			}
		case <-time.After(within):
			t.Fatalf("the stream was still running %v after its owner was disabled", within)
		}
	})

	for _, c := range []struct{ name, route string }{
		{"a stream of a file", "/stream?i=0"},
		{"a download", "/download?i=0"},
	} {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			h := newHarnessDirect(t)
			h.srv.streamRecheckEvery = 50 * time.Millisecond
			base := tightServer(t, h)
			pid, size := longTrack(t, h)
			owner, link := shareAsNewUser(t, h, "dana", pid, map[string]any{"allowDownload": true})
			// Running is answered: its head is in, so the owner is disabled
			// under a transfer that has started, not one still on its way.
			status, rest, err := pacedStart(base+link.Url+c.route, 256<<10, size+1)
			if err != nil || status != http.StatusOK {
				t.Fatalf("the transfer = %d, %v; want it started", status, err)
			}
			type result struct {
				got int64
				err error
			}
			done := make(chan result, 1)
			go func() {
				got, err := rest()
				done <- result{got, err}
			}()
			disable(t, h, owner)
			select {
			case r := <-done:
				if r.err == nil || r.got >= size {
					t.Errorf("after its owner was disabled the transfer got %d of %d bytes, %v; want it cut", r.got, size, r.err)
				}
			case <-time.After(within):
				t.Fatalf("the transfer was still running %v after its owner was disabled", within)
			}
		})
	}
}

// A transfer that starts on a link a revoke has already taken is ended as
// it registers: the revoke's pass over the running transfers found nothing
// of it to end, and the periodic link check is seconds away, so the
// transfer asks once itself.
func TestATransferStartedOnARevokedLinkIsEndedAtOnce(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	track := h.items(t, "?mediaType=music").Items[0]
	start := func(shareID string) (*stallBoundWriter, *http.Request) {
		t.Helper()
		bound, served, over := h.srv.beginShareTransfer(httptest.NewRecorder(),
			httptest.NewRequest(http.MethodGet, "/s/link/stream?i=0", nil), shareID, time.Time{})
		t.Cleanup(over)
		return bound, served
	}

	live := shareOf(t, h, track.Pid, nil)
	bound, served := start(barePID(live.Pid))
	if _, err := bound.Write([]byte("audio")); err != nil || served.Context().Err() != nil {
		t.Errorf("a transfer of a live link: write error %v, context %v; want neither", err, served.Context().Err())
	}

	revoked := shareOf(t, h, track.Pid, nil)
	wantStatus(t, h.deleteReq(t, "/api/v1/shares/"+revoked.Pid), 204, "revoking the link")
	bound, served = start(barePID(revoked.Pid))
	if _, err := bound.Write([]byte("audio")); err == nil {
		t.Error("a transfer started on a revoked link wrote its first bytes")
	}
	if served.Context().Err() == nil {
		t.Error("a transfer started on a revoked link is still reading on a live context")
	}
}

// A revoke addressed with the pid in lower case revokes the link and ends
// its running transfers all the same.
func TestRevokingALinkByALowerCasePidEndsItsTransfers(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	ep := episodesByTitle(t, h, newEndlessFeed(t, 1, 0).feedURL())["Episode 1"]
	share := shareOf(t, h, ep.Pid, nil)
	stalledVisitor(t, h.ts.URL, share.Url+"/stream?i=0")
	waitForSlots(t, &h.srv.shareStreams, barePID(share.Pid), 1, 3*time.Second, "the visitor arriving")

	wantStatus(t, h.deleteReq(t, "/api/v1/shares/sh-"+strings.ToLower(barePID(share.Pid))), 204, "revoking by a lower-case pid")
	if resp, _ := anon(t, h, http.MethodGet, share.Url, ""); resp.StatusCode != http.StatusNotFound {
		t.Fatalf("the page after the revoke = %d, want 404", resp.StatusCode)
	}
	waitForSlots(t, &h.srv.shareStreams, barePID(share.Pid), 0, 3*time.Second, "the link's slots after the revoke")
}
