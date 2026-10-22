package gpodder

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// premiumFeed serves one show under a podcast:guid at /premium whatever
// the query, the way a paid feed answers each listener's own tokenized
// address.
func premiumFeed(t *testing.T) string {
	t.Helper()
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/premium" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0" xmlns:podcast="https://podcastindex.org/namespace/1.0"><channel><title>Premium</title>
<podcast:guid>5a5d2f43-8c4e-5d1e-9b0a-6a8f0e4c2b71</podcast:guid>
<item><title>Bonus</title><guid>premium-1</guid><enclosure url="http://%s/bonus.mp3" type="audio/mpeg" length="1"/></item>
</channel></rss>`, r.Host)
	}))
	t.Cleanup(ts.Close)
	return ts.URL + "/premium"
}

// listener is another account on the server.
func (e *env) listener(name string) *service.UserCtx {
	e.t.Helper()
	acct, err := e.svc.CreateAccount(e.ctx, service.AccountCreate{Username: name, Password: "login-password-2"})
	if err != nil {
		e.t.Fatal(err)
	}
	uc, err := e.svc.UserCtx(e.ctx, acct.User)
	if err != nil {
		e.t.Fatal(err)
	}
	return uc
}

// Two accounts following one paid show through their own tokens are each
// told their own: the catalog keeps one URL for the show, the one added
// last, and no list, change, play action or export of one account carries
// the other's.
func TestEachAccountIsToldItsOwnURL(t *testing.T) {
	e := newEnv(t)
	premium := premiumFeed(t)
	mine, theirs := premium+"?auth=AAA", premium+"?auth=BBB"
	show := e.subscribeFirstParty(mine)
	if _, _, err := e.svc.Subscribe(e.ctx, e.listener("bob"), service.SubscribeRequest{URL: theirs}); err != nil {
		t.Fatal(err)
	}
	eps, _, err := e.svc.Episodes(e.ctx, e.uc, show, "", 1)
	if err != nil || len(eps) != 1 {
		t.Fatalf("episodes = %+v (%v)", eps, err)
	}
	if _, err := e.svc.Checkpoint(e.ctx, e.uc, eps[0].PID, 30_000, nil); err != nil {
		t.Fatal(err)
	}

	e.wantList("the account's list", mine)
	resp, raw := e.call("GET", "/subscriptions/alice.opml", "", true)
	mustStatus(t, resp, raw, 200)
	if strings.Contains(string(raw), "BBB") || !strings.Contains(string(raw), "auth=AAA") {
		t.Errorf("the OPML list = %s, want the account's own token alone", raw)
	}
	for _, a := range e.actions("since=0").Actions {
		if a.Podcast != mine {
			t.Errorf("a play action names %q, want the account's %q", a.Podcast, mine)
		}
	}
	export, err := e.svc.ExportOPML(e.ctx, e.uc)
	if err != nil || strings.Contains(string(export), "BBB") || !strings.Contains(string(export), "auth=AAA") {
		t.Errorf("the OPML export = %s (%v), want the account's own token alone", export, err)
	}
	if err := e.svc.Unsubscribe(e.ctx, e.uc, show, false); err != nil {
		t.Fatal(err)
	}
	if d := e.changesSince("tablet", 0); len(d.Add) != 0 || !slices.Equal(d.Remove, []string{mine}) {
		t.Errorf("the delta after leaving the show = %+v, want its removal under the account's %q", d, mine)
	}
}

// A device adding its own spelling of a show the apps follow holds that
// show without the catalog taking up its spelling or the device being
// told to rewrite it, and the account's removal of the show later reaches
// the device under the spelling it holds.
func TestADeviceKeepsItsOwnSpelling(t *testing.T) {
	e := newEnv(t)
	feed := e.feedURL()
	respelled := feed + "/"
	show := e.subscribeFirstParty(feed)
	ack := e.change("phone", []string{respelled}, nil)
	if len(ack.UpdateURLs) != 0 {
		t.Fatalf("update_urls = %v, want none for a spelling of a show the account follows", ack.UpdateURLs)
	}
	subs, _, err := e.svc.Subscriptions(e.ctx, e.uc, "", 10, false)
	if err != nil || len(subs) != 1 || subs[0].Show.FeedURL != feed {
		t.Fatalf("subscriptions = %+v (%v), want the catalog's spelling unchanged", subs, err)
	}
	if err := e.svc.Unsubscribe(e.ctx, e.uc, show, false); err != nil {
		t.Fatal(err)
	}
	if d := e.changesSince("phone", ack.Timestamp); !slices.Equal(d.Remove, []string{respelled}) {
		t.Errorf("the phone's delta = %+v, want the removal under its own %q", d, respelled)
	}
}

// The same feed in a change's add and remove is refused whatever
// whitespace tells the two apart, since the server acts on them trimmed.
func TestAnAddAndARemoveOfOneFeedAreRefusedHoweverSpaced(t *testing.T) {
	e := newEnv(t)
	feed := e.feedURL()
	e.subscribeFirstParty(feed)
	resp, raw := e.call("POST", "/api/2/subscriptions/alice/phone.json",
		fmt.Sprintf(`{"add":[%q],"remove":[%q]}`, " "+feed, feed), true)
	mustStatus(t, resp, raw, http.StatusBadRequest)
	e.wantList("after the refused change", feed)
}

// A device of an account that may no longer manage podcasts lets go of
// nothing by uploading a list without the shows it holds.
func TestARevokedAccountsListLetsGoOfNothing(t *testing.T) {
	e := newEnv(t)
	a := e.feedURLOf(1)
	e.put("phone", "json", fmt.Sprintf(`[%q]`, a))
	perms := service.DefaultPermissions()
	perms.ManagePodcasts = false
	if _, err := e.svc.UpdateAccount(e.ctx, e.uc.ID, service.AccountUpdate{Permissions: &perms}); err != nil {
		t.Fatal(err)
	}
	e.put("phone", "json", `[]`)
	e.wantList("after the revoked account's device listed nothing", a)
}
