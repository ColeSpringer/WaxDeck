// Package bodylimit stands in for the one package that may call it.
package bodylimit

import (
	"io"
	"net/http"
)

func Reader(w http.ResponseWriter, body io.ReadCloser, limit int64) io.ReadCloser {
	return http.MaxBytesReader(w, body, limit)
}
