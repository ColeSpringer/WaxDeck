package service

import (
	"encoding/base64"
	"testing"
	"time"
)

func TestDayNumberConsecutiveAcrossDST(t *testing.T) {
	t.Parallel()
	denver, err := time.LoadLocation("America/Denver")
	if err != nil {
		t.Fatal(err)
	}
	// Spring forward (2026-03-08) and fall back (2026-11-01): the civil
	// dates around each transition must still differ by exactly one,
	// even though the days are 23 and 25 hours long.
	for _, span := range []struct {
		year  int
		month time.Month
		days  []int
	}{
		{2026, time.March, []int{7, 8, 9}},
		{2026, time.October, []int{31}},
	} {
		prev := dayNumber(time.Date(span.year, span.month, span.days[0], 12, 0, 0, 0, denver))
		for _, d := range span.days[1:] {
			cur := dayNumber(time.Date(span.year, span.month, d, 12, 0, 0, 0, denver))
			if cur != prev+1 {
				t.Fatalf("%d %s %d: dayNumber = %d, want %d", span.year, span.month, d, cur, prev+1)
			}
			prev = cur
		}
	}
	oct31 := dayNumber(time.Date(2026, time.October, 31, 12, 0, 0, 0, denver))
	nov1 := dayNumber(time.Date(2026, time.November, 1, 12, 0, 0, 0, denver))
	nov2 := dayNumber(time.Date(2026, time.November, 2, 12, 0, 0, 0, denver))
	if nov1 != oct31+1 || nov2 != nov1+1 {
		t.Fatalf("fall-back run = %d, %d, %d, want consecutive", oct31, nov1, nov2)
	}
}

func TestDayNumberYearBoundaryAndAnchor(t *testing.T) {
	t.Parallel()
	dec31 := dayNumber(time.Date(2025, time.December, 31, 23, 59, 0, 0, time.UTC))
	jan1 := dayNumber(time.Date(2026, time.January, 1, 0, 1, 0, 0, time.UTC))
	if jan1 != dec31+1 {
		t.Fatalf("year boundary: %d then %d, want consecutive", dec31, jan1)
	}
	if n := dayNumber(time.Date(1970, time.January, 1, 0, 0, 0, 0, time.UTC)); n != 0 {
		t.Fatalf("epoch dayNumber = %d, want 0", n)
	}
	// Only the civil date matters, never the zone offset.
	tokyo, err := time.LoadLocation("Asia/Tokyo")
	if err != nil {
		t.Fatal(err)
	}
	utc := dayNumber(time.Date(2026, time.July, 21, 1, 0, 0, 0, time.UTC))
	jst := dayNumber(time.Date(2026, time.July, 21, 23, 0, 0, 0, tokyo))
	if utc != jst {
		t.Fatalf("same civil date, different zones: %d vs %d", utc, jst)
	}
}

func TestBucketStart(t *testing.T) {
	t.Parallel()
	loc, err := time.LoadLocation("America/Denver")
	if err != nil {
		t.Fatal(err)
	}
	at := func(y int, m time.Month, d int) time.Time {
		return time.Date(y, m, d, 14, 30, 45, 0, loc)
	}
	midnight := func(y int, m time.Month, d int) time.Time {
		return time.Date(y, m, d, 0, 0, 0, 0, loc)
	}
	cases := []struct {
		name   string
		in     time.Time
		bucket string
		want   time.Time
	}{
		{"day floors to midnight", at(2026, time.July, 15), "day", midnight(2026, time.July, 15)},
		{"week from Wednesday", at(2026, time.July, 15), "week", midnight(2026, time.July, 13)},
		{"week from Monday is itself", at(2026, time.July, 13), "week", midnight(2026, time.July, 13)},
		{"week from Sunday reaches back", at(2026, time.July, 19), "week", midnight(2026, time.July, 13)},
		{"week crosses a month boundary", at(2026, time.August, 1), "week", midnight(2026, time.July, 27)},
		{"month floors to the first", at(2026, time.July, 15), "month", midnight(2026, time.July, 1)},
	}
	for _, c := range cases {
		if got := bucketStart(c.in, c.bucket); !got.Equal(c.want) {
			t.Errorf("%s: bucketStart = %v, want %v", c.name, got, c.want)
		}
	}
}

func TestLongestRun(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name string
		days []int
		want int
	}{
		{"empty", nil, 0},
		{"single day", []int{5}, 1},
		{"two runs", []int{1, 2, 3, 7, 8}, 3},
		{"longer run later", []int{1, 2, 10, 11, 12, 13}, 4},
		{"no consecutive days", []int{2, 4, 6}, 1},
	}
	for _, c := range cases {
		days := map[int]bool{}
		for _, d := range c.days {
			days[d] = true
		}
		if got := longestRun(days); got != c.want {
			t.Errorf("%s: longestRun = %d, want %d", c.name, got, c.want)
		}
	}
}

func TestLogCursorRoundTrip(t *testing.T) {
	t.Parallel()
	wantNS, wantID := int64(1753000000000000000), int64(42)
	ns, id, err := decodeLogCursor(encodeLogCursor(wantNS, wantID))
	if err != nil || ns != wantNS || id != wantID {
		t.Fatalf("round trip = (%d, %d, %v), want (%d, %d, nil)", ns, id, err, wantNS, wantID)
	}
	// The empty cursor is the first page, never an error.
	if ns, id, err := decodeLogCursor(""); err != nil || ns != 0 || id != 0 {
		t.Fatalf("empty cursor = (%d, %d, %v), want (0, 0, nil)", ns, id, err)
	}
}

func TestLogCursorMalformed(t *testing.T) {
	t.Parallel()
	enc := func(raw string) string {
		return base64.RawURLEncoding.EncodeToString([]byte(raw))
	}
	for _, bad := range []string{
		"%%%",              // not base64url
		enc("nocolon"),     // no separator
		enc("abc:42"),      // non-numeric ns
		enc("42:abc"),      // non-numeric id
		enc(":"),           // both parts empty
		enc("1:2:3") + "!", // trailing junk breaks decoding
	} {
		if _, _, err := decodeLogCursor(bad); err == nil {
			t.Errorf("cursor %q decoded, want error", bad)
		}
	}
}
