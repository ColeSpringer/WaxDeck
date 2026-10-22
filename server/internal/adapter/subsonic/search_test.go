package subsonic

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"testing"
)

// search3's counts are clamped as the other lists' are, to 500 at most,
// while zero still asks for none: a client probing the song count asks
// for no artists and no albums beside it.
func TestSearchCountsAreClamped(t *testing.T) {
	h, uc := serviceHandler(t)
	settle(t, h)
	ctx := context.Background()
	if _, err := h.index(ctx, uc); err != nil {
		t.Fatal(err)
	}
	var rows []track
	for i := range 600 {
		rows = append(rows, track{PID: fmt.Sprintf("tr-%d", i), Title: fmt.Sprintf("Song %d", i),
			AlbumArtist: fmt.Sprintf("Artist %d", i), Album: fmt.Sprintf("Album %d", i)})
	}
	big := buildIndex(rows, nil)
	h.idxMu.Lock()
	big.tail = h.idxTail
	if scope := indexScope(uc); scope == "" {
		h.idxShared = big
	} else {
		h.idxScoped[scope] = big
	}
	h.idxMu.Unlock()

	r := httptest.NewRequest("GET", "/rest/search3?f=json&query=&songCount=1000000&albumCount=1000000&artistCount=0", nil)
	if err := r.ParseForm(); err != nil {
		t.Fatal(err)
	}
	w := httptest.NewRecorder()
	h.search3(w, withCaller(r, uc), uc)
	var out struct {
		Response struct {
			Result struct {
				Artists []any `json:"artist"`
				Albums  []any `json:"album"`
				Songs   []any `json:"song"`
			} `json:"searchResult3"`
		} `json:"subsonic-response"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	res := out.Response.Result
	if len(res.Songs) != 500 || len(res.Albums) != 500 || len(res.Artists) != 0 {
		t.Fatalf("search3 = %d artists, %d albums, %d songs; want 0, 500 and 500",
			len(res.Artists), len(res.Albums), len(res.Songs))
	}
}
