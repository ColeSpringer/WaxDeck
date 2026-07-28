package api

import (
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/connect"
)

// The error vocabulary lives as prose in the spec preamble rather than
// as a schema enum, so nothing structural catches refusalCodes drifting
// out of it. This does, in the one direction that matters: a code the
// server can put on the wire that the contract never documented.
//
// Against the authored fragment, not the generated bundle, so a code
// deleted from the vocabulary fails here rather than passing on a stale
// bundle. And against the code list alone rather than the whole
// document: every one of these words also appears in ordinary prose
// somewhere in the spec, so a whole-file substring search would pass
// for a code nobody had defined.
func TestRefusalCodesAreDocumented(t *testing.T) {
	path := filepath.Join("..", "..", "..", "api", "spec", "_root.yaml")
	spec, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading the spec preamble: %v", err)
	}
	const (
		opens  = "currently defined codes:"
		closes = "New codes may appear"
	)
	_, after, found := strings.Cut(string(spec), opens)
	if !found {
		t.Fatalf("%s no longer says %q; this guard is reading the wrong thing", path, opens)
	}
	list, _, found := strings.Cut(after, closes)
	if !found {
		t.Fatalf("%s no longer says %q; this guard is reading the wrong thing", path, closes)
	}
	for code := range refusalCodes {
		if !strings.Contains(list, "`"+code+"`") {
			t.Errorf("refusal code %q is not in the documented code list in %s; add it there or drop it from refusalCodes", code, path)
		}
	}
}

func TestRefusalStatusWhitelistsCodes(t *testing.T) {
	for code, want := range refusalCodes {
		status, got := refusalStatus(code)
		if got != code || status != want {
			t.Errorf("refusalStatus(%q) = (%d, %q), want (%d, %q)", code, status, got, want, code)
		}
	}
	// A client endpoint is free to answer anything; only the documented
	// vocabulary reaches the wire, and the message survives either way.
	for _, code := range []string{"", "banana", "Not-Found", "internal-oops"} {
		status, got := refusalStatus(code)
		if got != "invalid-request" || status != http.StatusBadRequest {
			t.Errorf("refusalStatus(%q) = (%d, %q), want (400, invalid-request)", code, status, got)
		}
	}
}

// Both transports read one table, so a coded refusal says the same
// thing whether the controller asked over REST or over the socket.
func TestBothSeamsCarryRefusalCodes(t *testing.T) {
	cases := []struct {
		name       string
		err        error
		wantStatus int
		wantCode   string
		wantMsg    string
	}{
		{"recognized code rides through", connect.InvalidError{Msg: "no books here", Code: "feature-unavailable"}, http.StatusNotImplemented, "feature-unavailable", "no books here"},
		{"conflict keeps its status", connect.InvalidError{Msg: "busy", Code: "conflict"}, http.StatusConflict, "conflict", "busy"},
		{"unknown code degrades", connect.InvalidError{Msg: "the client rejected the command", Code: "wat"}, http.StatusBadRequest, "invalid-request", "the client rejected the command"},
		// A code that is real API vocabulary but describes the request
		// or the transport rather than the refusal: the server says
		// those, an endpoint does not get to.
		{"a client cannot claim the endpoint is offline", connect.InvalidError{Msg: "not downloaded", Code: "endpoint-offline"}, http.StatusBadRequest, "invalid-request", "not downloaded"},
		{"a client cannot claim not-found", connect.InvalidError{Msg: "not downloaded", Code: "not-found"}, http.StatusBadRequest, "invalid-request", "not downloaded"},
		{"uncoded refusal is unchanged", connect.InvalidError{Msg: "seek needs a non-negative positionMs"}, http.StatusBadRequest, "invalid-request", "seek needs a non-negative positionMs"},
		{"a timeout is not an absence", connect.ErrTimeout, http.StatusConflict, "timeout", "the endpoint did not answer in time"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			status, code, msg, ok := connectHTTP(tc.err)
			if !ok {
				t.Fatalf("connectHTTP did not recognize %v", tc.err)
			}
			if status != tc.wantStatus || code != tc.wantCode {
				t.Errorf("connectHTTP = (%d, %q), want (%d, %q)", status, code, tc.wantStatus, tc.wantCode)
			}
			if msg != tc.wantMsg {
				t.Errorf("connectHTTP message = %q, want %q", msg, tc.wantMsg)
			}
			if got := wsErrorCode(tc.err); got != tc.wantCode {
				t.Errorf("wsErrorCode = %q, want %q", got, tc.wantCode)
			}
		})
	}
}
