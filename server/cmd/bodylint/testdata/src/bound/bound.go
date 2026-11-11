package bound

import (
	"net/http"
	web "net/http"
)

func bounds(w http.ResponseWriter, r *http.Request, h http.Handler) http.Handler {
	r.Body = http.MaxBytesReader(w, r.Body, 1) // want `http.MaxBytesReader: bound a request body with bodylimit.Reader`
	r.Body = web.MaxBytesReader(w, r.Body, 1)  // want `http.MaxBytesReader: bound a request body with bodylimit.Reader`
	return http.MaxBytesHandler(h, 1)          // want `http.MaxBytesHandler: bound a request body with bodylimit.Reader`
}

// Held as a value, it is still the call.
var held = http.MaxBytesReader // want `http.MaxBytesReader: bound a request body with bodylimit.Reader`

type limits struct{}

func (limits) MaxBytesReader() {}

// Another type's MaxBytesReader is not net/http's, and nor is the error
// a handler reads the limit off.
func unrelated(err *http.MaxBytesError) int64 {
	var l limits
	l.MaxBytesReader()
	return err.Limit
}
