package api

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	"github.com/colespringer/waxdeck/server/internal/connect"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// socketAnswer is what the socket answers err with on a server outside any
// catalog hand-off.
func socketAnswer(err error) (code, message string, params map[string]string) {
	return (&Server{}).wsRefusal(err)
}

// restAnswer is what a connect handler answers err with over REST: the
// refusal the hub words, else the error as it is, through the central
// writer.
func restAnswer(t *testing.T, err error) (int, Error) {
	t.Helper()
	if refusal := connectRefusal(err); refusal != nil {
		err = refusal
	}
	status, body, _ := responseOf(t, err)
	return status, body
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

// Both transports read one table, so a refused command says the same
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
		// The server's own skip past the end of a device queue says it the
		// way a client endpoint does.
		{"the end of a queue is coded", connect.InvalidError{Msg: "already at the end of the queue", Code: "queue-end"}, http.StatusConflict, "queue-end", "already at the end of the queue"},
		{"unknown code degrades", connect.InvalidError{Msg: "the client rejected the command", Code: "wat"}, http.StatusBadRequest, "invalid-request", "the client rejected the command"},
		// A code that is real API vocabulary but describes the request
		// or the transport rather than the refusal: the server says
		// those, an endpoint does not get to.
		{"a client cannot claim the endpoint is offline", connect.InvalidError{Msg: "not downloaded", Code: "endpoint-offline"}, http.StatusBadRequest, "invalid-request", "not downloaded"},
		{"a client cannot claim not-found", connect.InvalidError{Msg: "not downloaded", Code: "not-found"}, http.StatusBadRequest, "invalid-request", "not downloaded"},
		{"uncoded refusal is unchanged", connect.InvalidError{Msg: "seek needs a non-negative positionMs"}, http.StatusBadRequest, "invalid-request", "seek needs a non-negative positionMs"},
		{"a timeout is not an absence", connect.ErrTimeout, http.StatusConflict, "timeout", "the endpoint did not answer in time"},
		{"a busy endpoint is busy", fmt.Errorf("%w: Kitchen speaker", connect.ErrEndpointBusy), http.StatusConflict, "endpoint-busy", "endpoint busy: Kitchen speaker"},
		// An error the hub did not word answers by its kind, in the
		// service's words and never in a wrapped error's text.
		{"a service refusal keeps its words", &service.Error{Kind: service.KindForbidden, Msg: "not yours"}, http.StatusForbidden, "forbidden", "not yours"},
		{"a fault says nothing of itself", &service.Error{Kind: service.KindInternal, Err: errors.New("open /var/lib/waxdeck/catalog.db: permission denied")}, http.StatusInternalServerError, "internal", "internal server error"},
		{"an unclassed failure says nothing of itself", errors.New("sql: no such table: users"), http.StatusInternalServerError, "internal", "internal server error"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if status, body := restAnswer(t, tc.err); status != tc.wantStatus || body.Code != tc.wantCode || body.Message != tc.wantMsg {
				t.Errorf("REST = %d %q %q, want %d %q %q", status, body.Code, body.Message, tc.wantStatus, tc.wantCode, tc.wantMsg)
			}
			if code, message, _ := socketAnswer(tc.err); code != tc.wantCode || message != tc.wantMsg {
				t.Errorf("socket = %q %q, want %q %q", code, message, tc.wantCode, tc.wantMsg)
			}
		})
	}
}

// A refusal's params are detail the code cannot carry, so they have to
// survive both seams intact or the client is back to reading prose.
func TestBothSeamsCarryRefusalParams(t *testing.T) {
	t.Parallel()
	err := connect.InvalidError{
		Msg:    "this track is a window into a larger file and needs the streaming engine to cast: tr-1",
		Code:   "feature-unavailable",
		Params: map[string]string{"feature": "windowed-track", "pid": "tr-1"},
	}

	status, body := restAnswer(t, err)
	if body.Params == nil {
		t.Fatal("REST dropped the refusal's params")
	}
	if got := (*body.Params)["feature"]; got != "windowed-track" {
		t.Errorf("params[feature] = %q, want windowed-track", got)
	}
	if got := (*body.Params)["pid"]; got != "tr-1" {
		t.Errorf("params[pid] = %q, want tr-1", got)
	}

	if _, _, params := socketAnswer(err); params["feature"] != "windowed-track" || params["pid"] != "tr-1" {
		t.Errorf("socket params = %v, want the refusal's", params)
	}

	// The engine away is a wait: the outage's status over REST, the same
	// code and params over the socket. The windowed-track refusal above
	// keeps its 501.
	if status != http.StatusNotImplemented {
		t.Errorf("windowed-track status = %d, want 501", status)
	}
	away := connect.InvalidError{
		Msg:    "this endpoint plays only what the streaming engine renders: tr-1",
		Code:   "feature-unavailable",
		Params: map[string]string{"feature": flow.FeatureStreamingEngine, "pid": "tr-1"},
	}
	if status, body := restAnswer(t, away); status != http.StatusServiceUnavailable ||
		body.Params == nil || (*body.Params)["feature"] != flow.FeatureStreamingEngine {
		t.Errorf("streaming-engine refusal = %d %+v, want 503 naming the engine", status, body)
	}
	if code, _, params := socketAnswer(away); code != "feature-unavailable" ||
		params["feature"] != flow.FeatureStreamingEngine {
		t.Errorf("ws frame = %q %v, want the refusal's code and params", code, params)
	}

	// A code the whitelist rejects loses its params with it: they would
	// otherwise describe a refusal that is not the one being answered.
	rejected := connect.InvalidError{
		Msg:    "the client rejected the command",
		Code:   "wat",
		Params: map[string]string{"feature": "invented-by-the-endpoint"},
	}
	if _, body := restAnswer(t, rejected); body.Code != "invalid-request" || body.Params != nil {
		t.Errorf("REST for %q = (%q, %v), want (invalid-request, no params)", rejected.Code, body.Code, body.Params)
	}
	if _, _, params := socketAnswer(rejected); params != nil {
		t.Errorf("socket params for a rejected code = %v, want nil", params)
	}

	// An uncoded refusal carries none, and the wire omits the field
	// rather than sending an empty object.
	plain := connect.InvalidError{Msg: "seek needs a non-negative positionMs"}
	if _, body := restAnswer(t, plain); body.Params != nil {
		t.Errorf("REST params = %v, want nil", body.Params)
	}
	code, message, params := socketAnswer(plain)
	if params != nil {
		t.Errorf("socket params = %v, want nil", params)
	}
	wire, err2 := json.Marshal(wsErrorFrame{Type: "error", Code: code, Message: message, Params: params})
	if err2 != nil {
		t.Fatalf("marshalling the frame: %v", err2)
	}
	if strings.Contains(string(wire), "params") {
		t.Errorf("frame without params serialized as %s", wire)
	}
}

// Every answer a connect error gets over REST, pinned: the hub's own
// refusals plain and wrapped, a coded refusal over each code with params
// and without, bare or wrapped, and the service kinds it leaves to the
// central writer. Status 0 is an error the hub leaves to the handler,
// which returns it as it is.
func TestConnectAnswersArePinned(t *testing.T) {
	t.Parallel()
	reason := map[string]string{"reason": "x"}
	windowed := map[string]string{"feature": "windowed-track", "pid": "tr-1"}
	engine := map[string]string{"feature": flow.FeatureStreamingEngine, "pid": "tr-1"}
	refused := func(code string, params map[string]string) connect.InvalidError {
		return connect.InvalidError{Msg: "refused", Code: code, Params: params}
	}
	cases := []struct {
		err    error
		status int
		body   string
	}{
		// The hub's own refusals, plain and wrapped.
		{connect.ErrNotFound, http.StatusNotFound, `{"code":"not-found","message":"no such endpoint or session is visible to you"}`},
		{connect.ErrEndpointOffline, http.StatusConflict, `{"code":"endpoint-offline","message":"endpoint offline"}`},
		{connect.ErrEndpointBusy, http.StatusConflict, `{"code":"endpoint-busy","message":"endpoint busy"}`},
		{connect.ErrForbidden, http.StatusForbidden, `{"code":"forbidden","message":"forbidden"}`},
		{connect.ErrTimeout, http.StatusConflict, `{"code":"timeout","message":"the endpoint did not answer in time"}`},
		{fmt.Errorf("%w: Kitchen speaker", connect.ErrNotFound), http.StatusNotFound, `{"code":"not-found","message":"no such endpoint or session is visible to you"}`},
		{fmt.Errorf("%w: Kitchen speaker", connect.ErrEndpointOffline), http.StatusConflict, `{"code":"endpoint-offline","message":"endpoint offline: Kitchen speaker"}`},
		{fmt.Errorf("%w: Kitchen speaker", connect.ErrEndpointBusy), http.StatusConflict, `{"code":"endpoint-busy","message":"endpoint busy: Kitchen speaker"}`},
		{fmt.Errorf("%w: Kitchen speaker", connect.ErrForbidden), http.StatusForbidden, `{"code":"forbidden","message":"forbidden: Kitchen speaker"}`},
		{fmt.Errorf("%w: Kitchen speaker", connect.ErrTimeout), http.StatusConflict, `{"code":"timeout","message":"the endpoint did not answer in time"}`},
		// Errors it leaves to the handler.
		{errors.New("sql: no such table"), 0, ""},
		{&service.Error{Kind: service.KindInvalid, Msg: "bad pid"}, 0, ""},
		{&service.Error{Kind: service.KindForbidden, Msg: "not yours"}, 0, ""},
		// A coded refusal over each code, without params and with.
		{refused("", nil), http.StatusBadRequest, `{"code":"invalid-request","message":"refused"}`},
		{refused("", reason), http.StatusBadRequest, `{"code":"invalid-request","message":"refused"}`},
		{refused("invalid-request", nil), http.StatusBadRequest, `{"code":"invalid-request","message":"refused"}`},
		{refused("invalid-request", reason), http.StatusBadRequest, `{"code":"invalid-request","message":"refused","params":{"reason":"x"}}`},
		{refused("conflict", nil), http.StatusConflict, `{"code":"conflict","message":"refused"}`},
		{refused("conflict", reason), http.StatusConflict, `{"code":"conflict","message":"refused","params":{"reason":"x"}}`},
		{refused("feature-unavailable", nil), http.StatusNotImplemented, `{"code":"feature-unavailable","message":"refused"}`},
		{refused("feature-unavailable", reason), http.StatusNotImplemented, `{"code":"feature-unavailable","message":"refused","params":{"reason":"x"}}`},
		{refused("endpoint-failed", nil), http.StatusConflict, `{"code":"endpoint-failed","message":"refused"}`},
		{refused("endpoint-failed", reason), http.StatusConflict, `{"code":"endpoint-failed","message":"refused","params":{"reason":"x"}}`},
		{refused("endpoint-idle", nil), http.StatusConflict, `{"code":"endpoint-idle","message":"refused"}`},
		{refused("endpoint-idle", reason), http.StatusConflict, `{"code":"endpoint-idle","message":"refused","params":{"reason":"x"}}`},
		{refused("no-session", nil), http.StatusConflict, `{"code":"no-session","message":"refused"}`},
		{refused("no-session", reason), http.StatusConflict, `{"code":"no-session","message":"refused","params":{"reason":"x"}}`},
		{refused("queue-end", nil), http.StatusConflict, `{"code":"queue-end","message":"refused"}`},
		{refused("queue-end", reason), http.StatusConflict, `{"code":"queue-end","message":"refused","params":{"reason":"x"}}`},
		{refused("queue-start", nil), http.StatusConflict, `{"code":"queue-start","message":"refused"}`},
		{refused("queue-start", reason), http.StatusConflict, `{"code":"queue-start","message":"refused","params":{"reason":"x"}}`},
		{refused("wat", nil), http.StatusBadRequest, `{"code":"invalid-request","message":"refused"}`},
		{refused("wat", reason), http.StatusBadRequest, `{"code":"invalid-request","message":"refused"}`},
		{refused("internal", nil), http.StatusBadRequest, `{"code":"invalid-request","message":"refused"}`},
		{refused("internal", reason), http.StatusBadRequest, `{"code":"invalid-request","message":"refused"}`},
		{refused("not-found", nil), http.StatusBadRequest, `{"code":"invalid-request","message":"refused"}`},
		{refused("not-found", reason), http.StatusBadRequest, `{"code":"invalid-request","message":"refused"}`},
		{refused("forbidden", nil), http.StatusBadRequest, `{"code":"invalid-request","message":"refused"}`},
		{refused("forbidden", reason), http.StatusBadRequest, `{"code":"invalid-request","message":"refused"}`},
		{refused("timeout", nil), http.StatusBadRequest, `{"code":"invalid-request","message":"refused"}`},
		{refused("timeout", reason), http.StatusBadRequest, `{"code":"invalid-request","message":"refused"}`},
		{refused("endpoint-offline", nil), http.StatusBadRequest, `{"code":"invalid-request","message":"refused"}`},
		{refused("endpoint-offline", reason), http.StatusBadRequest, `{"code":"invalid-request","message":"refused"}`},
		{refused("endpoint-busy", nil), http.StatusBadRequest, `{"code":"invalid-request","message":"refused"}`},
		{refused("endpoint-busy", reason), http.StatusBadRequest, `{"code":"invalid-request","message":"refused"}`},
		// Empty params, another feature, the engine away, and its params on
		// other codes.
		{refused("conflict", map[string]string{}), http.StatusConflict, `{"code":"conflict","message":"refused"}`},
		{refused("feature-unavailable", windowed), http.StatusNotImplemented, `{"code":"feature-unavailable","message":"refused","params":{"feature":"windowed-track","pid":"tr-1"}}`},
		{refused("feature-unavailable", engine), http.StatusServiceUnavailable, `{"code":"feature-unavailable","message":"refused","params":{"feature":"streaming-engine","pid":"tr-1"}}`},
		{refused("conflict", engine), http.StatusConflict, `{"code":"conflict","message":"refused","params":{"feature":"streaming-engine","pid":"tr-1"}}`},
		{refused("wat", engine), http.StatusBadRequest, `{"code":"invalid-request","message":"refused"}`},
		{refused("", engine), http.StatusBadRequest, `{"code":"invalid-request","message":"refused"}`},
		{refused("endpoint-offline", engine), http.StatusBadRequest, `{"code":"invalid-request","message":"refused"}`},
		// The first arm that matches answers.
		{fmt.Errorf("%w: %w", connect.ErrTimeout, refused("feature-unavailable", engine)), http.StatusConflict, `{"code":"timeout","message":"the endpoint did not answer in time"}`},
		{fmt.Errorf("%w: %w", &service.Error{Kind: service.KindConflict, Msg: "a merge is running"}, refused("queue-end", nil)), http.StatusConflict, `{"code":"queue-end","message":"refused"}`},
	}
	for _, tc := range cases {
		errs := []error{tc.err}
		if _, bare := tc.err.(connect.InvalidError); bare {
			// The refusal's own words, not the wrapping's.
			errs = append(errs, fmt.Errorf("relayed: %w", tc.err))
		}
		for _, err := range errs {
			refusal := connectRefusal(err)
			if tc.status == 0 {
				if refusal != nil {
					t.Errorf("%#v: worded as %v, want it left to the handler", err, refusal)
				}
				continue
			}
			rec := httptest.NewRecorder()
			responseError(rec, refusal)
			if got := strings.TrimSuffix(rec.Body.String(), "\n"); rec.Code != tc.status || got != tc.body {
				t.Errorf("%#v: the refusal answers %d %s, want %d %s", err, rec.Code, got, tc.status, tc.body)
			}
			// The outage alone says when to ask again.
			wantRetry := ""
			if tc.status == http.StatusServiceUnavailable {
				wantRetry = strconv.Itoa(flow.EngineRetrySeconds)
			}
			if got := rec.Header().Get("Retry-After"); got != wantRetry {
				t.Errorf("%#v: Retry-After %q, want %q", err, got, wantRetry)
			}
		}
	}

	// A kind the hub does not word is returned as it is, and the central
	// writer answers it: the service's Msg, else the kind's fallback, with
	// the error's params.
	kinds := []struct {
		err    error
		status int
		body   string
	}{
		{&service.Error{Kind: service.KindNotFound, Msg: "no such queue entry"}, http.StatusNotFound, `{"code":"not-found","message":"no such queue entry"}`},
		{&service.Error{Kind: service.KindNotFound}, http.StatusNotFound, `{"code":"not-found","message":"not found"}`},
		{fmt.Errorf("resolving: %w", &service.Error{Kind: service.KindNotFound, Msg: "no such queue entry"}), http.StatusNotFound, `{"code":"not-found","message":"no such queue entry"}`},
		{&service.Error{Kind: service.KindConflict, Msg: "a merge is running", Params: reason}, http.StatusConflict, `{"code":"conflict","message":"a merge is running","params":{"reason":"x"}}`},
	}
	for _, tc := range kinds {
		if refusal := connectRefusal(tc.err); refusal != nil {
			t.Errorf("%#v: the hub worded it %v, want it left to the handler", tc.err, refusal)
			continue
		}
		rec := httptest.NewRecorder()
		responseError(rec, tc.err)
		if got := strings.TrimSuffix(rec.Body.String(), "\n"); rec.Code != tc.status || got != tc.body {
			t.Errorf("%#v: the central writer answers %d %s, want %d %s", tc.err, rec.Code, got, tc.status, tc.body)
		}
	}
}
