package api

import (
	"encoding/json"
	"errors"
	"net/http/httptest"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// A book the engine-less join cannot lay out is answered as a download
// whose source cannot be read is: gone is not found, a catalog handed to
// maintenance says retry shortly, and a fault of the server's is its own,
// never a not-found that tells the client to give up.
func TestJoinRefusalsSayWhyTheBookCannotBeLaidOut(t *testing.T) {
	for _, c := range []struct {
		err    error
		status int
		code   string
	}{
		{&service.Error{Kind: service.KindNotFound, Msg: "no such book"}, 404, "not-found"},
		{&service.Error{Kind: service.KindInvalid, Msg: "not a book"}, 404, "not-found"},
		{&service.Error{Kind: service.KindMaintenance, Msg: "catalog handed off"}, 503, "catalog-maintenance"},
		{&service.Error{Kind: service.KindInternal, Err: errors.New("database is locked")}, 500, "internal"},
	} {
		rec := httptest.NewRecorder()
		refuseJoin(rec, c.err)
		var body struct{ Code string }
		json.Unmarshal(rec.Body.Bytes(), &body)
		if rec.Code != c.status || body.Code != c.code {
			t.Errorf("%v: answered %d %q, want %d %q", c.err, rec.Code, body.Code, c.status, c.code)
		}
	}
}
