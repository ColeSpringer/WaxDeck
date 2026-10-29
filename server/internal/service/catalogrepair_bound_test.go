package service

import (
	"testing"
	"time"
)

// A repair reads the whole catalog at every step, which on a large one on
// slow storage takes far longer than the half hour other tools get, so
// each of its attempts has the six hours a health fix has.
func TestACatalogRepairAttemptHasSixHours(t *testing.T) {
	t.Parallel()
	if got := toolRunTimeoutFor(taskTypeCatalogRepair); got != 6*time.Hour {
		t.Errorf("a catalog repair attempt's bound = %v, want six hours", got)
	}
	if got := toolRunTimeoutFor(taskTypeBookMerge); got != toolRunTimeout {
		t.Errorf("a book merge attempt's bound = %v, want %v", got, toolRunTimeout)
	}
}
