package service

import (
	"context"
	"errors"
	"net/http"
	"net/url"
	"time"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// The Audiobookshelf import. The /api/me profile carries every book's
// mediaProgress; each referenced item is fetched for its identity
// (title, author, ASIN/ISBN, duration) and matched through the resolve
// ladder, and the position lands through the same checkpoint path the
// API's resume writes use. A finished book checkpoints at its end,
// which is exactly how the catalog's position-derived completion rules
// mark a book played and finished.

// absClient is a minimal Audiobookshelf API client: bearer token,
// JSON answers.
type absClient struct {
	migrateSource
	token string
}

func newABSClient(base, token string) *absClient {
	return &absClient{migrateSource: newMigrateSource("audiobookshelf", base), token: token}
}

func (c *absClient) get(ctx context.Context, path string, out any) error {
	return c.migrateSource.get(ctx, path,
		http.Header{"Authorization": {"Bearer " + c.token}}, out)
}

// absMediaProgress is one row of the profile's mediaProgress: times in
// seconds, lastUpdate in epoch milliseconds. EpisodeID marks podcast
// progress, which the gpodder surface owns, not this importer.
type absMediaProgress struct {
	LibraryItemID string  `json:"libraryItemId"`
	EpisodeID     string  `json:"episodeId"`
	CurrentTime   float64 `json:"currentTime"`
	IsFinished    bool    `json:"isFinished"`
	LastUpdate    int64   `json:"lastUpdate"`
}

// absItem is the expanded library item, trimmed to the identity fields
// the matcher needs. Duration is seconds.
type absItem struct {
	Media struct {
		Metadata struct {
			Title      string `json:"title"`
			AuthorName string `json:"authorName"`
			Authors    []struct {
				Name string `json:"name"`
			} `json:"authors"`
			ASIN string `json:"asin"`
			ISBN string `json:"isbn"`
		} `json:"metadata"`
		Duration float64 `json:"duration"`
	} `json:"media"`
}

// runABSImport pulls book positions and finished flags from an
// Audiobookshelf server and replays them for the task's user. Books
// resolve by ASIN/ISBN first and author/title descriptively after;
// multi-file books need no special handling because a catalog book's
// position is a book-timeline millisecond by contract.
func (l *Library) runABSImport(ctx context.Context, t *wdb.ToolTask, uc *UserCtx, p migrationParams, secret string) (migrationSummary, error) {
	sum := migrationSummary{Source: p.Source, DryRun: p.DryRun, Samples: migrationSamples{Unmatched: []string{}}}
	client := newABSClient(p.ServerURL, secret)
	prog := newMigrateProgress(l, t)
	var me struct {
		MediaProgress []absMediaProgress `json:"mediaProgress"`
	}
	if err := client.get(ctx, "/api/me", &me); err != nil {
		return sum, migrateClientErr(err)
	}
	for i, mp := range me.MediaProgress {
		if ctx.Err() != nil {
			return sum, ctx.Err()
		}
		prog.report(ctx, float64(i+1)/float64(len(me.MediaProgress))*90)
		if mp.EpisodeID != "" || mp.LibraryItemID == "" {
			continue
		}
		if mp.CurrentTime <= 0 && !mp.IsFinished {
			continue
		}
		var item absItem
		if err := client.get(ctx, "/api/items/"+url.PathEscape(mp.LibraryItemID)+"?expanded=1", &item); err != nil {
			var hs *migrateHTTPError
			if errors.As(err, &hs) && hs.Status == http.StatusNotFound {
				// The progress row outlived its book on the source; one
				// stale row must not fail the whole import.
				sum.noteUnmatched("", mp.LibraryItemID)
				continue
			}
			return sum, migrateClientErr(err)
		}
		meta := item.Media.Metadata
		author := meta.AuthorName
		if author == "" && len(meta.Authors) > 0 {
			author = meta.Authors[0].Name
		}
		ref := model.PortableRef{
			Kind:       model.KindBook,
			ASIN:       meta.ASIN,
			ISBN:       meta.ISBN,
			Artist:     author,
			Title:      meta.Title,
			DurationMS: int64(item.Media.Duration * 1000),
		}
		it, rung, err := l.resolveMigrationRef(ctx, ref)
		if err != nil {
			return sum, classify(err)
		}
		if it == nil || rung == model.MatchNone {
			sum.noteUnmatched(author, meta.Title)
			continue
		}
		sum.Matched++
		if !p.Progress {
			continue
		}
		posMS := int64(mp.CurrentTime * 1000)
		if mp.IsFinished && it.DurationMS > 0 {
			// The catalog derives played and finished from the position
			// reached, so a finished book checkpoints at its end rather
			// than carrying a separate flag.
			posMS = it.DurationMS
		}
		// Replay the checkpoint in the source's own recorded time so the
		// position stamp orders it against whatever the user has already
		// listened to here: a backdated import stops reading as a
		// just-now checkpoint and losing them their place.
		var recordedAt *time.Time
		if mp.LastUpdate > 0 {
			ts := time.UnixMilli(mp.LastUpdate)
			recordedAt = &ts
		}
		if !p.DryRun {
			applied, err := l.Checkpoint(ctx, uc, apiPID(PrefixBook, it.PID), posMS, recordedAt)
			if err != nil {
				if !migrateWriteSkippable(err) {
					return sum, err
				}
				l.log.Warn("migration progress skipped", "task", t.ID, "item", string(it.PID), "err", err)
				continue
			}
			if !applied {
				// The local position is newer than the source's recorded
				// time, so the replay lost. Counting it would report a
				// write the import did not make.
				continue
			}
		}
		sum.Progress++
	}
	prog.report(ctx, 95)
	return sum, nil
}
