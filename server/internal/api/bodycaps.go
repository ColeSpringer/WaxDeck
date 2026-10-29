package api

import (
	"fmt"
	"net/http"
)

// opmlImportMaxBytes caps an OPML import's request body, which the
// generated binder reads whole before the handler runs.
const opmlImportMaxBytes = 4 << 20

// jsonBodyMaxBytes caps every other request body the binder decodes. The
// largest one the contract's field limits allow is a genre tree at its
// limits, 2000 genres each with a 128-character name and parent and 64
// aliases of 128 (about 17.4 MB written plainly); next is an M3U document
// of 1,048,576 characters in JSON's costliest escape, a 12-byte surrogate
// pair each (about 12.6 MB).
const jsonBodyMaxBytes = 24 << 20

// rawBodies are the operations whose body is not JSON (an upload's bytes,
// an archive, an export, an image), each of which bounds its own.
var rawBodies = func() *http.ServeMux {
	mux := http.NewServeMux()
	for _, pattern := range []string{
		"POST /api/v1/admin/backups/import",
		"POST /api/v1/admin/migrations/exports",
		"PUT /api/v1/items/{pid}/artwork",
		"PUT /api/v1/entities/{entityType}/{entityPid}/artwork",
		"PUT /api/v1/uploads/{uploadId}/data",
	} {
		mux.Handle(pattern, http.NotFoundHandler())
	}
	return mux
}()

// rawBody reports whether r is one of those operations.
func rawBody(r *http.Request) bool {
	_, pattern := rawBodies.Handler(r)
	return pattern != ""
}

// capRequestBody bounds the request bodies the binder would otherwise
// read without limit: past the cap the binder answers invalid-request. A
// body that declares more is refused before any of it is read, in which
// case capRequestBody has answered and reports false.
func capRequestBody(w http.ResponseWriter, r *http.Request) bool {
	if rawBody(r) {
		return true
	}
	limit := int64(jsonBodyMaxBytes)
	if r.Method == http.MethodPost && r.URL.Path == "/api/v1/podcasts/opml" {
		limit = opmlImportMaxBytes
	}
	if r.ContentLength > limit {
		writeError(w, http.StatusBadRequest, "invalid-request", bodyTooLarge(limit))
		return false
	}
	r.Body = http.MaxBytesReader(w, r.Body, limit)
	return true
}

// bodyTooLarge is the refusal of a request body past its cap.
func bodyTooLarge(limit int64) string {
	return fmt.Sprintf("the request body is too large: it may be at most %d bytes", limit)
}
