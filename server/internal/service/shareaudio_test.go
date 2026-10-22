package service

import (
	"context"
	"testing"

	"github.com/colespringer/waxbin/model"
)

// A member with no file on this server has nothing to play unless it is
// an episode the feed can relay: a trashed one is not relayed from its
// feed, however relayable the feed's audio, and a track or a book whose
// file has gone is not offered as a file.
func TestAShareMemberWithoutAFileHasNoAudioUnlessItRelays(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	show := model.PID("01SHOWFORTRASHEDMEMBERS000")
	svc.showSources.Store(show, model.SourceRSS)
	feedEpisode := func(pid model.PID) *model.Episode {
		return &model.Episode{PID: pid, PodcastPID: show, EnclosureURL: "https://feeds.example/ep.mp3"}
	}
	svc.episodeReadHook = func(_ context.Context, pids []model.PID) ([]*model.Episode, error) {
		out := make([]*model.Episode, 0, len(pids))
		for _, pid := range pids {
			out = append(out, feedEpisode(pid))
		}
		return out, nil
	}
	views := []*model.ItemView{
		{PID: "01TRASHEDEPISODE0000000000", Kind: model.KindEpisode, State: model.StateArchived, PodcastPID: show},
		{PID: "01TRASHEDTRACK000000000000", Kind: model.KindTrack, State: model.StateArchived},
		{PID: "01UNFETCHEDEPISODE00000000", Kind: model.KindEpisode, State: model.StateRemote, PodcastPID: show},
		{PID: "01PRESENTTRACK000000000000", Kind: model.KindTrack, State: model.StatePresent},
		{PID: "01MISSINGTRACK000000000000", Kind: model.KindTrack, State: model.StateMissing},
		{PID: "01MISSINGBOOK0000000000000", Kind: model.KindBook, State: model.StateMissing},
		{PID: "01REMOTETRACK0000000000000", Kind: model.KindTrack, State: model.StateRemote},
		{PID: "01MISSINGEPISODE0000000000", Kind: model.KindEpisode, State: model.StateMissing, PodcastPID: show},
	}
	audio, err := svc.shareAudio(ctx, views, nil)
	if err != nil {
		t.Fatal(err)
	}
	for i, want := range []ShareAudio{"", "", ShareAudioRelay, ShareAudioLocal, "", "", "", ShareAudioRelay} {
		if got := audio[itemAPIPID(views[i])]; got != want {
			t.Errorf("%s %s = %q, want %q", views[i].State, views[i].Kind, got, want)
		}
		if got := audio[itemAPIPID(views[i])].Plays(); got != (want != "") {
			t.Errorf("%s %s plays = %v", views[i].State, views[i].Kind, got)
		}
	}
}
