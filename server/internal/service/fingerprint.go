package service

import (
	"cmp"
	"context"
	"path/filepath"
	"time"

	"github.com/colespringer/waxbin/fingerprint"
)

// defaultFpcalcTimeout bounds one fpcalc run. It reads two minutes of
// audio at most, in seconds, and one that never ends would hold whatever
// waits on it.
const defaultFpcalcTimeout = 2 * time.Minute

// fingerprintFile is a file's AcoustID fingerprint and the length fpcalc
// read in whole seconds, or nothing when fpcalc is absent or could not
// give one in fpcalcTimeout. expected is the file's own length: fpcalc exits non-zero on
// a damaged frame even past the span it needed, and such a read is kept
// when its fingerprint covers that span; with no length known, any
// failure is refused.
func (l *Library) fingerprintFile(ctx context.Context, path string, expected time.Duration) (string, int) {
	if l.fpcalcPath == "" {
		return "", 0
	}
	ctx, cancel := context.WithTimeout(ctx, cmp.Or(l.fpcalcTimeout, defaultFpcalcTimeout))
	defer cancel()
	r, err := fingerprint.ChromaprintCompressedDetail(ctx, l.fpcalcPath, path, 0, expected)
	if err != nil {
		l.log.Debug("fpcalc could not fingerprint a file", "file", filepath.Base(path), "err", err)
		return "", 0
	}
	if r.Partial {
		l.log.Debug("kept a fingerprint fpcalc read before an error",
			"file", filepath.Base(path), "exit", r.ExitCode, "note", r.Note)
	}
	return r.Compressed, r.DurationSec
}

// rawFingerprint is a file's Chromaprint sub-fingerprint, the form the
// catalog compares recordings by, under fingerprintFile's rule for a
// read that ended in an error.
func (l *Library) rawFingerprint(ctx context.Context, path string, expected time.Duration) []uint32 {
	if l.fpcalcPath == "" {
		return nil
	}
	ctx, cancel := context.WithTimeout(ctx, cmp.Or(l.fpcalcTimeout, defaultFpcalcTimeout))
	defer cancel()
	r, err := fingerprint.ChromaprintRawDetail(ctx, l.fpcalcPath, path, 0, expected)
	if err != nil {
		l.log.Debug("fpcalc could not fingerprint a file", "file", filepath.Base(path), "err", err)
		return nil
	}
	return r.Sub
}
