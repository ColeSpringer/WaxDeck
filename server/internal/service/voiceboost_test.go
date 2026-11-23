package service

import (
	"testing"

	"github.com/colespringer/waxdeck/fixtures"
)

// The boost a stream is minted with: an explicit choice wins, then the
// caller's stored setting for the book, then the caller's default; a
// stored off is a setting, not an absence.
func TestEffectiveVoiceBoostForABook(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixtureWith(t, catalogFixtureOptions{extra: func(t *testing.T, dir string) {
		if _, err := fixtures.GenerateBook(dir); err != nil {
			t.Fatal(err)
		}
	}})
	books, err := svc.Reads.Items(ctx, uc, ItemFilter{MediaType: "audiobook"}, "", 10)
	if err != nil || len(books.Items) != 1 {
		t.Fatalf("books = %+v (%v), want the fixture book", books.Items, err)
	}
	book := books.Items[0].PID
	boost := func(explicit *bool, def bool) bool {
		return svc.Playback.EffectiveVoiceBoost(ctx, uc, book, explicit, def)
	}

	if !boost(nil, true) {
		t.Error("none stored, default on: want the boost")
	}
	if boost(nil, false) {
		t.Error("none stored, default off: want none")
	}
	if boost(ptrTo(false), true) {
		t.Error("an explicit off under a default on: want none")
	}

	store := func(on bool) {
		t.Helper()
		if _, err := svc.Reads.PutBookSettings(ctx, uc, book, BookSettings{VoiceBoost: ptrTo(on)}); err != nil {
			t.Fatal(err)
		}
	}
	store(true)
	if !boost(nil, false) {
		t.Error("stored on, default off: want the boost")
	}
	if boost(ptrTo(false), true) {
		t.Error("stored on, explicit off: want none")
	}
	store(false)
	if boost(nil, true) {
		t.Error("stored off, default on: want none")
	}
	if !boost(ptrTo(true), false) {
		t.Error("stored off, explicit on: want the boost")
	}
}

// The same for an episode, whose setting is its show's subscription: a
// show the caller does not follow has none stored.
func TestEffectiveVoiceBoostForAnEpisode(t *testing.T) {
	d := newDormantFollower(t)
	episode := d.episodes["Episode 1"]
	boost := func(explicit *bool, def bool) bool {
		return d.svc.Playback.EffectiveVoiceBoost(d.ctx, d.carol(t), episode, explicit, def)
	}

	if !boost(nil, true) {
		t.Error("followed, none stored, default on: want the boost")
	}
	if boost(nil, false) {
		t.Error("followed, none stored, default off: want none")
	}

	store := func(on bool) {
		t.Helper()
		if _, err := d.svc.Podcasts.PutSubscriptionSettings(d.ctx, d.carol(t), d.show, SubscriptionSettings{VoiceBoost: ptrTo(on)}); err != nil {
			t.Fatal(err)
		}
	}
	store(true)
	if !boost(nil, false) {
		t.Error("stored on, default off: want the boost")
	}
	if boost(ptrTo(false), true) {
		t.Error("stored on, explicit off: want none")
	}
	store(false)
	if boost(nil, true) {
		t.Error("stored off, default on: want none")
	}
	if !boost(ptrTo(true), false) {
		t.Error("stored off, explicit on: want the boost")
	}

	if err := d.svc.Podcasts.Unsubscribe(d.ctx, d.carol(t), d.show, false); err != nil {
		t.Fatal(err)
	}
	if !boost(nil, true) {
		t.Error("unfollowed, default on: want the boost")
	}
	if boost(nil, false) {
		t.Error("unfollowed, default off: want none")
	}
}

// Music keeps no boost setting and takes no default.
func TestEffectiveVoiceBoostIgnoresTheDefaultForMusic(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	track, _ := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")
	if svc.Playback.EffectiveVoiceBoost(ctx, uc, track, nil, true) {
		t.Error("a music track took the spoken-word default")
	}
}
