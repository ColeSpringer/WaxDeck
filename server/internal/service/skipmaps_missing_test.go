package service

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// syncBuffer is a log sink the service's goroutines and the test share.
type syncBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *syncBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *syncBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

// An item whose analysis found no audio may keep a copy elsewhere, so the
// drain says which happened (a gone copy dropped, or a copy taking a gone
// file's place) rather than "already out of the present state".
func TestAMissingFileWithACopyIsReportedForWhatHappened(t *testing.T) {
	t.Parallel()
	logs := &syncBuffer{}
	ctx, svc, uc := newCatalogFixtureWith(t, catalogFixtureOptions{
		logs: logs,
		extra: func(t *testing.T, libDir string) {
			for _, dir := range []string{"a", "b", "c"} {
				if _, err := fixtures.Generate(filepath.Join(libDir, dir), fixtures.Spec{
					Name: "solo", Codec: fixtures.CodecFLAC, Duration: 4500 * time.Millisecond,
					Tags: map[string]string{"TITLE": "Solo", "ARTIST": "Copyist"},
				}); err != nil {
					t.Fatal(err)
				}
			}
		},
	})
	pid := itemPIDByTitle(t, ctx, svc, uc, "Solo")
	it, err := svc.getVisibleItem(ctx, uc, pid)
	if err != nil {
		t.Fatal(err)
	}
	primary := string(it.Path)
	var copies []string
	for _, dir := range []string{"a", "b", "c"} {
		p := filepath.Join(filepath.Dir(filepath.Dir(primary)), dir, "solo.flac")
		if p != primary {
			copies = append(copies, p)
		}
	}
	if len(copies) != 2 {
		t.Fatalf("primary %s is not one of the three copies", primary)
	}

	if err := os.Remove(copies[0]); err != nil {
		t.Fatal(err)
	}
	svc.markAudioMissing(ctx, string(it.PID)+"|")
	if !strings.Contains(logs.String(), "dropped the rows") {
		t.Errorf("a gone copy's drain logged no drop:\n%s", logs.String())
	}

	if err := os.Remove(primary); err != nil {
		t.Fatal(err)
	}
	svc.markAudioMissing(ctx, string(it.PID)+"|")
	if !strings.Contains(logs.String(), "took the place") {
		t.Errorf("a gone primary's drain logged no promotion:\n%s", logs.String())
	}
	if strings.Contains(logs.String(), "already out of the present state") {
		t.Errorf("an item that kept a copy was logged as out of the present state:\n%s", logs.String())
	}
}
