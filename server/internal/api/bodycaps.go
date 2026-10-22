package api

import "net/http"

// opmlImportMaxBytes caps an OPML import's request body, which the
// generated binder reads whole before the handler runs.
const opmlImportMaxBytes = 4 << 20

// capRequestBody bounds the request bodies the binder would otherwise
// read without limit; past the cap the binder answers invalid-request.
func capRequestBody(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodPost && r.URL.Path == "/api/v1/podcasts/opml" {
		r.Body = http.MaxBytesReader(w, r.Body, opmlImportMaxBytes)
	}
}
