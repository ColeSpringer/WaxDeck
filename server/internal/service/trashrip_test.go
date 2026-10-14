package service

import (
	"errors"
	"slices"
	"strings"
	"testing"
)

// A cue rip's file goes whole or not at all: a delete naming one track is
// refused in WaxDeck's words, dry run included, and one naming every
// track reports each while counting the file once.
func TestACueRipIsDeletedWholeOrNotAtAll(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCueFixture(t)
	one, two, _ := carvedTracks(t, ctx, svc, uc)

	for _, dryRun := range []bool{true, false} {
		_, err := svc.DeleteItems(ctx, uc, []string{one}, "trash", dryRun)
		if KindOf(err) != KindInvalid || !errors.Is(err, ErrCueRipPart) {
			t.Fatalf("deleting one track of a rip (dry run %v) = %v, want the cue-rip refusal", dryRun, err)
		}
		if msg := err.Error(); strings.Contains(msg, "/") || strings.Contains(msg, strings.TrimPrefix(one, "tr-")) {
			t.Errorf("the refusal carries a path or a bare pid: %q", msg)
		}
	}

	res, err := svc.DeleteItems(ctx, uc, []string{one, two}, "trash", true)
	if err != nil {
		t.Fatal(err)
	}
	var pids []string
	files := 0
	for _, e := range res.Entries {
		pids = append(pids, e.PID)
		files += e.Files
	}
	slices.Sort(pids)
	want := []string{one, two}
	slices.Sort(want)
	if !slices.Equal(pids, want) || files != 1 {
		t.Fatalf("whole-rip plan names %v over %d files, want %v over the one file", pids, files, want)
	}
}
