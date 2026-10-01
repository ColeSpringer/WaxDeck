package service

import (
	"context"
	"errors"
	"log/slog"
	"strings"
	"testing"

	"github.com/colespringer/waxbin/waxerr"
)

// A catalog under a hand-off answers reads and writes alike as
// maintenance, and the catalog's read-only refusals as read-only.
func TestCatalogRefusalsClassifyByWhatTheyMean(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		name string
		err  error
		want ErrorKind
	}{
		{"a read of a suspended store", waxerr.Wrap(waxerr.CodeIO, "store.Libraries", errors.New("sql: database is closed")), KindMaintenance},
		{"a write to a suspended store", waxerr.New(waxerr.CodeUnsupported, "store.writeTx", "store is closed"), KindMaintenance},
		{"a restore into a read-only library", waxerr.New(waxerr.CodeLocked, "Library.RestoreTrash", "cannot restore trash entry x: library y is read-only"), KindReadOnly},
		{"a purge from a read-only library", waxerr.New(waxerr.CodeLocked, "Library.PurgeTrash", "trash entry x came from library y, which is read-only"), KindReadOnly},
		{"a locked field", waxerr.New(waxerr.CodeLocked, "store.EditFields", "field is locked (use force to override): title"), KindLocked},
		{"a missing integration", waxerr.New(waxerr.CodeUnsupported, "podcast", "no acquisition provider registered for source type youtube"), KindUnsupported},
	} {
		if got := KindOf(c.err); got != c.want {
			t.Errorf("%s: %q, want %q", c.name, got, c.want)
		}
	}
}

// A catalog read-only refusal reads like the server's own, without the
// catalog's op name and pids.
func TestAReadOnlyRefusalSaysSoPlainly(t *testing.T) {
	t.Parallel()
	err := classify(waxerr.New(waxerr.CodeLocked, "Library.RestoreTrash", "cannot restore trash entry x: library y is read-only"))
	if err.Error() != errReadOnly("this library").Error() {
		t.Errorf("message = %q, want the server's read-only sentence", err.Error())
	}
}

// The trash's empty notice counts the files a read-only library kept.
func TestTheTrashNoticeCountsWhatStayed(t *testing.T) {
	t.Parallel()
	body := trashBody(TrashEmptyDTO{SkippedReadOnly: 2})
	if !strings.Contains(body, "2 kept in read-only libraries") {
		t.Errorf("body = %q, want the kept count", body)
	}
	if strings.Contains(trashBody(TrashEmptyDTO{Purged: 1}), "read-only") {
		t.Error("a pass that kept nothing mentions read-only libraries")
	}
}

// A feed's failure reads as its own words, without the provider label
// the catalog wraps it in.
func TestAFeedFailureKeepsItsOwnWords(t *testing.T) {
	t.Parallel()
	l := &Library{log: slog.New(slog.DiscardHandler)}
	err := l.feedUnreachable(hostFailure(context.Background(), "service.fetchTranscript", errors.New("transcript host answered status 404")), "", false)
	if strings.Contains(err.Error(), "provider") || !strings.Contains(err.Error(), "status 404") {
		t.Errorf("message = %q, want the host's answer alone", err.Error())
	}
}
