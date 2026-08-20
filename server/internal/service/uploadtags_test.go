package service

import (
	"testing"

	"github.com/colespringer/waxlabel/tag"
)

// The one reader of this order is the DATE the matcher scores against,
// and nothing else in the suite carries a document holding more than one
// date. Reversed - or reordered by a later argument shuffle - a reissue
// matches the release it was reissued as instead of the one it is.
func TestMatchDatePrefersTheRecordingOverTheReissue(t *testing.T) {
	for _, c := range []struct {
		name string
		tags tag.Tags
		want string
	}{
		{
			name: "a reissue carrying all three files under the recording",
			tags: tag.Tags{
				RecordingDate: "1969",
				ReleaseDate:   "2011",
				OriginalDate:  "1969-08-16",
			},
			want: "1969",
		},
		{
			name: "release stands in where nothing recorded a date",
			tags: tag.Tags{ReleaseDate: "2011", OriginalDate: "1969"},
			want: "2011",
		},
		{
			name: "original is the last resort",
			tags: tag.Tags{OriginalDate: "1969"},
			want: "1969",
		},
		{
			name: "a document with no date at all answers nothing",
			tags: tag.Tags{},
			want: "",
		},
	} {
		t.Run(c.name, func(t *testing.T) {
			if got := matchDate(c.tags); got != c.want {
				t.Errorf("matchDate = %q, want %q", got, c.want)
			}
		})
	}
}
