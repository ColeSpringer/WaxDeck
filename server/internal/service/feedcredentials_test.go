package service

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/waxerr"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// A show a subscriber marked private is spent for its subscribers only,
// as one with stored credentials is: its feed's address can be its own
// token, so an unfetched episode is relayed to them and to no one else.
func TestAPrivateShowIsRelayedForItsSubscribersOnly(t *testing.T) {
	s := newLandingShow(t)
	if _, err := s.svc.PutSubscriptionSettings(s.ctx, s.admin, s.show, SubscriptionSettings{Private: true}); err != nil {
		t.Fatal(err)
	}
	acct, err := s.svc.CreateAccount(s.ctx, AccountCreate{Username: "visitor", Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.svc.EnclosureStreamSource(s.ctx, acct.User.ID, s.episodes["Episode 4"]); KindOf(err) != KindForbidden {
		t.Errorf("relaying a private show's episode to a non-subscriber = %v, want forbidden", err)
	}
	if _, err := s.svc.EnclosureStreamSource(s.ctx, s.admin.ID, s.episodes["Episode 4"]); err != nil {
		t.Errorf("relaying it to its subscriber = %v, want the source", err)
	}
}

// credentialedShow is a show subscribed with a login whose transcript
// host wants it, counting the asks.
type credentialedShow struct {
	ctx     context.Context
	svc     *Library
	admin   *UserCtx
	pod     *model.Podcast
	episode string // api pid
	asked   *atomic.Int64
}

func newCredentialedShow(t *testing.T) credentialedShow {
	t.Helper()
	return newTranscriptShow(t, true)
}

// newTranscriptShow is newCredentialedShow, or with login false a show
// whose host wants none, subscribed without one.
func newTranscriptShow(t *testing.T, login bool) credentialedShow {
	t.Helper()
	dir := t.TempDir()
	ctx, svc, admin, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
	})
	asked := &atomic.Int64{}
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if user, pass, ok := r.BasicAuth(); login && (!ok || user != "member" || pass != "s3cret") {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			if strings.HasSuffix(r.URL.Path, ".vtt") {
				asked.Add(1)
			}
			return
		}
		if strings.HasSuffix(r.URL.Path, ".vtt") {
			asked.Add(1)
			w.Header().Set("Content-Type", "text/vtt")
			fmt.Fprint(w, "WEBVTT\n\n00:00.000 --> 00:01.000\nMembers only\n")
			return
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0" xmlns:podcast="https://podcastindex.org/namespace/1.0">`+
			`<channel><title>Members Show</title><item><title>Members</title><guid>members-1</guid>`+
			`<pubDate>%s</pubDate><enclosure url="http://%s/ep.mp3" type="audio/mpeg" length="1"/>`+
			`<podcast:transcript url="http://%s/ep.vtt" type="text/vtt"/></item></channel></rss>`,
			time.Date(2026, 6, 1, 8, 0, 0, 0, time.UTC).Format(time.RFC1123Z), r.Host, r.Host)
	}))
	t.Cleanup(ts.Close)
	req := SubscribeRequest{URL: ts.URL + "/feed.xml"}
	if login {
		req.Username, req.Password = "member", "s3cret"
	}
	sub, _, err := svc.Subscribe(ctx, admin, req)
	if err != nil {
		t.Fatal(err)
	}
	eps, _, err := svc.Episodes(ctx, admin, sub.Show.PID, "", 10)
	if err != nil || len(eps) != 1 {
		t.Fatalf("episodes = %+v (%v), want one", eps, err)
	}
	pod, err := svc.getShow(ctx, sub.Show.PID)
	if err != nil {
		t.Fatal(err)
	}
	return credentialedShow{ctx: ctx, svc: svc, admin: admin, pod: pod, episode: eps[0].PID, asked: asked}
}

// A subscriber whose subscription could not be read is not told to
// subscribe: the store's failure is the server's.
func TestAFailedSubscriptionReadIsNotARefusal(t *testing.T) {
	c := newCredentialedShow(t)
	canceled, cancel := context.WithCancel(c.ctx)
	cancel()
	if _, _, err := c.svc.feedCredentials(canceled, c.admin.ID, c.pod); err == nil || KindOf(err) == KindForbidden {
		t.Errorf("credentials when the subscription could not be read = %v, want the server's failure", err)
	}
}

// A password that could not be read sends no login at all, and nothing a
// host says to the half of one is kept: the transcript read fails as the
// server's, asks the host nothing and remembers nothing. A password the
// store holds but cannot open (sealed under another key) is the server's
// failure too, never the caller's.
func TestAFailedSecretReadSendsNoHalfLogin(t *testing.T) {
	c := newCredentialedShow(t)
	for _, failure := range []error{
		waxerr.New(waxerr.CodeIO, "store.GetSecret", "disk I/O error"),
		waxerr.New(waxerr.CodeInvalid, "store.GetSecret", "opening secret sealed under key k1"),
	} {
		c.svc.secretReadHook = func(context.Context, string) (string, error) { return "", failure }
		if user, pass, err := c.svc.feedCredentials(c.ctx, c.admin.ID, c.pod); KindOf(err) != KindInternal || user != "" || pass != "" {
			t.Errorf("credentials when the password read failed (%v) = %q, %q, %v; want none and the server's failure", failure, user, pass, err)
		}
		if _, err := c.svc.Transcript(c.ctx, c.admin, c.episode); KindOf(err) != KindInternal {
			t.Errorf("a transcript read when the password read failed (%v) = %v, want the server's failure", failure, err)
		}
	}
	if n := c.asked.Load(); n != 0 {
		t.Errorf("the host was asked %d times with half a login", n)
	}
	_, bare, _ := parseAPIPID(c.episode)
	if _, err := c.svc.db.TranscriptCacheFor(c.ctx, string(bare)); !errors.Is(err, wdb.ErrNotFound) {
		t.Errorf("the transcript cache after the failed read = %v, want nothing kept", err)
	}

	// A login stored without its password is the user half alone, as the
	// download sends it.
	c.svc.secretReadHook = func(context.Context, string) (string, error) {
		return "", waxerr.New(waxerr.CodeNotFound, "store.GetSecret", "no such secret")
	}
	if user, pass, err := c.svc.feedCredentials(c.ctx, c.admin.ID, c.pod); err != nil || user != "member" || pass != "" {
		t.Errorf("credentials with no stored password = %q, %q, %v; want the user alone", user, pass, err)
	}
}

// A show private by a subscriber's mark alone needs no login, and its
// transcript is refused to anyone else in words that say what it is:
// private to its subscribers.
func TestAPrivateShowsTranscriptIsRefusedAsPrivate(t *testing.T) {
	c := newTranscriptShow(t, false)
	if _, err := c.svc.PutSubscriptionSettings(c.ctx, c.admin, apiPID(PrefixPodcast, c.pod.PID), SubscriptionSettings{Private: true}); err != nil {
		t.Fatal(err)
	}
	acct, err := c.svc.CreateAccount(c.ctx, AccountCreate{Username: "visitor", Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	visitor, err := c.svc.UserCtx(c.ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	_, err = c.svc.Transcript(c.ctx, visitor, c.episode)
	var se *Error
	if KindOf(err) != KindForbidden || !errors.As(err, &se) || !strings.Contains(se.Msg, "private to its subscribers") {
		t.Errorf("a non-subscriber's transcript of a private show = %v, want a refusal saying the show is private to its subscribers", err)
	}
	if _, err := c.svc.Transcript(c.ctx, c.admin, c.episode); err != nil {
		t.Errorf("the subscriber's transcript = %v", err)
	}
}
