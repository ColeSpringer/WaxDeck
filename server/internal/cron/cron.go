// Package cron parses five-field cron expressions and computes next firing
// times for WaxDeck's scheduled jobs (library scans, backups, pruning).
//
// The dialect is Vixie-style. A spec is five whitespace-separated fields:
// minute (0-59), hour (0-23), day of month (1-31), month (1-12), and day of
// week (0-7, where both 0 and 7 mean Sunday). Each field accepts *, single
// values, lists (a,b,c), ranges (a-b), and steps (*/n, a-b/n). The month and
// day-of-week fields also accept case-insensitive three-letter names
// (jan..dec, sun..sat), including as range endpoints.
package cron

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

// Schedule is a parsed cron expression. Use Parse to construct one.
type Schedule struct {
	spec    string
	minute  uint64 // bits 0-59
	hour    uint64 // bits 0-23
	dom     uint64 // bits 1-31
	month   uint64 // bits 1-12
	dow     uint64 // bits 0-6, Sunday twice (7) folded into 0
	domStar bool
	dowStar bool
}

var monthNames = map[string]int{
	"jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
	"jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
}

var dayNames = map[string]int{
	"sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6,
}

// Parse parses a five-field cron spec (minute hour day-of-month month
// day-of-week). Errors name the offending field, for example
// "cron: minute: value 63 out of range 0-59".
func Parse(spec string) (*Schedule, error) {
	fields := strings.Fields(spec)
	if len(fields) != 5 {
		return nil, fmt.Errorf("cron: expected 5 fields (minute hour day-of-month month day-of-week), got %d in %q", len(fields), spec)
	}
	s := &Schedule{spec: strings.Join(fields, " ")}
	var err error
	if s.minute, err = (field{"minute", 0, 59, nil}).parse(fields[0]); err != nil {
		return nil, err
	}
	if s.hour, err = (field{"hour", 0, 23, nil}).parse(fields[1]); err != nil {
		return nil, err
	}
	if s.dom, err = (field{"day-of-month", 1, 31, nil}).parse(fields[2]); err != nil {
		return nil, err
	}
	if s.month, err = (field{"month", 1, 12, monthNames}).parse(fields[3]); err != nil {
		return nil, err
	}
	if s.dow, err = (field{"day-of-week", 0, 7, dayNames}).parse(fields[4]); err != nil {
		return nil, err
	}
	if s.dow&(1<<7) != 0 {
		s.dow = s.dow&^(1<<7) | 1
	}
	// For the either-or day rule a field is unrestricted only when it is
	// literally "*"; forms such as */2 count as restricted.
	s.domStar = fields[2] == "*"
	s.dowStar = fields[4] == "*"
	return s, nil
}

// String returns the spec with fields joined by single spaces.
func (s *Schedule) String() string {
	return s.spec
}

// Next returns the next time the schedule fires strictly after the given
// time, computed in that time's location with seconds truncated to zero.
//
// The search is bounded: if nothing matches within roughly five years
// (for example "0 0 30 2 *", February 30th), Next returns the zero Time.
//
// Candidate wall-clock times are built with time.Date, which normalizes
// times a DST transition makes nonexistent: a schedule for 02:30 on a
// spring-forward day where 02:00 jumps to 03:00 fires at the instant
// time.Date resolves 02:30 to — a wall time valid in one of the two zones
// adjacent to the transition — instead of being skipped or looping. During
// a fall-back overlap the schedule fires once, at whichever of the two
// instants time.Date resolves the repeated wall time to.
func (s *Schedule) Next(after time.Time) time.Time {
	loc := after.Location()
	limit := after.AddDate(5, 0, 1)
	// Noon anchors keep day arithmetic stable in zones where a DST jump can
	// skip midnight.
	day := time.Date(after.Year(), after.Month(), after.Day(), 12, 0, 0, 0, loc)
	for day.Before(limit) {
		if s.month&(1<<day.Month()) == 0 {
			day = time.Date(day.Year(), day.Month()+1, 1, 12, 0, 0, 0, loc)
			continue
		}
		if s.dayMatches(day) {
			if t, ok := s.firstOnDay(day, after); ok {
				return t
			}
		}
		day = time.Date(day.Year(), day.Month(), day.Day()+1, 12, 0, 0, 0, loc)
	}
	return time.Time{}
}

// dayMatches applies Vixie cron's either-or day rule: when both the
// day-of-month and day-of-week fields are restricted, the day matches when
// either field matches; when only one is restricted, it alone governs.
func (s *Schedule) dayMatches(day time.Time) bool {
	domOK := s.dom&(1<<day.Day()) != 0
	dowOK := s.dow&(1<<day.Weekday()) != 0
	switch {
	case s.domStar:
		return dowOK
	case s.dowStar:
		return domOK
	default:
		return domOK || dowOK
	}
}

// firstOnDay returns the earliest candidate on day's date strictly after
// the given time. All matching hour/minute pairs are scanned because DST
// normalization can reorder candidates built from field values.
func (s *Schedule) firstOnDay(day, after time.Time) (time.Time, bool) {
	loc := after.Location()
	y, mo, d := day.Date()
	var best time.Time
	for h := 0; h < 24; h++ {
		if s.hour&(1<<h) == 0 {
			continue
		}
		for m := 0; m < 60; m++ {
			if s.minute&(1<<m) == 0 {
				continue
			}
			cand := time.Date(y, mo, d, h, m, 0, 0, loc)
			if cand.After(after) && (best.IsZero() || cand.Before(best)) {
				best = cand
			}
		}
	}
	return best, !best.IsZero()
}

// field describes one position of the spec for parsing.
type field struct {
	name     string
	min, max int
	names    map[string]int
}

func (f field) parse(s string) (uint64, error) {
	var bits uint64
	for _, part := range strings.Split(s, ",") {
		if part == "" {
			return 0, fmt.Errorf("cron: %s: empty list element in %q", f.name, s)
		}
		b, err := f.parsePart(part)
		if err != nil {
			return 0, err
		}
		bits |= b
	}
	return bits, nil
}

func (f field) parsePart(part string) (uint64, error) {
	base, stepStr, hasStep := strings.Cut(part, "/")
	step := 1
	if hasStep {
		n, err := strconv.Atoi(stepStr)
		if !isDigits(stepStr) || err != nil {
			return 0, fmt.Errorf("cron: %s: invalid step in %q", f.name, part)
		}
		if n == 0 {
			return 0, fmt.Errorf("cron: %s: step must be positive in %q", f.name, part)
		}
		step = n
	}

	var lo, hi int
	switch {
	case base == "*":
		lo, hi = f.min, f.max
	case strings.Contains(base, "-"):
		loStr, hiStr, _ := strings.Cut(base, "-")
		var err error
		if lo, err = f.value(loStr); err != nil {
			return 0, err
		}
		if hi, err = f.value(hiStr); err != nil {
			return 0, err
		}
		if lo > hi {
			return 0, fmt.Errorf("cron: %s: reversed range %q", f.name, base)
		}
	default:
		v, err := f.value(base)
		if err != nil {
			return 0, err
		}
		if hasStep {
			return 0, fmt.Errorf("cron: %s: step requires a range in %q", f.name, part)
		}
		lo, hi = v, v
	}

	var bits uint64
	for v := lo; v <= hi; v += step {
		bits |= 1 << v
	}
	return bits, nil
}

func (f field) value(s string) (int, error) {
	if f.names != nil {
		if v, ok := f.names[strings.ToLower(s)]; ok {
			return v, nil
		}
	}
	if !isDigits(s) {
		return 0, fmt.Errorf("cron: %s: invalid value %q", f.name, s)
	}
	n, err := strconv.Atoi(s)
	if err != nil {
		return 0, fmt.Errorf("cron: %s: invalid value %q", f.name, s)
	}
	if n < f.min || n > f.max {
		return 0, fmt.Errorf("cron: %s: value %d out of range %d-%d", f.name, n, f.min, f.max)
	}
	return n, nil
}

func isDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}
