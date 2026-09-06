package service

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// The ListenBrainz import. The listens surface is a real play log with a
// time per play, walked newest to oldest by max_ts; loved recordings
// come off the feedback surface. A token is optional - a public history
// answers without one - and the base URL is overridable, because the
// API shape is implemented by more than one server.

// migrateLBPageSize is the listens endpoint's own maximum. A variable
// rather than a constant so a test can put a page boundary where it
// needs one: what the cursor does when a page ends inside a group of
// listens sharing one second is the whole of its correctness.
var migrateLBPageSize = 1000

const (
	// migrateLBFeedbackPage is the feedback endpoint's maximum.
	migrateLBFeedbackPage = 100
	// migrateLBMaxPages bounds one import: at a thousand listens a page
	// this is more history than any real account has, and the summary
	// says when the cap was reached.
	migrateLBMaxPages = 2500
	// migrateLBPause spaces the requests. The public instance limits by
	// address and an import is not something anybody is waiting on, so
	// this is politeness bought with time nobody spends.
	migrateLBPause = 250 * time.Millisecond
)

// lbClient reads the slice of the ListenBrainz API this import walks.
type lbClient struct {
	migrateSource
	token string
}

func newLBClient(base, token string) *lbClient {
	return &lbClient{migrateSource: newMigrateSource("listenbrainz", base), token: token}
}

func (c *lbClient) get(ctx context.Context, path string, out any) error {
	// A token only widens what a public history answers with, so an
	// account read without one carries no authorization at all.
	header := http.Header{}
	if c.token != "" {
		header.Set("Authorization", "Token "+c.token)
	}
	return c.migrateSource.get(ctx, path, header, out)
}

// lbTrackMetadata is the descriptive half of a listen or a feedback row.
type lbTrackMetadata struct {
	ArtistName     string `json:"artist_name"`
	TrackName      string `json:"track_name"`
	ReleaseName    string `json:"release_name"`
	AdditionalInfo struct {
		RecordingMBID string  `json:"recording_mbid"`
		DurationMS    int64   `json:"duration_ms"`
		Duration      float64 `json:"duration"`
	} `json:"additional_info"`
	MBIDMapping struct {
		RecordingMBID string `json:"recording_mbid"`
	} `json:"mbid_mapping"`
}

// mbid answers the recording identifier, preferring what the submitter
// sent over what the server's own mapping guessed.
func (m lbTrackMetadata) mbid() string {
	if m.AdditionalInfo.RecordingMBID != "" {
		return m.AdditionalInfo.RecordingMBID
	}
	return m.MBIDMapping.RecordingMBID
}

// msPlayed answers what the submitter recorded, in milliseconds; zero
// when nothing was recorded, which takes the matched item's duration.
func (m lbTrackMetadata) msPlayed() int64 {
	if m.AdditionalInfo.DurationMS > 0 {
		return m.AdditionalInfo.DurationMS
	}
	return int64(m.AdditionalInfo.Duration * 1000)
}

type lbListen struct {
	ListenedAt    int64           `json:"listened_at"`
	RecordingMSID string          `json:"recording_msid"`
	TrackMetadata lbTrackMetadata `json:"track_metadata"`
}

// listens reads one page, older than maxTS when that is set.
func (c *lbClient) listens(ctx context.Context, user string, maxTS int64) ([]lbListen, error) {
	q := url.Values{"count": {strconv.Itoa(migrateLBPageSize)}}
	if maxTS > 0 {
		q.Set("max_ts", strconv.FormatInt(maxTS, 10))
	}
	var out struct {
		Payload struct {
			Listens []lbListen `json:"listens"`
		} `json:"payload"`
	}
	err := c.get(ctx, "/1/user/"+url.PathEscape(user)+"/listens?"+q.Encode(), &out)
	return out.Payload.Listens, err
}

// feedback reads one page of loved recordings.
func (c *lbClient) feedback(ctx context.Context, user string, offset int) ([]lbTrackMetadata, error) {
	q := url.Values{
		"score":    {"1"},
		"metadata": {"true"},
		"count":    {strconv.Itoa(migrateLBFeedbackPage)},
		"offset":   {strconv.Itoa(offset)},
	}
	var out struct {
		Feedback []struct {
			RecordingMBID string          `json:"recording_mbid"`
			TrackMetadata lbTrackMetadata `json:"track_metadata"`
		} `json:"feedback"`
	}
	if err := c.get(ctx, "/1/feedback/user/"+url.PathEscape(user)+"/get-feedback?"+q.Encode(), &out); err != nil {
		return nil, err
	}
	rows := make([]lbTrackMetadata, 0, len(out.Feedback))
	for _, f := range out.Feedback {
		m := f.TrackMetadata
		if m.AdditionalInfo.RecordingMBID == "" {
			m.AdditionalInfo.RecordingMBID = f.RecordingMBID
		}
		rows = append(rows, m)
	}
	return rows, nil
}

// runListenBrainzImport replays an account's listens and loved
// recordings onto the target account.
func (l *Library) runListenBrainzImport(ctx context.Context, t *wdb.ToolTask, uc *UserCtx, p migrationParams, secret string) (migrationSummary, error) {
	sum := migrationSummary{Source: p.Source, DryRun: p.DryRun, Samples: migrationSamples{Unmatched: []string{}}}
	client := newLBClient(p.ServerURL, secret)
	prog := newMigrateProgress(l, t)
	hist := l.newMigrateHistory(uc, p, &sum)

	if p.History {
		maxTS := int64(0)
		for page := 0; page < migrateLBMaxPages; page++ {
			if ctx.Err() != nil {
				return sum, ctx.Err()
			}
			rows, err := client.listens(ctx, p.Username, maxTS)
			if err != nil {
				var hs *migrateHTTPError
				if errors.As(err, &hs) && hs.Status == http.StatusNotFound {
					// A compatible server that takes submissions but
					// serves no history. Nothing to retry, and the
					// sentence has to say which half is missing.
					return sum, fmt.Errorf("%w: this server does not serve listen history", errToolPermanent)
				}
				return sum, migrateClientErr(err)
			}
			if len(rows) == 0 {
				break
			}
			oldest := int64(0)
			for _, r := range rows {
				if r.ListenedAt <= 0 {
					continue
				}
				if oldest == 0 || r.ListenedAt < oldest {
					oldest = r.ListenedAt
				}
				m := r.TrackMetadata
				// The msid identifies the submission; without one the
				// descriptive fields have to, which is the same fold the
				// session id uses everywhere else.
				id := r.RecordingMSID
				if id == "" {
					id = m.ArtistName
				}
				if err := hist.add(ctx, migratePlay{
					SourceID: strconv.FormatInt(r.ListenedAt, 10) + "|" + id + "|" + m.TrackName,
					MBID:     m.mbid(),
					Artist:   m.ArtistName,
					Title:    m.TrackName,
					Album:    m.ReleaseName,
					At:       time.Unix(r.ListenedAt, 0),
					MsPlayed: m.msPlayed(),
					// A submitted listen is a play the service counted.
					Finished: true,
				}); err != nil {
					return sum, err
				}
			}
			prog.report(ctx, 85)
			// Walked until a page comes back empty rather than until one
			// comes back short: a short page is not documented to mean
			// the end, and stopping on one would silently drop whatever
			// is older. Without a usable timestamp there is no window to
			// advance, so that does end the walk.
			if oldest == 0 {
				break
			}
			// The window's older end walks back. max_ts is exclusive, so
			// asking for the oldest row's own second re-reads that row -
			// a duplicate the deterministic ids absorb - and asking for
			// anything below it would skip every listen sharing that
			// second which did not fit on this page. Ties at one second
			// are ordinary in a history that was itself bulk-imported.
			next := oldest + 1
			if maxTS != 0 && next >= maxTS {
				// A whole page inside one second: the cursor cannot go
				// below it without skipping the rest of that second, and
				// cannot stay without repeating the page. Whether more
				// remain there is unknowable, so a full page says the
				// history was cut short and a short one says it ended.
				if len(rows) >= migrateLBPageSize {
					sum.HistoryTruncated = true
				}
				break
			}
			maxTS = next
			// Spaced, like every other walk of somebody else's server.
			// The public instance rate-limits per address, and a
			// thousand requests back to back is what trips it - after
			// which a 429 is what the rest of the history costs.
			select {
			case <-ctx.Done():
				return sum, ctx.Err()
			case <-time.After(migrateLBPause):
			}
			if page == migrateLBMaxPages-1 {
				// The cap, with the walk still going.
				sum.HistoryTruncated = true
			}
		}
		if err := hist.finish(ctx); err != nil {
			return sum, err
		}
	}

	if p.Stars {
		for offset := 0; offset < migrateLBMaxPages*migrateLBFeedbackPage; offset += migrateLBFeedbackPage {
			if ctx.Err() != nil {
				return sum, ctx.Err()
			}
			rows, err := client.feedback(ctx, p.Username, offset)
			if err != nil {
				return sum, migrateClientErr(err)
			}
			if len(rows) == 0 {
				break
			}
			for _, m := range rows {
				if m.TrackName == "" && m.mbid() == "" {
					continue
				}
				if err := hist.star(ctx, migratePlay{
					MBID:   m.mbid(),
					Artist: m.ArtistName,
					Title:  m.TrackName,
					Album:  m.ReleaseName,
				}); err != nil {
					return sum, err
				}
			}
			prog.report(ctx, 90)
			if len(rows) < migrateLBFeedbackPage {
				break
			}
			if offset+migrateLBFeedbackPage >= migrateLBMaxPages*migrateLBFeedbackPage {
				// The cap, with pages left: what landed is the most
				// recent of them, and the report has to say so.
				sum.HistoryTruncated = true
			}
			select {
			case <-ctx.Done():
				return sum, ctx.Err()
			case <-time.After(migrateLBPause):
			}
		}
	}

	prog.report(ctx, 95)
	return sum, nil
}
