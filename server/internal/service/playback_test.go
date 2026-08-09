package service

import "testing"

func TestCrossedPlayedThreshold(t *testing.T) {
	t.Parallel()
	const minute = int64(60_000)
	cases := []struct {
		name       string
		mediaType  string
		msPlayed   int64
		durationMS int64
		want       bool
	}{
		{"music half of short track", "music", 500, 1000, true},
		{"music under half of short track", "music", 400, 1000, false},
		{"music four minutes of a long track", "music", 4 * minute, 10 * minute, true},
		{"music under both rules", "music", 3 * minute, 10 * minute, false},
		{"music two-hour set, four minutes is not enough", "music", 4 * minute, 120 * minute, false},
		{"music two-hour set, an hour counts", "music", 60 * minute, 120 * minute, true},
		{"podcast ninety percent", "podcast", 54 * minute, 60 * minute, true},
		{"podcast eighty percent", "podcast", 48 * minute, 60 * minute, false},
		{"audiobook complete", "audiobook", 594 * minute, 600 * minute, true},
		{"audiobook near complete", "audiobook", 580 * minute, 600 * minute, false},
		{"zero played", "music", 0, 1000, false},
		{"unknown duration", "music", 5 * minute, 0, false},
	}
	for _, c := range cases {
		if got := crossedPlayedThreshold(c.mediaType, c.msPlayed, c.durationMS); got != c.want {
			t.Errorf("%s: got %v, want %v", c.name, got, c.want)
		}
	}
}

func TestInvalidSession(t *testing.T) {
	t.Parallel()
	valid := ListenSession{SessionID: "s-1", PID: "tr-01JZX5N8QW3F4V9T2B7KD3M9R6"}
	cases := []struct {
		name   string
		mutate func(*ListenSession)
		reject bool
	}{
		{"well formed", func(*ListenSession) {}, false},
		{"live source", func(s *ListenSession) { s.Source = "live" }, false},
		{"import source", func(s *ListenSession) { s.Source = "import" }, false},
		{"missing session id", func(s *ListenSession) { s.SessionID = "" }, true},
		{"overlong session id", func(s *ListenSession) { s.SessionID = string(make([]byte, 65)) }, true},
		{"missing pid", func(s *ListenSession) { s.PID = "" }, true},
		{"negative msPlayed", func(s *ListenSession) { s.MsPlayed = -1 }, true},
		{"overlong client", func(s *ListenSession) { s.Client = string(make([]byte, 129)) }, true},
		{"unknown source", func(s *ListenSession) { s.Source = "scrobble" }, true},
	}
	for _, c := range cases {
		s := valid
		c.mutate(&s)
		reason := invalidSession(s)
		if got := reason != ""; got != c.reject {
			t.Errorf("%s: reject = %v (%q), want %v", c.name, got, reason, c.reject)
		}
	}
}
