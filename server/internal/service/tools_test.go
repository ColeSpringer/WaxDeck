package service

import (
	"errors"
	"testing"

	"github.com/colespringer/waxlabel"
)

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
