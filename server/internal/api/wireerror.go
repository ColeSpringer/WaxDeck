package api

import (
	"encoding/json"
	"net/http"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// wireError is an answer already in the spec's Error schema, which the
// response error handler writes as it stands. Only refuse and
// refusalError build one, so the tests can read every code it carries.
// service.KindOf classes one as internal, so api code classifying a
// handler's error checks for a wireError first, as ResponseErrorHandler
// does.
type wireError struct {
	Status        int
	Code, Message string
	Params        map[string]string
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

// errNoBody refuses a request that came without its body, with a fresh
// refusal each call so no caller can change another's.
func errNoBody() error {
	return refuse(http.StatusBadRequest, "invalid-request", "a request body is required")
}

// refusalError is a refusal coded from the refusal whitelist, which
// degrades a code it does not know to invalid-request.
func refusalError(code, message string) error {
	status, code := refusalStatus(code)
	return &wireError{Status: status, Code: code, Message: message}
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
