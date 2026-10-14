package main

import (
	"strings"
	"testing"
)

// A session cap below one is refused at startup rather than read as the
// default: an operator setting 0 to mean "no cap" is told it has none.
func TestSessionCapRefusesLessThanOne(t *testing.T) {
	for _, n := range []int{0, -5} {
		if _, err := sessionCapFrom(n); err == nil || !strings.Contains(err.Error(), "WAXDECK_SESSION_CAP") {
			t.Errorf("a cap of %d = %v, want a refusal naming the variable", n, err)
		}
	}
	if got, err := sessionCapFrom(250); err != nil || got != 250 {
		t.Errorf("a cap of 250 = %d, %v", got, err)
	}
}
