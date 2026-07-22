package service

import (
	"testing"
	"time"
)

func TestParseRadioTitle(t *testing.T) {
	cases := []struct {
		raw, station  string
		artist, title string
		ok            bool
	}{
		{"Massive Attack - Teardrop", "Groove Salad", "Massive Attack", "Teardrop", true},
		{"A - B - C", "", "A", "B - C", true},
		{"  Boards of Canada -  Roygbiv ", "", "Boards of Canada", "Roygbiv", true},
		{"Groove Salad", "Groove Salad", "", "", false},
		{"Groove Salad - The Chill Hour", "Groove Salad", "", "", false},
		{"Best Mix - Groove Salad", "Groove Salad", "", "", false},
		{"NoSeparatorHere", "", "", "", false},
		{"Visit us at https://station.example - now", "", "", "", false},
		{" - Title only", "", "", "", false},
		{"Artist only - ", "", "", "", false},
		{"", "", "", "", false},
	}
	for _, c := range cases {
		artist, title, ok := parseRadioTitle(c.raw, c.station)
		if ok != c.ok || artist != c.artist || title != c.title {
			t.Errorf("parseRadioTitle(%q, %q) = %q, %q, %v; want %q, %q, %v",
				c.raw, c.station, artist, title, ok, c.artist, c.title, c.ok)
		}
	}
}

func TestScrobbleRadioPlayEnqueues(t *testing.T) {
	ctx, svc, admin := newAdminFixture(t)
	st, err := svc.CreateRadioStation(ctx, admin, RadioStationEdit{
		Name: "Groove Salad", StreamURL: "https://ice.example.net/groove",
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.storeScrobbleConnection(ctx, admin.ID, ScrobblerListenBrainz, "token", "sam", ""); err != nil {
		t.Fatal(err)
	}

	started := time.Now().Add(-2 * time.Minute)
	svc.ScrobbleRadioPlay(ctx, admin.ID, st.PID, "Massive Attack - Teardrop", started)

	row, err := svc.db.LeaseScrobble(ctx, time.Now().UnixNano(), int64(time.Minute), 3)
	if err != nil {
		t.Fatalf("expected a queued scrobble: %v", err)
	}
	if row.Artist != "Massive Attack" || row.Title != "Teardrop" ||
		row.ItemPID != st.PID || row.DurationMS != 0 ||
		row.ListenedAtNS != started.UnixNano() {
		t.Fatalf("queued row: %+v", row)
	}

	// Junk titles queue nothing.
	svc.ScrobbleRadioPlay(ctx, admin.ID, st.PID, "Groove Salad", started)
	if _, err := svc.db.LeaseScrobble(ctx, time.Now().UnixNano(), int64(time.Minute), 3); err == nil {
		t.Fatal("station-slogan title must not scrobble")
	}

	// Users without connections queue nothing (no error, no row).
	other, err := svc.CreateAccount(ctx, AccountCreate{Username: "quiet", Password: "password123"})
	if err != nil {
		t.Fatal(err)
	}
	svc.ScrobbleRadioPlay(ctx, other.User.ID, st.PID, "Massive Attack - Teardrop", started)
	if _, err := svc.db.LeaseScrobble(ctx, time.Now().UnixNano(), int64(time.Minute), 3); err == nil {
		t.Fatal("no-connection listener must not scrobble")
	}
}
