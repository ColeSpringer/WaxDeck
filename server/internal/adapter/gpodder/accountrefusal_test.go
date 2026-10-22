package gpodder

import (
	"bytes"
	"log/slog"
	"slices"
	"strings"
	"sync"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// lockedLog is a log destination the service may write from any goroutine.
type lockedLog struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (l *lockedLog) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.buf.Write(p)
}

func (l *lockedLog) String() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.buf.String()
}

// A device of an account that cannot see the podcast library is refused a
// show the catalog already holds, as it is any other: answered with no
// address to use, never parked, said once in the inbox however often the
// device asks, and logged without the feed.
func TestAnAccountWithoutPodcastsIsRefusedAKnownShow(t *testing.T) {
	var logged lockedLog
	e := newEnvWith(t, func(cfg *service.Config) {
		cfg.Logger = slog.New(slog.NewTextHandler(&logged, &slog.HandlerOptions{Level: slog.LevelDebug}))
	})
	// The catalog holds the show: alice followed it once, and let go.
	show := e.subscribeFirstParty(e.feedURL())
	if err := e.svc.Unsubscribe(e.ctx, e.uc, show, false); err != nil {
		t.Fatal(err)
	}
	libs, err := e.svc.Libraries(e.ctx)
	if err != nil {
		t.Fatal(err)
	}
	var music string
	for _, lib := range libs {
		if lib.Media != "podcast" {
			music = lib.PID
		}
	}
	granted := "granted"
	if _, err := e.svc.UpdateAccount(e.ctx, e.uc.ID, service.AccountUpdate{AccessMode: &granted, LibraryPIDs: []string{music}}); err != nil {
		t.Fatal(err)
	}

	for range 3 {
		ack := e.change("phone", []string{e.feedURL()}, nil)
		if !slices.Equal(ack.UpdateURLs, [][2]string{{e.feedURL(), ""}}) {
			t.Fatalf("update_urls = %v, want the known show refused", ack.UpdateURLs)
		}
	}
	e.wantList("after the refused adds")
	if d := e.changesSince("tablet", 0); len(d.Add) != 0 {
		t.Errorf("the tablet's delta = %+v, want nothing added", d)
	}
	if rows := e.failedAdds(); len(rows) != 1 || !strings.Contains(rows[0].Body, "This account cannot see the podcast library") ||
		strings.Contains(rows[0].Body, "127.0.0.1") {
		t.Errorf("inbox = %+v, want one row saying the account was refused, naming no feed", rows)
	}
	if out := logged.String(); strings.Contains(out, strings.TrimPrefix(e.feedURL(), "http://")) {
		t.Errorf("the log names the feed: %q", out)
	}
}
