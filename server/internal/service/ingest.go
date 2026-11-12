package service

import (
	"cmp"
	"context"
	"sync"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/inbox"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"
	"github.com/colespringer/waxdeck/server/internal/match"
)

// Ingest is getting media in: uploads, matching, review, acquisition,
// fingerprinting and write-back drift.
type Ingest struct {
	*core
	// planHook stands in for the catalog's import planner in a test;
	// nothing in the server sets it.
	planHook func(context.Context, waxbin.AcquiredFile, model.Kind, waxbin.AcquiredMeta) (*waxbin.AcquiredResult, error)
	// discardReadHook runs between a discard's first read of its session
	// and its guards, in a test; nothing in the server sets it.
	discardReadHook func()
	// bodyReadHook runs once an append has read a chunk's body and before
	// the session counts its bytes, in a test; nothing in the server sets
	// it.
	bodyReadHook func()
	// applyImportHook stands in for the catalog's import apply in a test;
	// nothing in the server sets it.
	applyImportHook func(context.Context, *inbox.Plan) (*inbox.Report, error)
	// batchFinalizeMu serializes upload-batch finalization (the flip,
	// entry opening, and member linking as one unit): two concurrent
	// finalizes of one batch would otherwise both gather the same
	// still-unlinked members and open duplicate review entries.
	// Process-wide is fine - finalizes are rare and database-only.
	batchFinalizeMu sync.Mutex
	// engine is the release matching engine; nil when no candidate
	// source is configured (review entries then hold no candidates).
	engine *match.Engine
	// stagingDir holds upload staging; uploadFormats is the accepted
	// extension set (uploadFormatsList the sorted health-payload form,
	// deny-list subtracted); uploadRetention bounds staged-byte
	// lifetime.
	stagingDir        string
	uploadFormats     map[string]bool
	uploadFormatsList []string
	uploadRetention   time.Duration
	// stagingFree answers how much room the staging volume has left,
	// for the check a new session runs. A field rather than a direct
	// call so a test can hand it a full disk; nothing configures it.
	stagingFree func(string) (int64, bool)
	// admitUpload serializes the allowance checks a new session runs
	// against the insert that spends them.
	admitUpload sync.Mutex
	// completing holds the ids of the upload sessions a complete or a
	// discard is working on, so a second waits its turn.
	completing sync.Map
	// appendLocks serialize the chunk appends of one upload session.
	appendLocks sessionLocks
	// deciding holds the ids of the review entries a decision, revert,
	// search or discard is changing, one at a time.
	deciding sync.Map
	// waitingForCatalog holds the declined submissions whose import met
	// another job holding the catalog, tried again when a job ends or the
	// follower finds none running; heldOff those whose entry another
	// change held, tried again when it lets go.
	waitingForCatalog sync.Map
	heldOff           sync.Map
	// fpcalcTimeout bounds one fpcalc run when set, defaultFpcalcTimeout
	// otherwise.
	fpcalcTimeout time.Duration
	// fpcalcPath is the fingerprint binary, empty when absent (matching
	// then runs on tag and search evidence only).
	fpcalcPath string
	// matchWake nudges the identify worker; lossy, ticker-backstopped.
	matchWake chan struct{}
	// sourceProviders are the injected acquisition providers, kept for
	// the acquire-from-URL surface (the catalog holds its own copy for
	// show dispatch).
	sourceProviders []source.Provider
}

func newIngest(c *core, cfg Config) *Ingest {
	return &Ingest{
		core:            c,
		matchWake:       make(chan struct{}, 1),
		uploadRetention: cmp.Or(cfg.UploadRetention, 7*24*time.Hour),
	}
}
