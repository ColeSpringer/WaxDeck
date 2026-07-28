package api

import "net/http"

// refusalCodes is the vocabulary a refused player command may carry
// out to a controller, mapped onto the HTTP status each code answers
// with. Both transports read it: the REST handlers for their typed
// responses, and the command socket for its error frame.
//
// It is a whitelist on purpose, and a short one. The code on a routed
// refusal arrives from a client endpoint, which is free to send
// anything; a code reaching the wire is the server saying it, and
// CLAUDE.md forbids handlers minting codes the contract does not
// document. Anything not listed here degrades to `invalid-request` and
// keeps its message, which is what every refusal used to be.
//
// Only the codes that say something about the *refusal* are here.
// `not-found`, `forbidden`, `endpoint-offline`, and `timeout` describe
// the request or the transport, and at these endpoints they are the
// server's to say, not the endpoint's: a client that answers
// `not-found` because it has not downloaded a track would tell the
// controller the endpoint or the item does not exist, and one that
// answers `endpoint-offline` would send it to refresh a list the
// endpoint is still online in — which is a loop, not a fix. Those
// arrive as `invalid-request` carrying the client's own message.
//
// Unexported and never written after init: both readers are in this
// package, and a package-level map that anything could write is a data
// race waiting for the first goroutine that tries.
//
// Every key must appear in the spec's documented code list;
// refusalcodes_test.go fails the build if one drifts out of it.
var refusalCodes = map[string]int{
	"invalid-request":     http.StatusBadRequest,
	"conflict":            http.StatusConflict,
	"feature-unavailable": http.StatusNotImplemented,
}

// refusalStatus resolves a refusal's code onto the status it answers
// with, degrading an unrecognized or absent one to `invalid-request`.
func refusalStatus(code string) (int, string) {
	if status, ok := refusalCodes[code]; ok {
		return status, code
	}
	return http.StatusBadRequest, "invalid-request"
}
