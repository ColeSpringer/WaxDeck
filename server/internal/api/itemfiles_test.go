package api

import (
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// A file row the catalog could not read sends no size, as it sends no
// codec, rather than claiming an empty file.
func TestAnUnreadFileSendsNoSize(t *testing.T) {
	t.Parallel()
	row := itemFileJSON(service.ItemFileDTO{FilePID: "fi-1", Role: "alternate", Name: "a.flac"})
	if row.SizeBytes != nil || row.Codec != nil {
		t.Fatalf("row = %+v, want no size and no codec", row)
	}
	if row := itemFileJSON(service.ItemFileDTO{FilePID: "fi-2", Role: "primary", Name: "b.flac", SizeBytes: 9}); row.SizeBytes == nil || *row.SizeBytes != 9 {
		t.Fatalf("row = %+v, want its 9 bytes", row)
	}
}
