package cron

import (
	"strings"
	"testing"
	"time"
)

func mustParse(t *testing.T, spec string) *Schedule {
	t.Helper()
	s, err := Parse(spec)
	if err != nil {
		t.Fatalf("Parse(%q): unexpected error: %v", spec, err)
	}
	return s
}

func TestParseErrors(t *testing.T) {
	tests := []struct {
		name string
		spec string
		want string // substring of the error message
	}{
		{"empty spec", "", "expected 5 fields"},
		{"too few fields", "* * * *", "expected 5 fields"},
		{"too many fields", "* * * * * *", "expected 5 fields"},
		{"minute out of range", "63 * * * *", "cron: minute: value 63 out of range 0-59"},
		{"hour out of range", "* 24 * * *", "cron: hour: value 24 out of range 0-23"},
		{"day of month zero", "* * 0 * *", "cron: day-of-month: value 0 out of range 1-31"},
		{"month out of range", "* * * 13 *", "cron: month: value 13 out of range 1-12"},
		{"day of week out of range", "* * * * 8", "cron: day-of-week: value 8 out of range 0-7"},
		{"range endpoint out of range", "10-63 * * * *", "cron: minute: value 63 out of range 0-59"},
		{"reversed range", "30-10 * * * *", "cron: minute: reversed range"},
		{"reversed name range", "* * * * fri-mon", "cron: day-of-week: reversed range"},
		{"zero step", "*/0 * * * *", "cron: minute: step must be positive"},
		{"non-numeric step", "*/x * * * *", "cron: minute: invalid step"},
		{"empty step", "1-5/ * * * *", "cron: minute: invalid step"},
		{"double step", "*/2/3 * * * *", "cron: minute: invalid step"},
		{"step on single value", "5/2 * * * *", "cron: minute: step requires a range"},
		{"non-numeric value", "x * * * *", `cron: minute: invalid value "x"`},
		{"dangling range", "5- * * * *", `cron: minute: invalid value ""`},
		{"empty list element", "1,,2 * * * *", "cron: minute: empty list element"},
		{"unknown month name", "* * * janx *", `cron: month: invalid value "janx"`},
		{"unknown day name", "* * * * monday", `cron: day-of-week: invalid value "monday"`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := Parse(tt.spec)
			if err == nil {
				t.Fatalf("Parse(%q): want error containing %q, got nil", tt.spec, tt.want)
			}
			if !strings.Contains(err.Error(), tt.want) {
				t.Fatalf("Parse(%q): error %q does not contain %q", tt.spec, err.Error(), tt.want)
			}
		})
	}
}

func TestNext(t *testing.T) {
	d := func(y int, mo time.Month, day, h, m int) time.Time {
		return time.Date(y, mo, day, h, m, 0, 0, time.UTC)
	}
	tests := []struct {
		name  string
		spec  string
		after time.Time
		want  time.Time
	}{
		{"daily 3am from earlier that day", "0 3 * * *", d(2026, 7, 21, 1, 0), d(2026, 7, 21, 3, 0)},
		{"daily 3am from later that day", "0 3 * * *", d(2026, 7, 21, 4, 0), d(2026, 7, 22, 3, 0)},
		{"daily 3am from a minute before", "0 3 * * *", d(2026, 7, 21, 2, 59), d(2026, 7, 21, 3, 0)},
		{"exact firing time returns the following one", "0 3 * * *", d(2026, 7, 21, 3, 0), d(2026, 7, 22, 3, 0)},
		{"seconds after a firing still move on", "0 3 * * *", time.Date(2026, 7, 21, 3, 0, 30, 0, time.UTC), d(2026, 7, 22, 3, 0)},
		{"step firing is strictly after", "*/15 * * * *", d(2026, 7, 21, 10, 15), d(2026, 7, 21, 10, 30)},
		{"step before window", "*/20 9-17 * * *", d(2026, 7, 21, 8, 0), d(2026, 7, 21, 9, 0)},
		{"step inside window", "*/20 9-17 * * *", d(2026, 7, 21, 9, 25), d(2026, 7, 21, 9, 40)},
		{"step past window rolls to next day", "*/20 9-17 * * *", d(2026, 7, 21, 17, 45), d(2026, 7, 22, 9, 0)},
		{"range with step", "10-50/20 * * * *", d(2026, 7, 21, 0, 31), d(2026, 7, 21, 0, 50)},
		{"lists", "5,35 6,18 * * *", d(2026, 7, 21, 6, 10), d(2026, 7, 21, 6, 35)},
		{"month name", "0 12 1 Mar *", d(2026, 1, 15, 0, 0), d(2026, 3, 1, 12, 0)},
		{"month name list", "0 0 1 jan,jul *", d(2026, 2, 1, 0, 0), d(2026, 7, 1, 0, 0)},
		{"month name range", "0 0 1 oct-dec *", d(2026, 8, 2, 0, 0), d(2026, 10, 1, 0, 0)},
		{"day name range", "0 9 * * mon-fri", d(2026, 7, 18, 10, 0), d(2026, 7, 20, 9, 0)}, // Jul 18 2026 is a Saturday
		{"day name uppercase", "0 0 * * SUN", d(2026, 7, 20, 0, 0), d(2026, 7, 26, 0, 0)},
		{"day of week 7 is sunday", "0 0 * * 7", d(2026, 7, 20, 0, 0), d(2026, 7, 26, 0, 0)},
		{"day range through 7", "0 0 * * 5-7", d(2026, 7, 21, 0, 0), d(2026, 7, 24, 0, 0)}, // Tuesday to Friday
		{"day range through 7 includes sunday", "0 0 * * 5-7", d(2026, 7, 25, 0, 0), d(2026, 7, 26, 0, 0)},
		{"dom or dow: weekday matches first", "0 0 13 * 5", d(2026, 11, 1, 0, 0), d(2026, 11, 6, 0, 0)},
		{"dom or dow: both match", "0 0 13 * 5", d(2026, 11, 6, 0, 0), d(2026, 11, 13, 0, 0)},
		{"dom or dow: day of month matches first", "0 0 13 * 5", d(2026, 12, 12, 0, 0), d(2026, 12, 13, 0, 0)}, // Dec 13 2026 is a Sunday
		{"dom alone governs when dow is star", "0 0 15 * *", d(2026, 7, 21, 0, 0), d(2026, 8, 15, 0, 0)},
		{"dow alone governs when dom is star", "0 0 * * 1", d(2026, 7, 21, 0, 0), d(2026, 7, 27, 0, 0)},
		{"jan 31 rolls to next month with a 31st", "0 0 31 * *", d(2026, 1, 31, 0, 0), d(2026, 3, 31, 0, 0)},
		{"feb 29 waits for a leap year", "0 0 29 2 *", d(2026, 1, 1, 0, 0), d(2028, 2, 29, 0, 0)},
		{"year rollover", "30 23 31 12 *", d(2026, 12, 31, 23, 30), d(2027, 12, 31, 23, 30)},
		{"jan 1 across the year boundary", "0 0 1 1 *", d(2026, 6, 15, 0, 0), d(2027, 1, 1, 0, 0)},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := mustParse(t, tt.spec).Next(tt.after)
			if !got.Equal(tt.want) {
				t.Fatalf("Parse(%q).Next(%v) = %v, want %v", tt.spec, tt.after, got, tt.want)
			}
		})
	}
}

func TestNextDSTSpringForward(t *testing.T) {
	ny, err := time.LoadLocation("America/New_York")
	if err != nil {
		t.Fatalf("LoadLocation: %v", err)
	}
	s := mustParse(t, "30 2 * * *")

	// 2026-03-08 02:00 EST jumps to 03:00 EDT, so 02:30 does not exist that
	// day. Next must return the instant time.Date normalizes 02:30 to
	// rather than skipping the day or looping.
	after := time.Date(2026, 3, 8, 1, 0, 0, 0, ny)
	got := s.Next(after)
	want := time.Date(2026, 3, 8, 2, 30, 0, 0, ny)
	if !got.Equal(want) {
		t.Fatalf("Next(%v) = %v, want the normalized instant %v", after, got, want)
	}
	if !got.After(after) {
		t.Fatalf("Next(%v) = %v, not strictly after", after, got)
	}
	if got.Location() != ny {
		t.Fatalf("Next returned location %v, want %v", got.Location(), ny)
	}
	// Pin the normalization direction of the pinned toolchain: Go resolves
	// the gap time to a wall clock valid in the pre-transition zone.
	if got.Hour() != 1 || got.Minute() != 30 {
		t.Fatalf("Next(%v) = %v, want wall clock 01:30 EST", after, got)
	}

	// The following day the schedule is back at an existing 02:30.
	got2 := s.Next(got)
	want2 := time.Date(2026, 3, 9, 2, 30, 0, 0, ny)
	if !got2.Equal(want2) {
		t.Fatalf("Next(%v) = %v, want %v", got, got2, want2)
	}
}

func TestNextImpossibleDateReturnsZero(t *testing.T) {
	s := mustParse(t, "0 0 30 2 *")
	if got := s.Next(time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)); !got.IsZero() {
		t.Fatalf("Next for %q = %v, want zero time", s, got)
	}
}

func TestString(t *testing.T) {
	tests := []struct {
		spec string
		want string
	}{
		{"0 3 * * *", "0 3 * * *"},
		{"  0   3 * *\t* ", "0 3 * * *"},
		{"*/5 0-12/2 1,15 jan-jun/2 sun", "*/5 0-12/2 1,15 jan-jun/2 sun"},
	}
	for _, tt := range tests {
		if got := mustParse(t, tt.spec).String(); got != tt.want {
			t.Errorf("Parse(%q).String() = %q, want %q", tt.spec, got, tt.want)
		}
	}
}
