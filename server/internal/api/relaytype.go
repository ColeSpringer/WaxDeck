package api

import (
	"strings"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// relayedType is the gate both relays hold a host's Content-Type to. A
// type naming audio or video (RelayableMediaType) passes, lowercased with
// its parameters dropped; no type, or octet-stream alone, passes untyped
// for the relay to name; anything else (a page, a document, a picture, a
// playlist, a multipart stream, a list of types) never goes out from
// this origin.
func relayedType(upstream string) (mediaType string, untyped, ok bool) {
	if mediaType, ok := service.RelayableMediaType(upstream); ok {
		return mediaType, false, true
	}
	switch base, _, _ := strings.Cut(strings.ToLower(upstream), ";"); strings.TrimSpace(base) {
	case "", "application/octet-stream", "binary/octet-stream":
		return "", true, true
	}
	return "", false, false
}
