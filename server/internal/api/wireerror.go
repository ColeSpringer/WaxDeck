package api

import (
	"encoding/json"
	"errors"
	"maps"
	"net/http"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// wireError is an answer already in the spec's Error schema, which the
// response error handler writes as it stands. Only refuse, refuseParams
// and refusalErrorParams build a refusal, and answerByKind and
// maintenanceAnswer an answer from the kind table, so the tests can read
// every code one carries.
// service.KindOf classes one as internal, so api code classifying a
// handler's error checks for a wireError first, as ResponseErrorHandler
// does.
type wireError struct {
	Status        int
	Code, Message string
	Params        map[string]string
	// RetryAfter is the Retry-After header's seconds; 0 sends none.
	RetryAfter int
}

func (e *wireError) Error() string { return e.Message }

// writeErrorParams writes the spec's Error schema, with params only when
// there are some. A status outside 400-599 is the caller's bug, and
// answers 500 internal rather than reaching WriteHeader.
func writeErrorParams(w http.ResponseWriter, status int, code, message string, params map[string]string) {
	if status < 400 || status > 599 {
		c := kindCodes[service.KindInternal]
		status, code, message, params = c.status, c.code, c.fallback, nil
	}
	body := Error{Code: code, Message: message}
	if len(params) > 0 {
		body.Params = &params
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

// refuse is a handler's refusal, answered with status and code as given.
func refuse(status int, code, message string) error {
	return &wireError{Status: status, Code: code, Message: message}
}

// refuseParams is refuse carrying the params a client words the refusal
// with. A nil or empty map sends none. It keeps the caller's map, not a
// copy: callers build a fresh one per call.
func refuseParams(status int, code, message string, params map[string]string) error {
	return &wireError{Status: status, Code: code, Message: message, Params: params}
}

// errNoBody refuses a request that came without its body, with a fresh
// refusal each call so no caller can change another's.
func errNoBody() error {
	return refuse(http.StatusBadRequest, "invalid-request", "a request body is required")
}

// refuseEngineAway refuses what only the configured streaming engine serves
// while it is away: the outage's 503 naming the engine beside any params
// of the caller's, and when to ask again.
func refuseEngineAway(message string, extra map[string]string) error {
	params := maps.Clone(extra)
	if params == nil {
		params = map[string]string{}
	}
	params["feature"] = flow.FeatureStreamingEngine
	refusal := refuseParams(http.StatusServiceUnavailable, "feature-unavailable", message, params).(*wireError)
	refusal.RetryAfter = flow.EngineRetrySeconds
	return refusal
}

// refusalErrorParams is a refusal coded from the refusal whitelist, which
// degrades a code it does not know to invalid-request, carrying params
// only where the code survived it.
func refusalErrorParams(code, message string, params map[string]string) error {
	status, resolved := refusalStatus(code)
	return &wireError{Status: status, Code: resolved, Message: message, Params: keptParams(code, params)}
}

// kindCodes is how each service kind answers: its status, its code, and
// the words it says when the error carries none of its own.
var kindCodes = map[service.ErrorKind]struct {
	status   int
	code     string
	fallback string
}{
	service.KindMaintenance:       {http.StatusServiceUnavailable, "catalog-maintenance", "the catalog is temporarily under maintenance; retry shortly"},
	service.KindNotFound:          {http.StatusNotFound, "not-found", "not found"},
	service.KindInvalid:           {http.StatusBadRequest, "invalid-request", "invalid request"},
	service.KindConflict:          {http.StatusConflict, "conflict", "a conflicting operation is running"},
	service.KindCatalogBusy:       {http.StatusConflict, "catalog-busy", "another catalog job holds the file-mutation scope; retry shortly"},
	service.KindGone:              {http.StatusGone, "sync-reset", "re-mirror from a fresh snapshot"},
	service.KindForbidden:         {http.StatusForbidden, "forbidden", "not allowed"},
	service.KindUnsupported:       {http.StatusNotImplemented, "source-unavailable", "this server is not running the needed integration"},
	service.KindUpstream:          {http.StatusBadGateway, "feed-unreachable", "the upstream feed could not be fetched"},
	service.KindDirectory:         {http.StatusBadGateway, "directory-unavailable", "the external directory could not be reached"},
	service.KindService:           {http.StatusBadGateway, "service-unreachable", "an external service could not be reached"},
	service.KindQuota:             {http.StatusRequestEntityTooLarge, "quota-exceeded", "the upload would exceed your storage quota"},
	service.KindStorageFull:       {http.StatusInsufficientStorage, "storage-full", "the server has no room to stage this"},
	service.KindLocked:            {http.StatusConflict, "field-locked", "the field is locked; pass force to override"},
	service.KindFormat:            {http.StatusUnsupportedMediaType, "unsupported-format", "the file's format is not accepted"},
	service.KindDRM:               {http.StatusUnsupportedMediaType, "drm-protected", "the file is DRM-encrypted and can never play"},
	service.KindFeature:           {http.StatusNotImplemented, "feature-unavailable", "this server is not running the needed capability"},
	service.KindReadOnly:          {http.StatusConflict, "read-only", "the server or the target library is read-only"},
	service.KindStorageUnwritable: {http.StatusConflict, "storage-unwritable", "a library folder refused the write"},
	service.KindTranscodeLimit:    {http.StatusTooManyRequests, "transcode-limited", "the transcode session limit is reached"},
	service.KindInternal:          {http.StatusInternalServerError, "internal", "internal server error"},
	service.KindUnauthenticated:   {http.StatusUnauthorized, "unauthenticated", "no valid session or token was presented"},
}

// answerTo is how a client meets err on any transport: a refusal as it
// stands, anything else by its kind.
func answerTo(err error) *wireError {
	var refusal *wireError
	if errors.As(err, &refusal) {
		return refusal
	}
	return answerByKind(err)
}

// answerByKind is the answer an error that is not a refusal gets: its
// kind's status and code, the service's own Msg else the kind's fallback,
// and the error's params. A maintenance error, and a kind the table does
// not know (which answers as internal), say the fallback alone.
func answerByKind(err error) *wireError {
	kind := service.KindOf(err)
	c, known := kindCodes[kind]
	switch {
	case !known:
		c = kindCodes[service.KindInternal]
		return &wireError{Status: c.status, Code: c.code, Message: c.fallback}
	case kind == service.KindMaintenance:
		return maintenanceAnswer()
	}
	return &wireError{Status: c.status, Code: c.code, Message: kindMessage(err, c.fallback), Params: service.RefusalParams(err)}
}

// maintenanceAnswer is what a request meets while the catalog is in
// maintenance.
func maintenanceAnswer() *wireError {
	c := kindCodes[service.KindMaintenance]
	return &wireError{Status: c.status, Code: c.code, Message: c.fallback}
}

// serviceMessage is the words a service error answers with, under any
// status a handler gives it: answerByKind's, never a wrapped error's raw
// text, which may name internals.
func serviceMessage(err error) string {
	return answerByKind(err).Message
}

// ownWords is the text of an error that is not a service error where that
// text is the answer: the connect hub's sentinels and the detail it wraps
// them with, the streaming bridge's refusals, the OIDC exchange's
// diagnostic, a cast preflight's failed self-fetch. Every other error is
// worded by serviceMessage, and so is a service error handed here.
func ownWords(err error) string {
	var se *service.Error
	if errors.As(err, &se) {
		return serviceMessage(err)
	}
	return err.Error()
}
