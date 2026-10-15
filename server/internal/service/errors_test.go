package service

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"strings"
	"testing"

	"github.com/colespringer/waxbin/waxerr"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
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

// A catalog refusal reads in its own words, without the operation names
// WaxBin threads through it; an internal failure keeps no message, since
// its cause is for the log.
func TestClassifiedMessagesDropOperationNames(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		name string
		err  error
		want string
	}{
		{"one layer", waxerr.New(waxerr.CodeConflict, "jobs.Run", "another job holds scope fs-mutate"),
			"another job holds scope fs-mutate"},
		{"a wrapped refusal", waxerr.Wrap(waxerr.CodeInvalid, "store.EditItemFields",
			waxerr.New(waxerr.CodeInvalid, "editfield.parse", `year: "abc" is not a number`)),
			`year: "abc" is not a number`},
		{"a message over its cause", waxerr.Wrapf(waxerr.CodeConflict, "inbox.apply",
			waxerr.New(waxerr.CodeConflict, "inbox.move", "destination already exists"), "track %d", 3),
			"track 3: destination already exists"},
		{"a plain cause", waxerr.Wrap(waxerr.CodeNotFound, "store.Item", errors.New("no such row")),
			"no such row"},
	} {
		if got := classify(c.err).Error(); got != c.want {
			t.Errorf("%s: %q, want %q", c.name, got, c.want)
		}
	}
	if busy := classifyMutation(waxerr.New(waxerr.CodeConflict, "jobs.Run", "another job holds scope fs-mutate")); KindOf(busy) != KindCatalogBusy || strings.Contains(busy.Error(), "jobs.") {
		t.Errorf("lease contention = %v (%s), want catalog-busy without the op", busy, KindOf(busy))
	}
	var se *Error
	if !errors.As(classify(waxerr.New(waxerr.CodeIO, "store.Open", "disk on fire")), &se) || se.Msg != "" {
		t.Errorf("internal failure message = %q, want none", se.Msg)
	}
}

// A failed task is recorded in the failure's own words: no operation
// names and no permanence marker, its file's name kept. An administrator
// reads the server's paths in it; its owner reads them cut.
func TestATaskFailureReadsWithoutOperationNames(t *testing.T) {
	t.Parallel()
	l := &Library{stagingDir: "/srv/waxdeck/staging", roots: []Root{{Path: "/srv/music"}}}
	for _, c := range []struct {
		name          string
		err           error
		stored, owner string
	}{
		{"a sibling's prefix", errors.New("waxtap: extraction failed (YouTube may have changed)"),
			"extraction failed (YouTube may have changed)", "extraction failed (YouTube may have changed)"},
		{"a catalog refusal", fmt.Errorf("%w: %w", errToolPermanent,
			waxerr.New(waxerr.CodeConflict, "jobs.Run", "another job holds scope fs-mutate")),
			"another job holds scope fs-mutate", "another job holds scope fs-mutate"},
		{"a permanent failure", fmt.Errorf("%w: bad item pid %q", errToolPermanent, "x"),
			`bad item pid "x"`, `bad item pid "x"`},
		{"a path", errors.New("open /srv/waxdeck/staging/t1/a.flac: permission denied"),
			"open /srv/waxdeck/staging/t1/a.flac: permission denied", "open t1/a.flac: permission denied"},
		{"a file's own name", fmt.Errorf("%w: part1.mp3: not a recognized audio file", errToolPermanent),
			"part1.mp3: not a recognized audio file", "part1.mp3: not a recognized audio file"},
	} {
		stored := taskFailureText(c.err)
		if stored != c.stored {
			t.Errorf("%s: recorded %q, want %q", c.name, stored, c.stored)
		}
		task := wdb.ToolTask{Error: stored}
		if got := l.toolTaskFor(&UserCtx{Admin: true}, task).Error; got != c.stored {
			t.Errorf("%s: an administrator reads %q, want %q", c.name, got, c.stored)
		}
		if got := l.toolTaskFor(&UserCtx{}, task).Error; got != c.owner {
			t.Errorf("%s: its owner reads %q, want %q", c.name, got, c.owner)
		}
	}
}

// Storage paths are cut whole, whatever order the roots were made in: a
// root whose path begins another's does not leave that one's name half
// cut, and a bare root reads as the library only where the path ends.
func TestStoragePathsAreCutWhole(t *testing.T) {
	t.Parallel()
	l := &Library{stagingDir: "/srv/waxdeck/staging", roots: []Root{{Path: "/srv/media"}, {Path: "/srv/media-extra"}}}
	for in, want := range map[string]string{
		"open /srv/media-extra/Rock/a.flac: permission denied": "open Rock/a.flac: permission denied",
		"open /srv/media/Rock/a.flac: permission denied":       "open Rock/a.flac: permission denied",
		"stat /srv/media-extra: no such file or directory":     "stat the library: no such file or directory",
		"stat /srv/media: no such file or directory":           "stat the library: no such file or directory",
		"open /srv/mediafiles/x.flac: denied":                  "open /srv/mediafiles/x.flac: denied",
		"/srv/media and /srv/media.old, then /srv/media":       "the library and /srv/media.old, then the library",
		"stat /srv/mediaé: denied":                             "stat /srv/mediaé: denied",
	} {
		if got := l.scrubStoragePaths(in); got != want {
			t.Errorf("scrub(%q) = %q, want %q", in, got, want)
		}
	}
}

// Operation names go wherever they lead a part of the text, however many
// segments they have; a file's own name stays.
func TestOperationNamesGoFromEveryPartOfAFailure(t *testing.T) {
	t.Parallel()
	for in, want := range map[string]string{
		"meta.Writer.Apply: writing tags to Rock/a.flac: permission denied": "writing tags to Rock/a.flac: permission denied",
		"meta.CueSheet.Carve: the sheet names no tracks":                    "the sheet names no tracks",
		"two.mp3: unreadable: meta.Read: open up-1/two.mp3: no such file":   "two.mp3: unreadable: open up-1/two.mp3: no such file",
		"ap.flac: inbox.import: mkdir V24 Band: permission denied":          "ap.flac: mkdir V24 Band: permission denied",
		"jobs.Run: store.EditItemFields: database is locked":                "database is locked",
	} {
		if got := withoutOpNames(in); got != want {
			t.Errorf("withoutOpNames(%q) = %q, want %q", in, got, want)
		}
	}
}

// A part of a failure that names a file or a host says what failed, so
// it stays, however much it reads like an operation's name; a sibling's
// own operation still goes.
func TestAFailureKeepsTheFileOrHostItNames(t *testing.T) {
	t.Parallel()
	for in, want := range map[string]string{
		"album.cue: parse error at line 3":            "album.cue: parse error at line 3",
		"meta.Read: cover.jpg: unsupported":           "cover.jpg: unsupported",
		"enrich.coverart: example.com: 403 Forbidden": "example.com: 403 Forbidden",
		"waxtap.json: unexpected end of JSON input":   "unexpected end of JSON input",
	} {
		if got := withoutOpNames(in); got != want {
			t.Errorf("withoutOpNames(%q) = %q, want %q", in, got, want)
		}
	}
}

// A slash between words is not a path: a refusal quoting a value with
// one keeps it whole.
func TestASlashBetweenWordsIsNotAPath(t *testing.T) {
	t.Parallel()
	for in, want := range map[string]string{
		"A / B / C": "A / B / C",
		`an album named "Live / Unplugged" exists`:             `an album named "Live / Unplugged" exists`,
		"open /srv/music/My Album/a b.flac: permission denied": "open a b.flac: permission denied",
		"copy (/srv/x/y.flac) failed":                          "copy (y.flac) failed",
	} {
		if got := withoutDirectories(in); got != want {
			t.Errorf("withoutDirectories(%q) = %q, want %q", in, got, want)
		}
	}
}

// A kind change refused by a store under a hand-off answers maintenance,
// as every other write does then, not that the catalog is read-only.
func TestAKindChangeDuringAHandOffAnswersMaintenance(t *testing.T) {
	t.Parallel()
	l := &Library{log: slog.New(slog.DiscardHandler)}
	if got := l.kindRefusal(waxerr.New(waxerr.CodeUnsupported, "store.writeTx", "store is closed")); KindOf(got) != KindMaintenance {
		t.Fatalf("refusal = %v (%s), want maintenance", got, KindOf(got))
	}
}

// A catalog refusal reaches its caller in the catalog's words, its files
// named and the server's directories cut: whoever asked may not be the
// one who may read where the library keeps things.
func TestACatalogRefusalNamesFilesNotDirectories(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		err  error
		want string
	}{
		{waxerr.New(waxerr.CodeInvalid, "inbox.Plan", "not a recognized audio file: /srv/waxdeck/staging/up-1/odd.webm"),
			"not a recognized audio file: odd.webm"},
		{waxerr.Wrap(waxerr.CodeConflict, "meta.Read", &fs.PathError{Op: "open", Path: "/srv/music/My Album/a b.flac", Err: fs.ErrPermission}),
			"open a b.flac: permission denied"},
		{waxerr.New(waxerr.CodeNotFound, "store.Item", "no item tr-1"), "no item tr-1"},
	} {
		if got := classify(c.err).Error(); got != c.want {
			t.Errorf("refusal = %q, want %q", got, c.want)
		}
	}
}

// A failure naming a file in a library its reader is not granted says
// only that; one in a library they are reads in plain words.
func TestAFailureInAnUngrantedLibrarySaysOnlyThat(t *testing.T) {
	t.Parallel()
	l := &Library{roots: []Root{{Path: "/srv/granted", PID: "LA"}, {Path: "/srv/hidden", PID: "LB"}}}
	reader := &UserCtx{Libraries: map[string]bool{"LA": true}}
	hidden := "meta.Writer.Apply: writing tags to /srv/hidden/Secret/copy.mp3: permission denied"
	if got := l.failureWordsFor(reader, hidden); got != "it failed on a file in a library you are not granted" {
		t.Errorf("hidden failure reads %q", got)
	}
	own := "meta.Writer.Apply: writing tags to /srv/granted/Mine/own.mp3: permission denied"
	if got := l.failureWordsFor(reader, own); got != "writing tags to Mine/own.mp3: permission denied" {
		t.Errorf("own failure reads %q", got)
	}
	if got := l.failureWordsFor(&UserCtx{AllLibraries: true}, hidden); got != "writing tags to Secret/copy.mp3: permission denied" {
		t.Errorf("a reader of every library reads %q", got)
	}
}
