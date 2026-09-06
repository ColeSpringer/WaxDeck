package service

import (
	"archive/zip"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"path"
	"strings"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// The Spotify import. Spotify hands its users a zip rather than an API,
// so this reads the staged archive: the streaming history files for a
// real play log with a time per play, and the library file for the
// tracks they saved. Two history shapes exist - the basic export's
// "StreamingHistory_music_*.json" and the extended one's
// "Streaming_History_Audio_*.json" - and an account export can hold
// either.

// spotifyBasicRow is one play in the basic export. endTime is when the
// play stopped, in UTC and to the minute, so the start is derived.
type spotifyBasicRow struct {
	EndTime    string `json:"endTime"`
	ArtistName string `json:"artistName"`
	TrackName  string `json:"trackName"`
	MsPlayed   int64  `json:"msPlayed"`
}

// spotifyExtendedRow is one play in the extended export. `ts` is when
// the track stopped, the same instant the basic export spells
// `endTime`, so the start is derived from it the same way. A row with
// no track name is a podcast or an audiobook, which this import skips.
type spotifyExtendedRow struct {
	TS        string `json:"ts"`
	MsPlayed  int64  `json:"ms_played"`
	TrackName string `json:"master_metadata_track_name"`
	Artist    string `json:"master_metadata_album_artist_name"`
	Album     string `json:"master_metadata_album_album_name"`
}

// spotifyLibrary is the saved-tracks file.
type spotifyLibrary struct {
	Tracks []struct {
		Artist string `json:"artist"`
		Album  string `json:"album"`
		Track  string `json:"track"`
	} `json:"tracks"`
}

// runSpotifyImport replays a staged Spotify account export onto the
// target account: every play with the time it happened, and the saved
// tracks as stars.
func (l *Library) runSpotifyImport(ctx context.Context, t *wdb.ToolTask, uc *UserCtx, p migrationParams) (migrationSummary, error) {
	sum := migrationSummary{Source: p.Source, DryRun: p.DryRun, Samples: migrationSamples{Unmatched: []string{}}}
	row, archive, err := l.migrationExportFile(ctx, p.ExportID)
	if err != nil {
		return sum, err
	}
	zr, err := zip.OpenReader(archive)
	if err != nil {
		return sum, fmt.Errorf("%w: the uploaded export cannot be read: %v", errToolPermanent, err)
	}
	defer zr.Close()
	prog := newMigrateProgress(l, t)
	hist := l.newMigrateHistory(uc, p, &sum)
	// Reporting is the importer's only lease renewal, and one history
	// file can be a hundred thousand plays: without a tick from inside
	// the batches, a single entry outlives the lease and the task is
	// re-claimed mid-run.
	hist.tick = func() { prog.report(ctx, 85) }

	wanted := exportFiles(row)
	read := map[string]bool{}
	for _, name := range wanted {
		read[name] = true
	}
	// Anything this run declines to read decides whether the archive may
	// be deleted at the end. A stars-only run has no reason to parse a
	// decade of history, but it has no right to destroy it either.
	skipped := false
	budget := spotifyReadMaxBytes
	for i, f := range zr.File {
		if ctx.Err() != nil {
			return sum, ctx.Err()
		}
		if !read[f.Name] {
			continue
		}
		prog.report(ctx, float64(i+1)/float64(len(zr.File))*85)
		base := path.Base(f.Name)
		library := base == "YourLibrary.json"
		if (library && !p.Stars) || (!library && !p.History) {
			skipped = true
			continue
		}
		sum.Files++
		var err error
		switch {
		case library:
			err = l.importSpotifyLibrary(ctx, hist, f, &budget)
		case spotifyExtendedHistory(base):
			err = decodeSpotifyRows(f, &budget, func(r spotifyExtendedRow) error {
				return l.addSpotifyExtended(ctx, hist, r)
			})
		default:
			err = decodeSpotifyRows(f, &budget, func(r spotifyBasicRow) error {
				return l.addSpotifyBasic(ctx, hist, r)
			})
		}
		if err != nil {
			return sum, err
		}
	}
	if err := hist.finish(ctx); err != nil {
		return sum, err
	}

	// Whether the upload may go, rather than the act of removing it: the
	// task settles that once its own completion is on disk, so a crash
	// between the two cannot delete a history whose import will be
	// re-run. Only a run that read all of it may say yes - a dry run is
	// kept because the point of one is running the real import
	// afterwards, and a run with a switch turned off would otherwise
	// destroy the half it was told to leave alone.
	sum.ExportConsumed = !p.DryRun && !skipped
	prog.report(ctx, 95)
	return sum, nil
}

// spotifyReadMaxBytes bounds what one import reads out of an archive,
// across every file in it. Not a memory bound: the rows are streamed,
// so no file is ever held whole and the peak is one play. It is what
// stops a half-gigabyte upload that decompresses to fifty from holding
// a drain worker for a day. A decade of extended history is tens of
// megabytes, so this is two orders of magnitude of headroom.
var spotifyReadMaxBytes int64 = 2 << 30

// spotifyLibraryMaxBytes bounds the saved-tracks file, which is the one
// entry this import does not stream.
const spotifyLibraryMaxBytes int64 = 64 << 20

// openZipEntry opens one archive member against the run's remaining
// read budget, which it draws down as the entry is read.
func openZipEntry(f *zip.File, budget *int64) (io.Reader, io.Closer, error) {
	rc, err := f.Open()
	if err != nil {
		return nil, nil, fmt.Errorf("%w: %s cannot be read: %v", errToolPermanent, path.Base(f.Name), err)
	}
	return &budgetedReader{r: rc, left: budget, name: path.Base(f.Name)}, rc, nil
}

// budgetedReader spends a shared byte budget and says so when it runs
// out, rather than truncating: a silent short read reaches the decoder
// as malformed JSON and would be reported as the wrong file shape.
type budgetedReader struct {
	r    io.Reader
	left *int64
	name string
}

func (b *budgetedReader) Read(p []byte) (int, error) {
	if *b.left <= 0 {
		return 0, fmt.Errorf("%w: %s is larger than this import reads", errToolPermanent, b.name)
	}
	if int64(len(p)) > *b.left {
		p = p[:*b.left]
	}
	n, err := b.r.Read(p)
	*b.left -= int64(n)
	return n, err
}

// decodeSpotifyRows streams one history file, handing each row to fn.
// A decode over the reader rather than a read-then-parse: an account
// export declares as many history files as it likes and each of them
// can be large, and holding one whole and its parsed form at the same
// time is how a NAS-class host runs out of memory instead of failing
// the task.
func decodeSpotifyRows[T any](f *zip.File, budget *int64, fn func(T) error) error {
	r, closer, err := openZipEntry(f, budget)
	if err != nil {
		return err
	}
	defer closer.Close()
	name := path.Base(f.Name)
	dec := json.NewDecoder(r)
	tok, err := dec.Token()
	if err != nil {
		return spotifyReadErr(name, err)
	}
	if tok != json.Delim('[') {
		return spotifyBadShape(name)
	}
	for dec.More() {
		var row T
		if err := dec.Decode(&row); err != nil {
			return spotifyReadErr(name, err)
		}
		if err := fn(row); err != nil {
			return err
		}
	}
	// The closing bracket, read for its error rather than for itself.
	// More() answers false for a read that failed exactly as it does for
	// one that finished, so an entry that fails its checksum partway, or
	// a read that runs past this import's budget, would otherwise end
	// the loop with a fraction of the plays and no error at all - and
	// the run would then report success and delete the only copy of the
	// export.
	if _, err := dec.Token(); err != nil {
		return spotifyReadErr(name, err)
	}
	return nil
}

// spotifyBadShape is the refusal for a file that parses as something
// this import does not read.
func spotifyBadShape(name string) error {
	return fmt.Errorf("%w: %s is not the shape this import reads", errToolPermanent, name)
}

// spotifyReadErr separates a file that is not the shape this import
// reads from one that could not be read to the end. Permanent either
// way - an uploaded archive does not change - but a truncated read
// blamed on the file's shape sends an administrator looking at the
// wrong thing entirely.
func spotifyReadErr(name string, err error) error {
	if errors.Is(err, errToolPermanent) {
		return err
	}
	var syntax *json.SyntaxError
	var typed *json.UnmarshalTypeError
	if errors.As(err, &syntax) || errors.As(err, &typed) {
		return spotifyBadShape(name)
	}
	return fmt.Errorf("%w: %s could not be read to the end: %v", errToolPermanent, name, err)
}

// spotifyMsPlayed reads a row's played milliseconds. Out-of-range
// values are read as a play of no measured length rather than dropped:
// the timestamp and the names are still the history, and a zero-length
// play records that it happened without asserting a duration or
// crossing any played threshold.
func spotifyMsPlayed(ms int64) int64 {
	if ms < 0 || ms > migrateMaxMsPlayed {
		return 0
	}
	return ms
}

func (l *Library) addSpotifyBasic(ctx context.Context, hist *migrateHistory, r spotifyBasicRow) error {
	if r.TrackName == "" {
		return nil
	}
	// The basic export records when the play ended, to the minute,
	// so the start is derived from what was played.
	end, err := time.Parse("2006-01-02 15:04", strings.TrimSpace(r.EndTime))
	if err != nil {
		return nil
	}
	ms := spotifyMsPlayed(r.MsPlayed)
	return hist.add(ctx, migratePlay{
		SourceID: r.EndTime + "|" + r.ArtistName + "|" + r.TrackName + "|" +
			fmt.Sprint(r.MsPlayed),
		Artist:     r.ArtistName,
		Title:      r.TrackName,
		At:         end.Add(-time.Duration(ms) * time.Millisecond).UTC(),
		MsPlayed:   ms,
		MsMeasured: true,
	})
}

func (l *Library) addSpotifyExtended(ctx context.Context, hist *migrateHistory, r spotifyExtendedRow) error {
	// A row with no track name is a podcast episode or an audiobook
	// chapter, which shares the file and resolves against nothing in a
	// music catalog.
	if r.TrackName == "" {
		return nil
	}
	end, err := time.Parse(time.RFC3339, strings.TrimSpace(r.TS))
	if err != nil {
		return nil
	}
	ms := spotifyMsPlayed(r.MsPlayed)
	return hist.add(ctx, migratePlay{
		SourceID:   r.TS + "|" + r.Artist + "|" + r.TrackName + "|" + fmt.Sprint(r.MsPlayed),
		Artist:     r.Artist,
		Title:      r.TrackName,
		Album:      r.Album,
		At:         end.Add(-time.Duration(ms) * time.Millisecond).UTC(),
		MsPlayed:   ms,
		MsMeasured: true,
	})
}

func (l *Library) importSpotifyLibrary(ctx context.Context, hist *migrateHistory, f *zip.File, budget *int64) error {
	// Bounded on its own as well as against the run's budget: this file
	// is one object rather than a list, so it is decoded whole and held
	// whole - the streaming the history gets does not apply. A list of
	// saved tracks is a few megabytes at the outside.
	left := min(*budget, spotifyLibraryMaxBytes)
	spent := left
	defer func() { *budget -= spent - left }()
	r, closer, err := openZipEntry(f, &left)
	if err != nil {
		return err
	}
	defer closer.Close()
	var lib spotifyLibrary
	if err := json.NewDecoder(r).Decode(&lib); err != nil {
		return spotifyReadErr(path.Base(f.Name), err)
	}
	for _, tr := range lib.Tracks {
		if tr.Track == "" {
			continue
		}
		// The export records no time for a saved track, so the star
		// lands as of now; the catalog orders star writes by recorded
		// time and nil is what says that.
		if err := hist.star(ctx, migratePlay{
			Artist: tr.Artist,
			Title:  tr.Track,
			Album:  tr.Album,
		}); err != nil {
			return err
		}
	}
	return nil
}
