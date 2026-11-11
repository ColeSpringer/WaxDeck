// Package bodylimit bounds a request body so that the server stops
// reading where the bound falls. It exists because http.MaxBytesReader
// tells the server a body ran past its limit only through the writer
// net/http itself made, and every surface here answers through writers
// that wrap it. Handed a wrapper it still fails the read at the limit,
// but the server, told nothing, reads a further 256 KB of the refused
// body before it sends the refusal.
package bodylimit

import (
	"io"
	"net/http"

	"github.com/colespringer/waxdeck/server/internal/respwriter"
)

// Reader is http.MaxBytesReader over the server's own writer, found under
// whatever wraps w. A wrapper with no Unwrap hides it, and the body is
// bounded as MaxBytesReader bounds it behind any other writer.
func Reader(w http.ResponseWriter, body io.ReadCloser, limit int64) io.ReadCloser {
	return http.MaxBytesReader(respwriter.Server(w), body, limit)
}
