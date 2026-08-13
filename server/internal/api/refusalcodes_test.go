package api

import (
	"encoding/json"
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
	t.Parallel()
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
	t.Parallel()
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
	t.Parallel()
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
			status, body, ok := connectHTTP(tc.err)
			if !ok {
				t.Fatalf("connectHTTP did not recognize %v", tc.err)
			}
			if status != tc.wantStatus || body.Code != tc.wantCode {
				t.Errorf("connectHTTP = (%d, %q), want (%d, %q)", status, body.Code, tc.wantStatus, tc.wantCode)
			}
			if body.Message != tc.wantMsg {
				t.Errorf("connectHTTP message = %q, want %q", body.Message, tc.wantMsg)
			}
			if got := wsErrorCode(tc.err); got != tc.wantCode {
				t.Errorf("wsErrorCode = %q, want %q", got, tc.wantCode)
			}
		})
	}
}

// A refusal's params are detail the code cannot carry, so they have to
// survive both seams intact or the client is back to reading prose.
func TestBothSeamsCarryRefusalParams(t *testing.T) {
	t.Parallel()
	err := connect.InvalidError{
		Msg:    "multi-part audiobooks cannot play on this endpoint yet: bk-1",
		Code:   "feature-unavailable",
		Params: map[string]string{"feature": "multi-part-audiobook", "pid": "bk-1"},
	}

	_, body, ok := connectHTTP(err)
	if !ok {
		t.Fatalf("connectHTTP did not recognize %v", err)
	}
	if body.Params == nil {
		t.Fatal("connectHTTP dropped the refusal's params")
	}
	if got := (*body.Params)["feature"]; got != "multi-part-audiobook" {
		t.Errorf("params[feature] = %q, want multi-part-audiobook", got)
	}
	if got := (*body.Params)["pid"]; got != "bk-1" {
		t.Errorf("params[pid] = %q, want bk-1", got)
	}

	frame := wsErrorFrame{Code: wsErrorCode(err), Message: err.Error(), Params: refusalParams(err)}
	if frame.Params["feature"] != "multi-part-audiobook" || frame.Params["pid"] != "bk-1" {
		t.Errorf("ws frame params = %v, want the refusal's", frame.Params)
	}

	// A code the whitelist rejects loses its params with it: they would
	// otherwise describe a refusal that is not the one being answered.
	rejected := connect.InvalidError{
		Msg:    "the client rejected the command",
		Code:   "wat",
		Params: map[string]string{"feature": "invented-by-the-endpoint"},
	}
	if _, body, ok := connectHTTP(rejected); !ok || body.Code != "invalid-request" || body.Params != nil {
		t.Errorf("connectHTTP(%q) = (%q, %v), want (invalid-request, no params)", rejected.Code, body.Code, body.Params)
	}
	if got := refusalParams(rejected); got != nil {
		t.Errorf("refusalParams for a rejected code = %v, want nil", got)
	}

	// An uncoded refusal carries none, and the wire omits the field
	// rather than sending an empty object.
	plain := connect.InvalidError{Msg: "seek needs a non-negative positionMs"}
	if _, body, ok := connectHTTP(plain); !ok || body.Params != nil {
		t.Errorf("connectHTTP params = %v, want nil", body.Params)
	}
	if got := refusalParams(plain); got != nil {
		t.Errorf("refusalParams = %v, want nil", got)
	}
	wire, err2 := json.Marshal(wsErrorFrame{Type: "error", Code: "invalid-request", Message: plain.Msg, Params: refusalParams(plain)})
	if err2 != nil {
		t.Fatalf("marshalling the frame: %v", err2)
	}
	if strings.Contains(string(wire), "params") {
		t.Errorf("frame without params serialized as %s", wire)
	}
}
