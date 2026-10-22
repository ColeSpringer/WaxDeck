package api

import (
	"context"
	"net/http"
	"sync/atomic"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// dormantShow is a show the administrator and one more account follow,
// its first two episodes fetched, with a destination of the account's own
// for new episodes and disabled feeds, and a feed that can be made to fail.
type dormantShow struct {
	h              *harness
	feed           *feedServer
	failing        *atomic.Bool
	show           string
	formerID       string
	former         string
	music, podcast string
	sink           *notifySink
}

func newDormantShow(t *testing.T) dormantShow {
	t.Helper()
	h := newPodcastHarnessWith(t, func(cfg *service.Config) { cfg.AllowPrivateNotifyHosts = true })
	failing := &atomic.Bool{}
	d := dormantShow{h: h, feed: newFeedServer(t, 4), failing: failing, sink: newNotifySink(t, 200)}
	serve := d.feed.ts.Config.Handler
	d.feed.ts.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if failing.Load() {
			http.Error(w, "gone", http.StatusNotFound)
			return
		}
		serve.ServeHTTP(w, r)
	})
	d.feed.writeFeed(t, 2)
	d.show = decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": d.feed.feedURL()}), 201, "subscribe").Show.Pid
	for _, ep := range decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+d.show+"/episodes", h.token)).Items {
		fetchUnasked(t, h, ep.Pid)
	}
	for _, lib := range decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries {
		if deref(lib.Media) == "podcast" {
			d.podcast = lib.Pid
		} else {
			d.music = lib.Pid
		}
	}
	acct := decodeStatus[UserAccount](t, h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "former", "password": testPassword,
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{d.music, d.podcast}},
	}), 201, "creating former")
	d.formerID, d.former = acct.Id, loginAs(t, h.ts, "former", testPassword).Token
	wantStatus(t, reqAs(t, h, http.MethodPost, "/api/v1/podcasts", d.former, map[string]any{"url": d.feed.feedURL()}), 201, "former subscribes")
	createTarget(t, h, "/api/v1/users/me/notification-targets", d.former, map[string]any{
		"kind": "webhook", "config": map[string]any{"url": d.sink.ts.URL},
		"enabledEvents": []string{"episode-arrived", "feed-disabled"},
	})
	return d
}

func (d dormantShow) grant(t *testing.T, libs ...string) {
	t.Helper()
	wantStatus(t, d.h.patchJSON(t, "/api/v1/users/"+d.formerID, map[string]any{
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": libs},
	}), 200, "setting the grant")
}

func (d dormantShow) settings(t *testing.T, token string, body map[string]any) {
	t.Helper()
	wantStatus(t, reqAs(t, d.h, http.MethodPut, "/api/v1/podcasts/"+d.show+"/settings", token, body), 200, "settings")
}

// downloaded names the show's episodes held on the server.
func (d dormantShow) downloaded(t *testing.T) map[string]bool {
	t.Helper()
	out := map[string]bool{}
	for _, ep := range decode[EpisodePage](t, get(t, d.h.ts, "/api/v1/podcasts/"+d.show+"/episodes", d.h.token)).Items {
		if ep.Downloaded {
			out[ep.Title] = true
		}
	}
	return out
}

// publish has the feed list its first n episodes and runs a refresh, the
// downloads it queued, the deliveries it filed and the retention sweep.
func (d dormantShow) publish(t *testing.T, n int) {
	t.Helper()
	ctx := context.Background()
	d.feed.writeFeed(t, n)
	d.h.svc.RefreshDueFeeds(ctx, 0)
	drainFetches(t, d.h)
	drainNotify(t, d.h)
	d.h.svc.SweepRetention(ctx)
}

// The rows of an account that cannot see the podcast library are kept for
// the grant's return and do nothing meanwhile: a sync tells it of no new
// episode, in its inbox or at its own destinations, downloads nothing by
// its policy, and its retention has no say. Regranting restores all three.
func TestANarrowedAccountsSubscriptionIsDormant(t *testing.T) {
	t.Parallel()
	d := newDormantShow(t)
	d.settings(t, d.h.token, map[string]any{"retentionKeep": 1})
	d.settings(t, d.former, map[string]any{"autoDownload": true, "retentionKeep": 0})
	d.h.svc.SweepRetention(context.Background())
	if got := d.downloaded(t); len(got) != 2 {
		t.Fatalf("downloads while the account keeps everything = %v, want both", got)
	}

	d.grant(t, d.music)
	d.publish(t, 3)
	if rows := inboxRows(t, d.h, d.former, "episode-arrived"); len(rows) != 0 {
		t.Errorf("the narrowed account's inbox = %+v, want no arrival", rows)
	}
	if got := d.sink.deliveries(); len(got) != 0 {
		t.Errorf("the narrowed account's destination got %v, want nothing", got)
	}
	if got := d.downloaded(t); len(got) != 1 || !got["Episode 2"] {
		t.Errorf("downloads after a sync while narrowed = %v, want Episode 2 alone: no fetch by the account's policy, and the administrator's keep-one", got)
	}

	d.grant(t, d.music, d.podcast)
	d.publish(t, 4)
	if rows := inboxRows(t, d.h, d.former, "episode-arrived"); len(rows) != 1 {
		t.Errorf("the regranted account's inbox = %+v, want the new arrival", rows)
	}
	if got := d.sink.deliveries(); len(got) != 1 || got[0]["event"] != "episode-arrived" {
		t.Errorf("the regranted account's destination got %v, want the new arrival", got)
	}
	if got := d.downloaded(t); len(got) != 2 || !got["Episode 4"] || !got["Episode 2"] {
		t.Errorf("downloads after a sync once regranted = %v, want Episode 4 fetched by its policy and Episode 2 kept by its vote", got)
	}
}

// A feed disabled after its failures tells only the followers who can
// see the podcast library.
func TestADisabledFeedTellsNoNarrowedAccount(t *testing.T) {
	t.Parallel()
	d := newDormantShow(t)
	d.grant(t, d.music)
	d.failing.Store(true)
	ctx := context.Background()
	for range 10 {
		d.h.svc.RefreshDueFeeds(ctx, 0)
	}
	drainNotify(t, d.h)
	if rows := inboxRows(t, d.h, d.h.token, "feed-disabled"); len(rows) != 1 {
		t.Fatalf("the administrator's inbox = %+v, want the feed disabled", rows)
	}
	if rows := inboxRows(t, d.h, d.former, "feed-disabled"); len(rows) != 0 {
		t.Errorf("the narrowed account's inbox = %+v, want nothing", rows)
	}
	if got := d.sink.deliveries(); len(got) != 0 {
		t.Errorf("the narrowed account's destination got %v, want nothing", got)
	}
}
