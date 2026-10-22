package service

import (
	"context"
	"errors"
	"testing"

	"github.com/colespringer/waxbin/model"
)

// One rule decides whether an episode reaches a caller, so the listing
// row getSong answers and the detail read agree, a show that cannot be
// read included: refused for an account without explicit content, which
// cannot be shown the show's advisory, and answered for one with it.
func TestAnEpisodeRowAndItsDetailAgreeOnWhoSeesIt(t *testing.T) {
	t.Parallel()
	feed := &stubFeed{kind: model.SourceRSS, n: 1, prefix: "Allowed"}
	f := openStubFeeds(t, feed)
	sub := f.subscribe(t, "https://feeds.example/allowed", "rss")
	episode := showEpisodePIDs(t, f, sub.Show.PID)[0]
	perms := DefaultPermissions()
	perms.Explicit = false
	acct, err := f.svc.CreateAccount(f.ctx, AccountCreate{Username: "kid", Password: "correct-horse", Permissions: &perms})
	if err != nil {
		t.Fatal(err)
	}
	kid, err := f.svc.UserCtx(f.ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	f.svc.showReadHook = func(context.Context, model.PID) (*model.Podcast, error) {
		return nil, errors.New("database is locked")
	}
	for _, c := range []struct {
		name string
		uc   *UserCtx
		want ErrorKind
	}{
		{"an account without explicit content", kid, KindNotFound},
		{"an account with it", f.uc, ""},
	} {
		_, detailErr := f.svc.EpisodeDetailFor(f.ctx, c.uc, episode)
		_, _, rowErr := f.svc.EpisodeSummaryFor(f.ctx, c.uc, episode)
		if KindOf(detailErr) != c.want || KindOf(rowErr) != c.want {
			t.Errorf("%s, the show unreadable: detail %v, row %v; want both %q", c.name, detailErr, rowErr, c.want)
		}
	}
}
