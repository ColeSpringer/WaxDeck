package sourcetags

import (
	"bytes"
	"context"
	"errors"
	"os"
	"slices"
	"testing"
	"time"

	waxlabel "github.com/colespringer/waxlabel"
	"github.com/colespringer/waxlabel/tag"

	"github.com/colespringer/waxdeck/fixtures"
)

// Restamp reads the uploader and title out of the file it is handed, so a
// source with nothing beside its file still delivers the clean tags.
func TestRestampCleansTheFilesOwnTags(t *testing.T) {
	t.Parallel()
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{Codec: fixtures.CodecMP3, Duration: 200 * time.Millisecond,
		Tags: map[string]string{"TITLE": "Song (Official Video)", "ARTIST": "Juvenile - Topic"}})
	if err != nil {
		t.Fatal(err)
	}
	in, err := os.Open(paths[0])
	if err != nil {
		t.Fatal(err)
	}
	defer in.Close()
	var out bytes.Buffer
	n, err := Restamp(context.Background(), t.TempDir(), ".mp3", in, &out, Source{URL: "https://example.invalid/v/1", ID: "1", Music: true})
	if err != nil {
		t.Fatalf("Restamp: %v", err)
	}
	if n != int64(out.Len()) {
		t.Errorf("n = %d, wrote %d", n, out.Len())
	}
	doc, err := waxlabel.Parse(context.Background(), waxlabel.BytesSource(out.Bytes()))
	if err != nil {
		t.Fatal(err)
	}
	for k, want := range map[tag.Key][]string{
		tag.Artist:    {"Juvenile"},
		tag.Title:     {"Song"},
		tag.SourceURL: {"https://example.invalid/v/1"},
		tag.SourceID:  {"1"},
	} {
		if got, _ := doc.Get(k); !slices.Equal(got, want) {
			t.Errorf("%s = %q, want %q", k, got, want)
		}
	}
}

// The committed-with-error quadrant is driven by a post-commit fsync, which
// no integration test can provoke, so this table is the only pin the
// decision gets.
func TestWriteLanded(t *testing.T) {
	t.Parallel()
	postCommit := errors.New("syncing directory: input/output error")
	for _, tc := range []struct {
		name string
		res  waxlabel.SaveResult
		err  error
		want bool
	}{
		{"the bytes landed", waxlabel.SaveResult{Committed: true}, nil, true},
		{"a no-op plan wrote nothing by contract", waxlabel.SaveResult{}, nil, true},
		{"the write landed and a step after it failed", waxlabel.SaveResult{Committed: true}, postCommit, true},
		{"nothing was written", waxlabel.SaveResult{}, postCommit, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := writeLanded(tc.res, tc.err); got != tc.want {
				t.Errorf("writeLanded(%+v, %v) = %v, want %v", tc.res, tc.err, got, tc.want)
			}
		})
	}
}
