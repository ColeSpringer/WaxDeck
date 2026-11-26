package service

import (
	"fmt"
	"strings"
	"testing"

	catalogerr "github.com/colespringer/waxbin/waxerr"
	waxtap "github.com/colespringer/waxtap/v3"
)

// A source's refusal fails the task in WaxDeck's sentence for its reason,
// wherever the source answered it, and the failure notice says the same:
// the source's own words are for the log.
func TestASourceRefusalIsRecordedInTheServersSentence(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name, link, reason, sourceSaid string
		playlist                       bool
		src                            *probeSource
	}{
		{
			name: "at the listing", link: "https://tube.example/playlist?list=PLgone", reason: reasonPlaylistUnavailable,
			playlist:   true,
			sourceSaid: "Esta lista es privada.",
			src: &probeSource{listErr: catalogerr.Wrap(catalogerr.CodeIO, "enumerate",
				fmt.Errorf("Esta lista es privada.: %w", waxtap.ErrPlaylistUnavailable))},
		},
		{
			name: "at the fetch", link: "https://tube.example/watch?v=one", reason: reasonVideoUnavailable,
			sourceSaid: "Video unavailable, this video has been removed by the uploader",
			src: &probeSource{fetchErr: catalogerr.Wrap(catalogerr.CodeIO, "fetch",
				fmt.Errorf("Video unavailable, this video has been removed by the uploader: %w", waxtap.ErrVideoUnavailable))},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc := acquireFixture(t, tc.src)
			task, err := svc.Ingest.StartAcquisition(ctx, uc, tc.link, tc.playlist, "music", "", "", nil, nil)
			if err != nil {
				t.Fatal(err)
			}
			drainOnce(t, ctx, svc)
			want := sourceReasons[tc.reason].sentence
			row := storedTask(t, ctx, svc, task.ID)
			if row.State != taskStateFailed || row.ErrorCode != "source-refused" || row.Error != want {
				t.Fatalf("task = %s, code %q (error %q); want it failed for %s in %q", row.State, row.ErrorCode, row.Error, tc.reason, want)
			}
			notice := waitForInbox(t, ctx, svc, uc, "tool-task-failed")
			if !strings.Contains(notice.Body, want) || strings.Contains(notice.Body, tc.sourceSaid) {
				t.Errorf("the failure notice says %q, want the server's sentence %q alone", notice.Body, want)
			}
		})
	}
}
