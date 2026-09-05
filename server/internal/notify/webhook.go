package notify

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"
)

// webhookProvider posts the documented generic payload to a
// caller-chosen URL: {event, title, body, timestamp}, timestamp in
// RFC 3339 UTC, plus {link} when the server knows where its web app
// lives and the event names something to open.
type webhookProvider struct{}

// Bounds on the caller-supplied headers. Small on purpose: this is a
// hook for an auth token or a routing key, not a general proxy.
const (
	webhookMaxHeaders    = 8
	webhookMaxHeaderName = 64
	webhookMaxHeaderVal  = 1024
	webhookMaxSecret     = 256
)

// refusedWebhookHeaders are the names a caller may not set: the
// hop-by-hop set, which belongs to the transport, plus the three this
// provider decides itself. Lower-cased; comparison is
// case-insensitive because header names are.
var refusedWebhookHeaders = map[string]bool{
	"connection":          true,
	"keep-alive":          true,
	"proxy-authenticate":  true,
	"proxy-authorization": true,
	"te":                  true,
	"trailer":             true,
	"transfer-encoding":   true,
	"upgrade":             true,
	"host":                true,
	"content-length":      true,
	"content-type":        true,
}

type webhookConfig struct {
	URL string `json:"url"`
	// Headers ride every post. A map rather than a list because a
	// header name is unique per request and the wire shape should say
	// so.
	Headers map[string]string `json:"headers,omitempty"`
	// Secret signs every post. Held sealed like the rest of the
	// config; the receiver holds the same string.
	Secret string `json:"secret,omitempty"`
}

func (webhookProvider) Kind() string { return KindWebhook }

func (webhookProvider) ValidateConfig(raw json.RawMessage) (json.RawMessage, string, error) {
	var c webhookConfig
	if err := decodeConfig(raw, &c); err != nil {
		return nil, "", err
	}
	c.URL = strings.TrimSpace(c.URL)
	u, err := url.Parse(c.URL)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return nil, "", errors.New("webhook url must be http or https")
	}
	if len(c.Headers) > 0 {
		clean := make(map[string]string, len(c.Headers))
		for name, value := range c.Headers {
			name = strings.TrimSpace(name)
			if err := validHeaderName(name); err != nil {
				return nil, "", err
			}
			if len(value) > webhookMaxHeaderVal {
				return nil, "", fmt.Errorf("header %s is longer than %d characters", name, webhookMaxHeaderVal)
			}
			if strings.ContainsAny(value, "\r\n\x00") {
				return nil, "", fmt.Errorf("header %s must not contain line breaks", name)
			}
			// Header names are case-insensitive, so two spellings of one
			// name are one header. Refused rather than collapsed: which
			// value survived would be map iteration order, and the owner
			// would see one header where they typed two.
			canonical := http.CanonicalHeaderKey(name)
			if _, taken := clean[canonical]; taken {
				return nil, "", fmt.Errorf("header %s is given twice", canonical)
			}
			clean[canonical] = value
		}
		// Counted after canonicalizing, so the cap is on headers rather
		// than on spellings.
		if len(clean) > webhookMaxHeaders {
			return nil, "", fmt.Errorf("a webhook takes at most %d headers", webhookMaxHeaders)
		}
		c.Headers = clean
	} else {
		c.Headers = nil
	}
	if len(c.Secret) > webhookMaxSecret {
		return nil, "", fmt.Errorf("a webhook secret is at most %d characters", webhookMaxSecret)
	}
	norm, err := json.Marshal(c)
	return norm, u.Hostname(), err
}

// validHeaderName holds the name to an ASCII token, which is what an
// HTTP field name is, and refuses the ones this provider owns.
func validHeaderName(name string) error {
	if name == "" {
		return errors.New("a webhook header needs a name")
	}
	if len(name) > webhookMaxHeaderName {
		return fmt.Errorf("header name %q is longer than %d characters", name, webhookMaxHeaderName)
	}
	for _, r := range name {
		if r > 0x7e || r <= 0x20 || strings.ContainsRune("()<>@,;:\\\"/[]?={}", r) {
			return fmt.Errorf("header name %q is not an HTTP token", name)
		}
	}
	if refusedWebhookHeaders[strings.ToLower(name)] {
		return fmt.Errorf("header %s belongs to the transport and cannot be set", name)
	}
	return nil
}

func (webhookProvider) Deliver(ctx context.Context, client *http.Client, config json.RawMessage, msg Message) error {
	var c webhookConfig
	if err := json.Unmarshal(config, &c); err != nil {
		return &Permanent{Err: fmt.Errorf("stored config unreadable: %w", err)}
	}
	fields := map[string]string{
		"event":     msg.Event,
		"title":     msg.Title,
		"body":      msg.Body,
		"timestamp": msg.Timestamp.UTC().Format(time.RFC3339),
	}
	// Absent rather than empty: a receiver keying on the field's
	// presence is answering "is there somewhere to go", and an empty
	// string is not an honest yes.
	if msg.Link != "" {
		fields["link"] = msg.Link
	}
	payload, err := json.Marshal(fields)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.URL, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	// The caller's headers first, so nothing it sets can displace the
	// three below - which the signature and the body format depend on.
	for _, name := range sortedKeys(c.Headers) {
		req.Header.Set(name, c.Headers[name])
	}
	req.Header.Set("Content-Type", "application/json")
	if c.Secret != "" {
		stamp := strconv.FormatInt(msg.Timestamp.UTC().Unix(), 10)
		mac := hmac.New(sha256.New, []byte(c.Secret))
		mac.Write([]byte(stamp))
		mac.Write([]byte("."))
		mac.Write(payload)
		req.Header.Set("X-WaxDeck-Timestamp", stamp)
		req.Header.Set("X-WaxDeck-Signature", "sha256="+hex.EncodeToString(mac.Sum(nil)))
	}
	return send(client, req)
}

// sortedKeys makes header order deterministic, which is what lets a
// test pin a request rather than a set.
func sortedKeys(m map[string]string) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
