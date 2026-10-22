package service

import (
	"testing"

	"github.com/colespringer/waxbin/model"
)

// The three upload doors share one answer for what a media type may be
// filed as: music and audiobook, with a podcast refused in a sentence of
// its own because it is a real medium that simply has no upload.
func TestRequireUploadMediaType(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		mediaType string
		kind      model.Kind
		refusal   string
	}{
		{"music", model.KindTrack, ""},
		{"audiobook", model.KindBook, ""},
		{"podcast", "", "podcasts are added by subscribing to a feed"},
		{"radio", "", "unknown media type"},
		{"", "", "unknown media type"},
	} {
		kind, err := requireUploadMediaType(tc.mediaType)
		if tc.refusal == "" {
			if err != nil || kind != tc.kind {
				t.Errorf("%q = %q, %v; want %q", tc.mediaType, kind, err, tc.kind)
			}
			continue
		}
		if KindOf(err) != KindInvalid || err.Error() != tc.refusal {
			t.Errorf("%q = %q, %v; want an invalid-request saying %q", tc.mediaType, kind, err, tc.refusal)
		}
	}
}
