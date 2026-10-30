package subsonic

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// unreadBody fails the test if anything reads it.
type unreadBody struct{ t *testing.T }

func (b unreadBody) Read([]byte) (int, error) {
	b.t.Error("the refused request's body was read")
	return 0, io.EOF
}

// A method the protocol does not use is refused before anything else: no
// body is read and no credential looked at, so a handler with no service
// behind it answers it, in the format the query names.
func TestOtherMethodsAreRefusedFirst(t *testing.T) {
	h := &Handler{version: "test"}
	for _, method := range []string{http.MethodPut, http.MethodDelete, http.MethodPatch, http.MethodOptions, http.MethodTrace} {
		for query, want := range map[string]string{
			"f=json":               `{"subsonic-response":{"status":"failed"`,
			"f=jsonp&callback=cb":  `cb({"subsonic-response":{"status":"failed"`,
			"":                     `<subsonic-response xmlns="http://subsonic.org/restapi" status="failed"`,
			"f=json&u=x&t=y&s=z":   `"error":{"code":0,`,
			"f=json&apiKey=secret": `"error":{"code":0,`,
		} {
			r := httptest.NewRequest(method, "/rest/star.view?id=tr-1&"+query, unreadBody{t})
			r.Header.Set("Content-Type", "application/x-www-form-urlencoded")
			w := httptest.NewRecorder()
			h.ServeHTTP(w, r)
			if w.Code != http.StatusMethodNotAllowed || w.Header().Get("Allow") != "GET, HEAD, POST" ||
				!strings.Contains(w.Body.String(), want) {
				t.Errorf("%s ?%s = %d, Allow %q: %s; want 405 with %s",
					method, query, w.Code, w.Header().Get("Allow"), w.Body.String(), want)
			}
		}
	}
}
