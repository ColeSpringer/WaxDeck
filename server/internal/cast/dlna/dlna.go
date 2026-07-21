// Package dlna is the DLNA/UPnP MediaRenderer endpoint: SSDP discovery
// of renderers on the local network, a SOAP control client for the
// AVTransport, RenderingControl, and ConnectionManager services, and a
// connect.Driver that drives one renderer per session. Renderers speak
// no push protocol worth depending on (GENA eventing is deliberately
// skipped; support in the wild is too uneven), so the driver polls
// transport state once a second and synthesizes events from what it
// sees.
package dlna

// Logger is the slice of logging this package needs; callers hand in
// whatever they log through.
type Logger interface {
	Info(string, ...any)
	Warn(string, ...any)
}

// nopLogger stands in when the caller passes no logger.
type nopLogger struct{}

func (nopLogger) Info(string, ...any) {}
func (nopLogger) Warn(string, ...any) {}
