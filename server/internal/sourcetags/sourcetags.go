// Package sourcetags is the tag pass every acquisition provider runs on a
// downloaded file: provenance (where the audio came from) and the clean
// tags the source got wrong, in one WaxLabel write. The noise rules live
// in sourcenoise; this package only decides what to write.
package sourcetags

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"slices"
	"strings"
	"time"

	waxlabel "github.com/colespringer/waxlabel"
	"github.com/colespringer/waxlabel/tag"

	"github.com/colespringer/waxdeck/server/internal/sourcenoise"
)

// Source is what the source says about one download.
type Source struct {
	URL         string // written as SOURCE_URL
	ID          string // written as SOURCE_ID
	Author      string // the uploader; the file's ARTIST
	Title       string
	Description string
	// Music cleans the title and reads an Art Track description; a
	// podcast episode or an audiobook keeps its title as delivered.
	Music bool
}

// ErrPostCommit says the tags landed and a step after the write failed.
var ErrPostCommit = errors.New("source tags written; a step after the write failed")

// Stamp writes the provenance tags and, from src, ARTIST without YouTube's
// " - Topic" suffix; for music also the title without upload notes and,
// when the description is an Art Track's for this title, its title,
// artists, album and release date (no date when it states none). The
// "Artist - Track" split is never written. A tag already holding what it
// would get is left alone.
func Stamp(ctx context.Context, path string, src Source) error {
	doc, err := waxlabel.ParseFile(ctx, path)
	if err != nil {
		return fmt.Errorf("parse: %w", err)
	}
	ed := doc.Edit()
	set := func(k tag.Key, vals ...string) {
		if cur, _ := doc.Get(k); !slices.Equal(cur, vals) {
			ed.Set(k, vals...)
		}
	}
	if src.URL != "" {
		set(tag.SourceURL, src.URL)
	}
	if src.ID != "" {
		set(tag.SourceID, src.ID)
	}
	set(tag.AcquisitionDate, time.Now().UTC().Format(time.RFC3339))
	c := clean(src)
	if len(c.artists) > 0 {
		// Several artists are a repeated ARTIST, which the catalog reads as
		// a stated credit list rather than a joined name it must guess at.
		set(tag.Artist, c.artists...)
	}
	if c.title != "" {
		set(tag.Title, c.title)
	}
	if c.album != "" {
		set(tag.Album, c.album)
	}
	switch {
	case c.date != "":
		set(tag.RecordingDate, c.date)
	case c.dropDate:
		// The embed's upload date would date a real album.
		if cur, _ := doc.Get(tag.RecordingDate); len(cur) > 0 {
			ed.Clear(tag.RecordingDate)
		}
	}
	plan, err := ed.Prepare()
	if err != nil {
		return fmt.Errorf("prepare: %w", err)
	}
	if _, res, err := plan.Execute(ctx, waxlabel.SaveBack()); err != nil {
		if writeLanded(res, err) {
			return fmt.Errorf("%w: %w", ErrPostCommit, err)
		}
		return fmt.Errorf("write: %w", err)
	}
	return nil
}

type cleaned struct {
	artists            []string
	title, album, date string
	dropDate           bool
}

func clean(src Source) cleaned {
	var c cleaned
	if a := strings.TrimSpace(sourcenoise.StripTopicSuffix(src.Author)); a != "" {
		c.artists = []string{a}
	}
	if !src.Music {
		return c
	}
	c.title = sourcenoise.CleanUploadNotes(src.Title)
	// A title or artist holding the description's own separator mis-splits
	// its title line, so the description counts only when its title is
	// this video's, as it stands or cleaned for writing or for a search.
	// Then it is the label's own metadata and wins whole: its title, and
	// its release date or none.
	if at, ok := sourcenoise.ParseArtTrackDescription(src.Description); ok &&
		(sourcenoise.SameTitle(at.Title, src.Title) || sourcenoise.SameTitle(at.Title, c.title) ||
			sourcenoise.SameTitle(at.Title, sourcenoise.CleanDescriptiveTitle(src.Title))) {
		c.artists, c.title, c.album, c.date = at.Artists, at.Title, at.Album, at.Released
		c.dropDate = at.Released == ""
	}
	return c
}

// Restamp lands r in a temp file under dir (the system temp when empty),
// stamps it with the file's own ARTIST and TITLE as the author and title,
// and copies the result to w. It is for a source whose file carries all it
// knows; the stamp is best effort, so a file WaxLabel cannot read is
// copied as delivered.
func Restamp(ctx context.Context, dir, ext string, r io.Reader, w io.Writer, src Source) (int64, error) {
	tmp, err := os.CreateTemp(dir, "restamp-*"+ext)
	if err != nil {
		return 0, err
	}
	path := tmp.Name()
	defer os.Remove(path)
	_, err = io.Copy(tmp, r)
	if cerr := tmp.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		return 0, err
	}
	if doc, err := waxlabel.ParseFile(ctx, path); err == nil {
		f := doc.Fields()
		src.Title = f.Title
		// A stated list of several is already a credit, not an uploader.
		if len(f.Artists) == 1 {
			src.Author = f.Artists[0]
		}
		_ = Stamp(ctx, path, src)
	}
	f, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	defer f.Close()
	return io.Copy(w, f)
}

// writeLanded says whether a SaveBack write reached the file. Committed is
// what answers that, not the error: an error with Committed set is a landed
// write whose post-commit step failed, so the bytes are in place and the plan
// is spent. A clean run with Committed clear is a no-op plan, which writes
// nothing by contract and is not a failure either. Duplicated from the
// service package, which this one cannot import.
func writeLanded(res waxlabel.SaveResult, err error) bool {
	return err == nil || res.Committed
}
