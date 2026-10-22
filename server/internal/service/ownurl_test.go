package service

import (
	"context"
	"encoding/xml"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"path/filepath"
	"strings"
	"testing"
)

// openOwnURLFixture is a service with podcasts on, its admin, two more
// accounts that see podcasts, and a host serving one show under a
// podcast:guid at any address.
func openOwnURLFixture(t *testing.T) (context.Context, *Library, *UserCtx, *UserCtx, *UserCtx, *guidShowHost) {
	t.Helper()
	dir := t.TempDir()
	ctx, svc, admin, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
	})
	account := func(name string) *UserCtx {
		t.Helper()
		acct, err := svc.CreateAccount(ctx, AccountCreate{Username: name, Password: "correct-horse"})
		if err != nil {
			t.Fatal(err)
		}
		uc, err := svc.UserCtx(ctx, acct.User)
		if err != nil {
			t.Fatal(err)
		}
		return uc
	}
	return ctx, svc, admin, account("bob"), account("carol"), newGuidShowHost(t)
}

// exportedURLs are the feed addresses an OPML export names.
func exportedURLs(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) []string {
	t.Helper()
	doc, err := svc.ExportOPML(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	var out []string
	dec := xml.NewDecoder(strings.NewReader(string(doc)))
	for {
		tok, err := dec.Token()
		if err != nil {
			return out
		}
		if el, ok := tok.(xml.StartElement); ok {
			for _, a := range el.Attr {
				if a.Name.Local == "xmlUrl" {
					out = append(out, a.Value)
				}
			}
		}
	}
}

// followerViews are the addresses each view of the show gives uc: its
// detail, its row in the subscription list, the show in a fresh catalog
// mirror and the subscription the server stream hydrates.
func followerViews(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, show string) map[string]string {
	t.Helper()
	out := map[string]string{}
	detail, err := svc.PodcastDetailFor(ctx, uc, show)
	if err != nil {
		t.Fatal(err)
	}
	out["the show detail"] = detail.Show.FeedURL
	subs, _, err := svc.Subscriptions(ctx, uc, "", 50, false)
	if err != nil {
		t.Fatal(err)
	}
	for _, s := range subs {
		if s.Show.PID == show {
			out["the subscription list"] = s.Show.FeedURL
		}
	}
	page, err := svc.SyncCatalogSnapshot(ctx, uc, "", 500)
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range page.Entries {
		if e.Show != nil && e.Show.PID == show {
			out["the catalog mirror"] = e.Show.FeedURL
		}
	}
	stream, err := svc.SyncServerDelta(ctx, uc, encodeServerCursor(svc.serverGen, 0), 500)
	if err != nil {
		t.Fatal(err)
	}
	for _, ev := range stream.Events {
		if ev.Subscription != nil && ev.Subscription.Show.PID == show {
			out["the server stream"] = ev.Subscription.Show.FeedURL
		}
	}
	return out
}

// Each follower is shown the address it subscribed a show by, whatever
// spelling the catalog took up from the last adder, and is handed it in
// its export; someone who does not follow the show is shown the
// catalog's.
func TestAFollowerIsShownItsOwnAddress(t *testing.T) {
	ctx, svc, admin, bob, carol, host := openOwnURLFixture(t)
	mine, theirs := host.URL+"/mine.xml", host.URL+"/theirs.xml"
	sub, _, err := svc.Subscribe(ctx, admin, SubscribeRequest{URL: mine})
	if err != nil {
		t.Fatal(err)
	}
	since := ""
	for cursor := ""; ; {
		page, err := svc.SyncCatalogSnapshot(ctx, admin, cursor, 500)
		if err != nil {
			t.Fatal(err)
		}
		since = page.NextSince
		if cursor = page.NextCursor; cursor == "" {
			break
		}
	}
	if _, _, err := svc.Subscribe(ctx, bob, SubscribeRequest{URL: theirs}); err != nil {
		t.Fatal(err)
	}
	_, bare, _ := parseAPIPID(sub.Show.PID)
	if got := catalogURL(t, ctx, svc, string(bare)); got != theirs {
		t.Fatalf("the catalog holds the show as %s, want the last adder's %s", got, theirs)
	}

	views := followerViews(t, ctx, svc, admin, sub.Show.PID)
	delta, err := svc.SyncCatalogDelta(ctx, admin, since, 500)
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range delta.Entries {
		if e.Show != nil && e.Show.PID == sub.Show.PID {
			views["the catalog delta"] = e.Show.FeedURL
		}
	}
	for _, what := range []string{"the show detail", "the subscription list", "the catalog mirror", "the catalog delta", "the server stream"} {
		if got, ok := views[what]; !ok || got != mine {
			t.Errorf("%s gives the follower %q (present %v), want its own %s", what, got, ok, mine)
		}
	}
	if got := exportedURLs(t, ctx, svc, admin); len(got) != 1 || got[0] != mine {
		t.Errorf("the export names %v, want the follower's own %s", got, mine)
	}
	if got := followerViews(t, ctx, svc, bob, sub.Show.PID)["the show detail"]; got != theirs {
		t.Errorf("the other follower is shown %q, want its own %s", got, theirs)
	}
	detail, err := svc.PodcastDetailFor(ctx, carol, sub.Show.PID)
	if err != nil {
		t.Fatal(err)
	}
	if detail.Show.FeedURL != theirs {
		t.Errorf("someone who does not follow the show is shown %q, want the catalog's %s", detail.Show.FeedURL, theirs)
	}
}

// A private show is shown to each follower, and exported, by that
// follower's own address and never by another's, with no login written;
// someone who does not follow it is shown no address.
func TestAPrivateShowIsGivenToItsFollowersByTheirOwnAddress(t *testing.T) {
	ctx, svc, admin, bob, carol, host := openOwnURLFixture(t)
	mine, theirs := host.URL+"/mine.xml", host.URL+"/theirs.xml"
	sub, _, err := svc.Subscribe(ctx, admin, SubscribeRequest{URL: mine})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.PutSubscriptionSettings(ctx, admin, sub.Show.PID, SubscriptionSettings{Private: true}); err != nil {
		t.Fatal(err)
	}
	if _, _, err := svc.Subscribe(ctx, bob, SubscribeRequest{URL: theirs}); err != nil {
		t.Fatal(err)
	}
	for _, f := range []struct {
		who  string
		uc   *UserCtx
		want string
	}{{"its first follower", admin, mine}, {"its other follower", bob, theirs}} {
		views := followerViews(t, ctx, svc, f.uc, sub.Show.PID)
		for _, what := range []string{"the show detail", "the subscription list", "the catalog mirror", "the server stream"} {
			if got, ok := views[what]; !ok || got != f.want {
				t.Errorf("%s gives %s %q (present %v), want its own %s", what, f.who, got, ok, f.want)
			}
		}
		if got := exportedURLs(t, ctx, svc, f.uc); len(got) != 1 || got[0] != f.want {
			t.Errorf("%s's export names %v, want its own %s", f.who, got, f.want)
		}
	}
	detail, err := svc.PodcastDetailFor(ctx, carol, sub.Show.PID)
	if err != nil {
		t.Fatal(err)
	}
	if detail.Show.FeedURL != "" {
		t.Errorf("someone who does not follow the private show is shown %q, want no address", detail.Show.FeedURL)
	}
}

// A show subscribed with a login is exported under the follower's address
// alone: the login stays sealed on the server.
func TestACredentialedShowIsExportedWithoutItsLogin(t *testing.T) {
	c := newCredentialedShow(t)
	doc, err := c.svc.ExportOPML(c.ctx, c.admin)
	if err != nil {
		t.Fatal(err)
	}
	got := exportedURLs(t, c.ctx, c.svc, c.admin)
	if len(got) != 1 || got[0] != c.pod.FeedURL {
		t.Errorf("the export names %v, want the follower's own %s", got, c.pod.FeedURL)
	}
	for _, secret := range []string{"member", "s3cret"} {
		if strings.Contains(string(doc), secret) {
			t.Errorf("the export carries %q: %s", secret, doc)
		}
	}
}

// A subscribe by an address that carries a credential, as user info or in
// a query parameter named like one, makes the show private as a login
// does: someone who does not follow it is shown no address. Any other
// address leaves the show as it was.
func TestASubscribeByAnAddressCarryingASecretMakesTheShowPrivate(t *testing.T) {
	ctx, svc, admin, _, carol, _ := openOwnURLFixture(t)
	host := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0"><channel><title>Show %s</title>
<item><title>One</title><guid>%s-1</guid><enclosure url="http://%s/one.mp3" type="audio/mpeg" length="1"/></item>
</channel></rss>`, r.URL.Path, r.URL.Path, r.Host)
	}))
	t.Cleanup(host.Close)
	u, _ := url.Parse(host.URL)
	for i, tc := range []struct {
		address string
		private bool
	}{
		{"http://member:s3cret@" + u.Host + "/%d.xml", true},
		{host.URL + "/%d.xml?token=abc", true},
		{host.URL + "/%d.xml?Auth=abc", true},
		{host.URL + "/%d.xml?a=1&API_KEY=abc", true},
		{host.URL + "/%d.xml?a=1;sig=abc", true},
		{host.URL + "/%d.xml?access%%5Ftoken=abc", true},
		{host.URL + "/%d.xml", false},
		{host.URL + "/%d.xml?utm_source=abc", false},
		{host.URL + "/%d.xml?monkey=1&keys=2&tokens=3", false},
		{host.URL + "/%d.xml#token=abc", false},
	} {
		address := fmt.Sprintf(tc.address, i)
		sub, _, err := svc.Subscribe(ctx, admin, SubscribeRequest{URL: address})
		if err != nil {
			t.Fatalf("subscribing by %s: %v", address, err)
		}
		pod, err := svc.getShow(ctx, sub.Show.PID)
		if err != nil {
			t.Fatal(err)
		}
		if got := svc.showIsPrivate(ctx, pod); got != tc.private {
			t.Errorf("subscribed by %s, the show is private = %v, want %v", address, got, tc.private)
		}
		if sub.Settings.Private != tc.private {
			t.Errorf("subscribed by %s, the subscription is private = %v, want %v", address, sub.Settings.Private, tc.private)
		}
		detail, err := svc.PodcastDetailFor(ctx, carol, sub.Show.PID)
		if err != nil {
			t.Fatal(err)
		}
		if shown := detail.Show.FeedURL != ""; shown == tc.private {
			t.Errorf("subscribed by %s, someone who does not follow it is shown %q", address, detail.Show.FeedURL)
		}
	}
}

// A subscribe by an address that carries a secret makes the show private
// even when the subscribe is then refused: the catalog took the address up
// as the show's before the refusal, so no one who does not follow the show
// is shown it.
func TestARefusedSubscribeLeavesNoSecretAddressPublic(t *testing.T) {
	dir := t.TempDir()
	ctx, svc, admin, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
	})
	host := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:podcast="https://podcastindex.org/namespace/1.0"><channel><title>Explicit Show</title><itunes:explicit>true</itunes:explicit>
<podcast:guid>5c1f8f8e-7c0b-5a8e-9d7f-2b8f0c3e4a99</podcast:guid>
<item><title>One</title><guid>x-1</guid><enclosure url="http://%s/one.mp3" type="audio/mpeg" length="1"/></item>
</channel></rss>`, r.Host)
	}))
	t.Cleanup(host.Close)
	sub, _, err := svc.Subscribe(ctx, admin, SubscribeRequest{URL: host.URL + "/feed.xml"})
	if err != nil {
		t.Fatal(err)
	}
	account := func(name string, explicit bool) *UserCtx {
		t.Helper()
		perms := DefaultPermissions()
		perms.Explicit = explicit
		acct, err := svc.CreateAccount(ctx, AccountCreate{Username: name, Password: "correct-horse", Permissions: &perms})
		if err != nil {
			t.Fatal(err)
		}
		uc, err := svc.UserCtx(ctx, acct.User)
		if err != nil {
			t.Fatal(err)
		}
		return uc
	}
	kid, carol := account("kid", false), account("carol", true)
	secret := host.URL + "/feed.xml?token=kidsecret"
	if _, _, err := svc.Subscribe(ctx, kid, SubscribeRequest{URL: secret}); KindOf(err) != KindForbidden {
		t.Fatalf("the kid's subscribe = %v, want the explicit show refused", err)
	}
	detail, err := svc.PodcastDetailFor(ctx, carol, sub.Show.PID)
	if err != nil {
		t.Fatal(err)
	}
	if detail.Show.FeedURL != "" {
		t.Errorf("someone who does not follow the show is shown %q after a refused subscribe by a secret address, want no address", detail.Show.FeedURL)
	}
}
