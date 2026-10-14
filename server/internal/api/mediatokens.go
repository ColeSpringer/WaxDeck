package api

import (
	"errors"
	"net/http"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// sessionCred is the credential a media token minted for a REST caller
// runs under: it dies with the session.
func sessionCred(p *auth.Principal) string {
	if id := sessionIDOf(p); id != "" {
		return "se:" + id
	}
	return ""
}

// verifiedMedia verifies a media token for want and re-runs its
// mint-time check, answering the request itself on refusal: the two
// steps every media route takes, in one call, so a route cannot take the
// first and forget the second. The enclosure relay alone splits them, to
// count its rate cap before any database read.
func (s *Server) verifiedMedia(w http.ResponseWriter, r *http.Request, token string, want auth.MediaWant) (auth.MediaClaims, *service.UserCtx, bool) {
	claims, err := s.media.Verify(token, want)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "missing, expired, or wrong media token")
		return auth.MediaClaims{}, nil, false
	}
	uc, ok := s.authorizeMediaFor(w, r, claims)
	return claims, uc, ok
}

// authorizeMedia re-runs a verified token's mint-time check, answering
// the request itself on refusal: a token whose account or credential is
// gone is as bad as no token.
func (s *Server) authorizeMedia(w http.ResponseWriter, r *http.Request, c auth.MediaClaims) bool {
	_, ok := s.authorizeMediaFor(w, r, c)
	return ok
}

// authorizeMediaFor is authorizeMedia answering the account the check
// read, for a route that goes on to read as it.
func (s *Server) authorizeMediaFor(w http.ResponseWriter, r *http.Request, c auth.MediaClaims) (*service.UserCtx, bool) {
	uc, err := s.svc.AuthorizeMediaFor(r.Context(), c)
	switch {
	case err == nil:
		return uc, true
	case errors.Is(err, auth.ErrMediaRevoked):
		writeError(w, http.StatusUnauthorized, "unauthenticated", "missing, expired, or wrong media token")
	case service.KindOf(err) == service.KindNotFound:
		writeError(w, http.StatusNotFound, "not-found", "no such item")
	case service.KindOf(err) == service.KindForbidden:
		writeError(w, http.StatusForbidden, "forbidden", kindMessage(err, "not allowed"))
	case service.KindOf(err) == service.KindMaintenance:
		writeMaintenance(w)
	default:
		writeError(w, http.StatusInternalServerError, "internal", "authorizing the media token failed")
	}
	return nil, false
}
