package main

import (
	"strings"
	"testing"
)

// A negative window, or one past what a Duration holds (it would wrap to
// a short one), is refused; anything else passes through.
func TestEnrichRetryWindowRefusesAnUnholdableCount(t *testing.T) {
	for _, days := range []int{-1, 106752} {
		if _, err := enrichRetryWindow(days); err == nil || !strings.Contains(err.Error(), "WAXDECK_ENRICHMENT_RETRY_MISSES_DAYS") {
			t.Errorf("%d days = %v, want a refusal naming the variable", days, err)
		}
	}
	for _, days := range []int{0, 30, 106751} {
		if got, err := enrichRetryWindow(days); err != nil || got == nil || *got != days {
			t.Errorf("%d days = %v, %v; want it passed through", days, got, err)
		}
	}
}
