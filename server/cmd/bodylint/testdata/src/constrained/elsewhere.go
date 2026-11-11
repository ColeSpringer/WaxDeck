//go:build ignore

package constrained

import (
	"io"
	web "net/http"
)

func bounds(w web.ResponseWriter, body io.ReadCloser, h web.Handler, http limits) web.Handler {
	_ = web.MaxBytesReader(w, body, 1)
	_ = web.MaxBytesHandler(h, 1)
	http.MaxBytesReader()
	return h
}

type limits struct{}

func (limits) MaxBytesReader() {}
