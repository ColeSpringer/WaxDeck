package service

import (
	"context"
	"errors"
	"testing"

	"github.com/colespringer/waxbin/model"
)

// One rule decides whether a show is private, for showIsPrivate (a feed's
// credentials, the address shown to someone who does not follow the show,
// gpodder, a link to one episode) and for the filter a playlist link
// applies to its members: a show with credentials, one a subscriber
// flagged private, and one whose flag cannot be read are private, an open
// one is not. A condition added to the rule has to reach both.
func TestShowPrivacyIsOneRule(t *testing.T) {
	t.Parallel()
	f := openStubFeeds(t, &stubFeed{kind: model.SourceRSS, n: 1, prefix: "Episode"})
	shows := map[string]struct {
		sub  Subscription
		want bool
	}{}
	for _, name := range []string{"open", "flagged", "paid", "hush"} {
		shows[name] = struct {
			sub  Subscription
			want bool
		}{f.subscribe(t, "https://feeds.example/"+name, "rss"), name == "flagged" || name == "paid"}
	}
	pidOf := func(name string) model.PID {
		_, pid, _ := parseAPIPID(shows[name].sub.Show.PID)
		return pid
	}
	f.svc.markShowPrivate(f.ctx, string(pidOf("flagged")))
	if err := f.svc.lib.Podcasts().SetAuth(f.ctx, pidOf("paid"), "member", "secret"); err != nil {
		t.Fatal(err)
	}

	private := f.svc.privateEpisodes()
	for name, c := range shows {
		pod, err := f.svc.lib.Podcasts().Get(f.ctx, pidOf(name))
		if err != nil {
			t.Fatal(err)
		}
		byRule := f.svc.showIsPrivate(f.ctx, pod)
		byFilter := private(f.ctx, &model.ItemView{Kind: model.KindEpisode, PodcastPID: pod.PID})
		if byRule != byFilter {
			t.Errorf("%s: showIsPrivate says %v and the playlist filter %v", name, byRule, byFilter)
		}
		if byRule != c.want || byFilter != c.want {
			t.Errorf("%s: showIsPrivate = %v and the playlist filter = %v, want %v", name, byRule, byFilter, c.want)
		}
	}

	// A flag that cannot be read counts as set, on both surfaces: the show
	// itself reads, the cancelled context fails the read of its flag.
	open, err := f.svc.lib.Podcasts().Get(f.ctx, pidOf("open"))
	if err != nil {
		t.Fatal(err)
	}
	f.svc.showReadHook = func(context.Context, model.PID) (*model.Podcast, error) { return open, nil }
	gone, cancel := context.WithCancel(f.ctx)
	cancel()
	if !f.svc.showIsPrivate(gone, open) {
		t.Error("showIsPrivate called an open show with an unreadable flag public")
	}
	if !f.svc.privateEpisodes()(gone, &model.ItemView{Kind: model.KindEpisode, PodcastPID: open.PID}) {
		t.Error("the playlist filter called an open show with an unreadable flag public")
	}
}

// The rule itself, over what it is given: the show, its flag, and whether
// the flag could be read.
func TestPrivateShowRule(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		name    string
		authed  bool
		mark    string
		markErr error
		want    bool
	}{
		{"open", false, "", nil, false},
		{"flagged", false, "1", nil, true},
		{"credentialed", true, "", nil, true},
		{"flag unreadable", false, "", errors.New("busy"), true},
		{"credentialed and flagged", true, "1", nil, true},
	} {
		pod := &model.Podcast{}
		if c.authed {
			pod.AuthUser = "member"
		}
		if got := privateShow(pod, c.mark, c.markErr); got != c.want {
			t.Errorf("%s: %v, want %v", c.name, got, c.want)
		}
	}
}
