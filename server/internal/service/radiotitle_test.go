package service

import (
	"testing"
	"time"
)

// ageRadioTitle backdates both of a station's clocks, so either bound
// can be crossed without waiting it out.
func ageRadioTitle(t *testing.T, l *Library, pid string, by time.Duration) {
	t.Helper()
	l.radioTitlesMu.Lock()
	defer l.radioTitlesMu.Unlock()
	entry, ok := l.radioTitles[pid]
	if !ok {
		t.Fatalf("no observed title for %q to age", pid)
	}
	entry.seenNS -= int64(by)
	entry.announcedNS -= int64(by)
	l.radioTitles[pid] = entry
}

// The bug this whole rung was blanking on: a station announces a title
// once and then says nothing until it changes, so a track longer than
// the freshness bound used to expire mid-play - taking its artwork with
// it, since the now-playing block is gated on the title.
func TestALongTrackKeepsItsTitleWhileTheStreamRuns(t *testing.T) {
	t.Parallel()
	_, svc, _ := newCatalogFixture(t)

	svc.NoteRadioMeta("rs-1", "Charlie Parker - Ornithology", "https://art.example/orn.png")
	ageRadioTitle(t, svc, "rs-1", radioTitleFreshFor+time.Minute)

	// The empty blocks a station sends between announcements are what
	// actually recur, and they say the stream is still running.
	svc.NoteRadioAlive("rs-1")
	title, artURL := svc.RadioNowPlayingMeta("rs-1")
	if title != "Charlie Parker - Ornithology" {
		t.Fatalf("title after a liveness block = %q, want the announced song", title)
	}
	if artURL != "https://art.example/orn.png" {
		t.Fatalf("art after a liveness block = %q, want it to survive with the title", artURL)
	}

	// The control, on its own station: nothing says the stream is alive,
	// so it reads as one that closed.
	svc.NoteRadioMeta("rs-2", "Charlie Parker - Ornithology", "")
	ageRadioTitle(t, svc, "rs-2", radioTitleFreshFor+time.Minute)
	if title, _ := svc.RadioNowPlayingMeta("rs-2"); title != "" {
		t.Fatalf("stale title = %q, want it dropped", title)
	}
}

// Nothing else revisits an entry once its station stops being relayed,
// so the read that finds one dead is what reclaims it - the same rule
// the artwork cache next door keeps.
func TestAStaleTitleIsReclaimedWhereItIsFound(t *testing.T) {
	t.Parallel()
	_, svc, _ := newCatalogFixture(t)

	svc.NoteRadioMeta("rs-1", "Charlie Parker - Ornithology", "")
	ageRadioTitle(t, svc, "rs-1", radioTitleHoldFor+time.Minute)
	svc.RadioNowPlayingMeta("rs-1")

	svc.radioTitlesMu.Lock()
	_, held := svc.radioTitles["rs-1"]
	svc.radioTitlesMu.Unlock()
	if held {
		t.Fatal("a dead entry survived the read that found it")
	}
}

// A station that no longer exists keeps nothing, the same as its logo.
func TestDeletingAStationForgetsItsTitle(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)
	st, err := svc.CreateRadioStation(ctx, admin, RadioStationEdit{
		Name: "Groove Salad", StreamURL: "https://ice.example.net/groove",
	})
	if err != nil {
		t.Fatal(err)
	}
	svc.NoteRadioMeta(st.PID, "Bluetech - Finding The Future", "")
	if err := svc.DeleteRadioStation(ctx, st.PID); err != nil {
		t.Fatal(err)
	}

	svc.radioTitlesMu.Lock()
	_, held := svc.radioTitles[st.PID]
	svc.radioTitlesMu.Unlock()
	if held {
		t.Fatal("a deleted station kept its observed title")
	}
}

// The other end of the same rope. A stream can outlive the automation
// that narrates it, and liveness alone would then hold one song on the
// face for as long as somebody listened. Past the hold bound nobody
// knows what is playing, and saying so is what the station mark is for.
func TestATitleNobodyRenewsEventuallyGoesQuiet(t *testing.T) {
	t.Parallel()
	_, svc, _ := newCatalogFixture(t)

	svc.NoteRadioMeta("rs-1", "Charlie Parker - Ornithology", "https://art.example/orn.png")
	ageRadioTitle(t, svc, "rs-1", radioTitleHoldFor+time.Minute)

	// The stream is demonstrably alive - this is not the stale-stream
	// case, it is the station that stopped talking.
	svc.NoteRadioAlive("rs-1")
	title, artURL := svc.RadioNowPlayingMeta("rs-1")
	if title != "" || artURL != "" {
		t.Fatalf("unrenewed title = (%q, %q), want the face to fall back", title, artURL)
	}

	// And it comes back the moment the station says anything, including
	// the same song.
	svc.NoteRadioMeta("rs-1", "Charlie Parker - Ornithology", "https://art.example/orn.png")
	if title, _ := svc.RadioNowPlayingMeta("rs-1"); title != "Charlie Parker - Ornithology" {
		t.Fatalf("re-announced title = %q, want it back", title)
	}
}

// The bound is on the station's silence, not on the listener's session:
// a long track is renewed by nothing and must survive anyway, which is
// what separates this from a title that has gone wrong.
func TestALongItemSurvivesWellPastASong(t *testing.T) {
	t.Parallel()
	_, svc, _ := newCatalogFixture(t)

	// A classical work, a DJ set, a prog side - all announced once and
	// left to run far longer than any single.
	svc.NoteRadioMeta("rs-1", "Pink Floyd - Echoes", "")
	ageRadioTitle(t, svc, "rs-1", 30*time.Minute)
	svc.NoteRadioAlive("rs-1")

	if title, _ := svc.RadioNowPlayingMeta("rs-1"); title != "Pink Floyd - Echoes" {
		t.Fatalf("title after half an hour = %q, want it standing", title)
	}
}

// Liveness is a refresh, not an announcement: a station nobody has heard
// a title from has nothing to keep fresh.
func TestLivenessDoesNotInventATitle(t *testing.T) {
	t.Parallel()
	_, svc, _ := newCatalogFixture(t)

	svc.NoteRadioAlive("rs-unheard")
	if title, _ := svc.RadioNowPlayingMeta("rs-unheard"); title != "" {
		t.Fatalf("title = %q, want nothing", title)
	}
}

// Automation sends an empty StreamTitle over idents, jingles and news.
// Honouring it emptied the face mid-programme and filled it again a
// minute later.
func TestAnEmptyAnnouncementIsNotAClear(t *testing.T) {
	t.Parallel()
	_, svc, _ := newCatalogFixture(t)

	svc.NoteRadioMeta("rs-1", "Charlie Parker - Ornithology", "https://art.example/orn.png")
	svc.NoteRadioMeta("rs-1", "", "")

	title, artURL := svc.RadioNowPlayingMeta("rs-1")
	if title != "Charlie Parker - Ornithology" || artURL != "https://art.example/orn.png" {
		t.Fatalf("after an empty announcement = (%q, %q), want the song to stand", title, artURL)
	}
}

// The other half of the same decision: an empty announcement counts as
// liveness, so what bounds a title gone wrong is the stream ending
// rather than the station going quiet.
func TestAnEmptyAnnouncementKeepsTheStreamFresh(t *testing.T) {
	t.Parallel()
	_, svc, _ := newCatalogFixture(t)

	svc.NoteRadioMeta("rs-1", "Charlie Parker - Ornithology", "")
	ageRadioTitle(t, svc, "rs-1", radioTitleFreshFor+time.Minute)
	svc.NoteRadioMeta("rs-1", "", "")

	if title, _ := svc.RadioNowPlayingMeta("rs-1"); title != "Charlie Parker - Ornithology" {
		t.Fatalf("title = %q, want it held", title)
	}
}
