// Package notify holds the outbound notification providers: native
// Pushover, ntfy, Gotify, Discord-webhook, and generic-webhook
// deliveries, the Apprise relay, and UnifiedPush posts. The service
// layer owns targets, scoping, and queueing; this package only
// validates per-kind configuration and speaks the wire protocols.
package notify

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

// Target kinds on the wire and in storage.
const (
	KindPushover    = "pushover"
	KindNtfy        = "ntfy"
	KindGotify      = "gotify"
	KindDiscord     = "discord"
	KindWebhook     = "webhook"
	KindApprise     = "apprise"
	KindUnifiedPush = "unifiedpush"
)

// Message is one notification to deliver.
type Message struct {
	Event string
	Title string
	Body  string
	// Timestamp is the delivery instant, carried by payloads that
	// include one (the generic webhook).
	Timestamp time.Time
	// Link is where the news is, as an absolute URL into this server's
	// web app. Empty when the server has no public base configured, or
	// when the event names nothing to open: providers that can carry a
	// link omit it rather than sending a URL nobody can follow.
	Link string
}

// Provider validates one kind's configuration and delivers messages
// to it.
type Provider interface {
	Kind() string
	// ValidateConfig checks and canonicalizes a config document.
	// Unknown fields are refused. userHost is the user-pointed host a
	// write-time private-address check applies to; empty means the
	// kind needs no such check (fixed or allowlisted hosts, or a
	// deliberately unguarded transport).
	ValidateConfig(raw json.RawMessage) (normalized json.RawMessage, userHost string, err error)
	// Deliver posts one message using a previously normalized config.
	Deliver(ctx context.Context, client *http.Client, config json.RawMessage, msg Message) error
}

// registry lists every provider by kind; explicit, no init magic.
var registry = map[string]Provider{
	KindPushover:    pushoverProvider{},
	KindNtfy:        ntfyProvider{},
	KindGotify:      gotifyProvider{},
	KindDiscord:     discordProvider{},
	KindWebhook:     webhookProvider{},
	KindApprise:     appriseProvider{},
	KindUnifiedPush: unifiedPushProvider{},
}

// ByKind resolves a provider.
func ByKind(kind string) (Provider, bool) {
	p, ok := registry[kind]
	return p, ok
}

// Permanent marks a delivery the destination itself rejected: retrying
// the same submission cannot succeed (a revoked token, a deleted
// webhook). Transport failures and throttling stay plain errors, which
// callers retry.
type Permanent struct{ Err error }

func (p *Permanent) Error() string { return "permanent: " + p.Err.Error() }
func (p *Permanent) Unwrap() error { return p.Err }

// IsPermanent reports whether err marks an unretryable rejection.
func IsPermanent(err error) bool {
	var p *Permanent
	return errors.As(err, &p)
}

// Throttled marks a delivery the destination asked us to slow down on,
// with the wait it named. Retryable like any other transient failure;
// the caller uses RetryAfter instead of its own backoff when the
// service's number is the larger one.
type Throttled struct {
	Err        error
	RetryAfter time.Duration
}

func (t *Throttled) Error() string { return t.Err.Error() }
func (t *Throttled) Unwrap() error { return t.Err }

// RetryAfterOf reports the wait a destination asked for, or zero.
func RetryAfterOf(err error) time.Duration {
	var t *Throttled
	if errors.As(err, &t) {
		return t.RetryAfter
	}
	return 0
}

// retryAfter reads the header in either documented form: a count of
// seconds, or an HTTP date. A date already past means "now", not a
// negative wait.
func retryAfter(h http.Header, now time.Time) (time.Duration, bool) {
	raw := strings.TrimSpace(h.Get("Retry-After"))
	if raw == "" {
		return 0, false
	}
	if secs, err := strconv.Atoi(raw); err == nil {
		if secs < 0 {
			return 0, true
		}
		return time.Duration(secs) * time.Second, true
	}
	when, err := http.ParseTime(raw)
	if err != nil {
		return 0, false
	}
	if wait := when.Sub(now); wait > 0 {
		return wait, true
	}
	return 0, true
}

// send posts one request and classifies the response. Response bodies
// are discarded, never surfaced: the errors land on the target's
// health fields, and destinations of user-pointed kinds (UnifiedPush
// especially, whose endpoints are deliberately unguarded) must not
// become a response-content oracle; delivery reachability is granted,
// response read-back is not. Definite 4xx answers (everything but
// timeout and throttling) are permanent: the destination understood
// the request and said no.
func send(client *http.Client, req *http.Request) error {
	return deliverRequest(client, req, false)
}

// sendDetailed is send for the pinned-host kinds (Pushover, Discord):
// the response can only come from the service itself, so its own error
// text (a revoked token, a malformed embed) rides the returned error
// onto the health fields, where a bare status code would leave the
// owner guessing.
func sendDetailed(client *http.Client, req *http.Request) error {
	return deliverRequest(client, req, true)
}

func deliverRequest(client *http.Client, req *http.Request, detail bool) error {
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 200 && resp.StatusCode <= 299 {
		io.Copy(io.Discard, io.LimitReader(resp.Body, 256))
		return nil
	}
	msg := fmt.Sprintf("delivery answered status %d", resp.StatusCode)
	if detail {
		if snippet := errorSnippet(resp.Body); snippet != "" {
			msg += ": " + snippet
		}
	} else {
		io.Copy(io.Discard, io.LimitReader(resp.Body, 256))
	}
	failure := errors.New(msg)
	switch {
	case resp.StatusCode == http.StatusTooManyRequests ||
		resp.StatusCode == http.StatusServiceUnavailable:
		// The two statuses that mean "come back later" and are allowed
		// to say when. Without a parseable header they stay ordinary
		// retryable failures on the generic ramp.
		if wait, ok := retryAfter(resp.Header, time.Now()); ok {
			return &Throttled{Err: failure, RetryAfter: wait}
		}
		return failure
	case resp.StatusCode == http.StatusRequestTimeout:
		return failure
	case resp.StatusCode >= 400 && resp.StatusCode <= 499:
		return &Permanent{Err: failure}
	default:
		return failure
	}
}

// errorSnippet distills an error response body into one short line.
// Known JSON error shapes surface their message fields (Pushover's
// errors array, Discord's message); anything else is used as text.
func errorSnippet(r io.Reader) string {
	raw, err := io.ReadAll(io.LimitReader(r, 256))
	if err != nil || len(raw) == 0 {
		return ""
	}
	text := string(raw)
	var doc map[string]any
	if json.Unmarshal(raw, &doc) == nil {
		switch {
		case len(anyStrings(doc["errors"])) > 0:
			text = strings.Join(anyStrings(doc["errors"]), ", ")
		case stringField(doc, "message") != "":
			text = stringField(doc, "message")
		case stringField(doc, "error") != "":
			text = stringField(doc, "error")
		}
	}
	// One line of clean text: control characters collapse to spaces
	// (the body may be HTML or binary junk), invalid bytes drop.
	text = strings.Map(func(r rune) rune {
		if r < 0x20 || r == 0x7f {
			return ' '
		}
		return r
	}, strings.ToValidUTF8(text, ""))
	text = strings.Join(strings.Fields(text), " ")
	return truncateRunes(text, 200)
}

func anyStrings(v any) []string {
	items, ok := v.([]any)
	if !ok {
		return nil
	}
	var out []string
	for _, item := range items {
		if s, ok := item.(string); ok && s != "" {
			out = append(out, s)
		}
	}
	return out
}

func stringField(doc map[string]any, key string) string {
	s, _ := doc[key].(string)
	return s
}

// decodeConfig parses a config document strictly: unknown fields are
// refused so a typo cannot silently disable an option.
func decodeConfig(raw json.RawMessage, into any) error {
	dec := json.NewDecoder(strings.NewReader(string(raw)))
	dec.DisallowUnknownFields()
	if err := dec.Decode(into); err != nil {
		return normalizeDecodeError(err)
	}
	// A second document after the first is as wrong as an unknown field.
	if dec.More() {
		return errors.New("config holds more than one document")
	}
	return nil
}

// normalizeDecodeError rewrites encoding/json's error prose into the
// config vocabulary these errors surface in.
func normalizeDecodeError(err error) error {
	msg := err.Error()
	if strings.Contains(msg, "unknown field") {
		return fmt.Errorf("config has an %s", msg[strings.Index(msg, "unknown field"):])
	}
	return errors.New("config is not a valid document: " + msg)
}

// truncateRunes bounds s to max runes, for services with hard length
// caps.
func truncateRunes(s string, max int) string {
	if utf8.RuneCountInString(s) <= max {
		return s
	}
	runes := []rune(s)
	return string(runes[:max])
}
