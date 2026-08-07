package service

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/colespringer/waxbin/port"
	"github.com/colespringer/waxbin/waxerr"
)

// The stale-baseline recovery, WaxDeck's side of it.
//
// Pre-1.0 WaxBin edits its v1 baseline in place rather than migrating, and
// stamps the baseline's fingerprint into the catalog so a build whose schema
// has moved refuses the catalog at open instead of failing on whichever write
// first reaches a column that is not there. The refusal names `waxbin db reset`
// as its cure, which is the right instruction for someone holding the WaxBin
// CLI and no instruction at all for a WaxDeck operator: they run one server
// binary, usually in a container, and reach the catalog only through it. So
// WaxDeck carries the same recovery itself.

// CatalogResetReport is what a stale-baseline reset discarded, read from the
// catalog before it was moved aside.
type CatalogResetReport struct {
	// SavedTo is where the previous catalog now lives. Empty when there was
	// no catalog to move.
	SavedTo string
	// Items and the counts beside it are what the previous catalog held.
	// They are meaningless when Partial is set.
	Items        int
	PlayStates   int
	Playlists    int
	Podcasts     int
	TrashEntries int
	// Partial reports that the census could not read the catalog, so the
	// counts understate it. Reporting zeros as the contents would tell the
	// operator a full catalog was empty, which is the one thing they do not
	// mean.
	Partial bool
	// UnconfiguredRoots are library roots the previous catalog held that
	// configuration does not name -- added at runtime, and the part of a
	// reset that startup will not put back.
	UnconfiguredRoots []string
}

// staleBaseline reports whether path's baseline fingerprint is not this
// build's. Probed rather than matched on the refusal's wording, so a schema
// downgrade (which keeps the v1 fingerprint) answers false and is refused
// rather than discarded. It cannot tell a baseline that moved forward from one
// that moved back, so a rollback across a baseline edit discards -- the
// accepted pre-1.0 cost, and why the flag is opt-in. Anything unreadable
// answers false, which keeps a catalog nobody has diagnosed.
func staleBaseline(ctx context.Context, path string) bool {
	_, err := port.ValidateBackup(ctx, path)
	return waxerr.Is(err, waxerr.CodeUnsupported)
}

// resetStaleCatalog moves the catalog and its WAL/shm sidecars aside and
// reports what they held. It does not create the replacement: the caller's
// next Open does that, with the roots and options it was already going to
// pass.
func resetStaleCatalog(ctx context.Context, dbPath string, configuredRoots []Root) (*CatalogResetReport, error) {
	// Best effort: a catalog too damaged to census still has to be
	// resettable, it just gets reported as unknown rather than as empty.
	census, _ := port.ReadCensus(ctx, dbPath)

	moved, err := moveCatalogAside(dbPath)
	if err != nil {
		return nil, err
	}

	rep := &CatalogResetReport{SavedTo: moved}
	if census != nil {
		rep.Items, rep.PlayStates = census.Items, census.PlayStates
		rep.Playlists, rep.Podcasts = census.Playlists, census.Podcasts
		rep.TrashEntries, rep.Partial = census.TrashEntries, census.Partial
		rep.UnconfiguredRoots = rootsNotConfigured(census.Roots, configuredRoots)
	}
	return rep, nil
}

// moveCatalogAside renames the catalog to a timestamped .stale-<ts>.bak set,
// keeping the -wal/-shm suffixes so the saved files stay a readable trio.
// Returns the new main-file path, or "" when there was no catalog to move.
//
// The set moves together or not at all, rolling back what it already renamed:
// the -wal can hold commits the main file lacks, so a half-moved catalog would
// drop them from the copy that exists to make a mis-fire recoverable.
func moveCatalogAside(dbPath string) (string, error) {
	const op = "service.resetStaleCatalog"
	if _, err := os.Stat(dbPath); err != nil {
		if os.IsNotExist(err) {
			return "", nil
		}
		return "", fmt.Errorf("%s: %w", op, err)
	}
	// The stamp is second-granular and os.Rename overwrites silently, so two
	// resets inside one second would replace the backup the first made.
	// Take the first free name instead.
	base := fmt.Sprintf("%s.stale-%s", dbPath, time.Now().UTC().Format("20060102T150405Z"))
	dest := base + ".bak"
	// Bounded, and any stat error that is not "absent" is fatal: an
	// unreadable data dir answers the same non-ENOENT error for every
	// candidate, and looping on it would hang startup with no log line.
	for n := 2; ; n++ {
		_, err := os.Stat(dest)
		if os.IsNotExist(err) {
			break
		}
		if err != nil {
			return "", fmt.Errorf("%s: %w", op, err)
		}
		if n > 1000 {
			return "", fmt.Errorf("%s: no free backup name beside %s", op, dbPath)
		}
		dest = fmt.Sprintf("%s-%d.bak", base, n)
	}

	var done [][2]string
	for _, suffix := range []string{"", "-wal", "-shm"} {
		src, dst := dbPath+suffix, dest+suffix
		if _, err := os.Stat(src); err != nil {
			continue
		}
		if err := os.Rename(src, dst); err != nil {
			for _, d := range done {
				_ = os.Rename(d[1], d[0])
			}
			return "", fmt.Errorf("%s: %w", op, err)
		}
		done = append(done, [2]string{src, dst})
	}
	return dest, nil
}

// rootsNotConfigured returns the catalog's roots that configuration does not
// name -- the ones a reset really loses, since startup re-registers the rest.
func rootsNotConfigured(catalogRoots []string, configured []Root) []string {
	known := make(map[string]struct{}, len(configured))
	for _, r := range configured {
		known[r.Path] = struct{}{}
	}
	var out []string
	for _, r := range catalogRoots {
		if _, ok := known[r]; !ok {
			out = append(out, r)
		}
	}
	return out
}

// logCatalogReset states what the reset discarded. It logs rather than
// returning a string because the only caller is startup, where this is the one
// record that the state is gone.
func (l *Library) logCatalogReset(rep *CatalogResetReport) {
	if rep.SavedTo == "" {
		l.log.Warn("catalog was built from a different schema baseline; created a fresh one (nothing to move aside)")
		return
	}
	if rep.Partial {
		// Zeros here would read as "the catalog was empty".
		l.log.Warn("catalog was built from a different schema baseline; moved it aside and created a fresh one",
			"savedTo", rep.SavedTo, "discarded", "unknown (the previous catalog could not be read)")
	} else {
		l.log.Warn("catalog was built from a different schema baseline; moved it aside and created a fresh one",
			"savedTo", rep.SavedTo, "items", rep.Items, "playStates", rep.PlayStates,
			"playlists", rep.Playlists, "podcasts", rep.Podcasts, "trashEntries", rep.TrashEntries)
	}
	if len(rep.UnconfiguredRoots) > 0 {
		l.log.Warn("the previous catalog held library roots this configuration does not name; re-add them to bring them back",
			"roots", rep.UnconfiguredRoots)
	}
}
