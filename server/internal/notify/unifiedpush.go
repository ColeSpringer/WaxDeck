package notify

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"unicode/utf8"
)

// unifiedPushProvider posts to a distributor-issued endpoint. Posting
// to caller-chosen URLs is inherent to UnifiedPush (self-hosted LAN
// distributors are legitimate), so the kind is deliberately exempt
// from the private-address check; the mitigations are shape: bodies
// carry only notification text and responses are never surfaced.
type unifiedPushProvider struct{}

// pushBodyByteBudget is the transport's payload ceiling.
const pushBodyByteBudget = 3500

type unifiedPushConfig struct {
	Endpoint string `json:"endpoint"`
}

func (unifiedPushProvider) Kind() string { return KindUnifiedPush }

func (unifiedPushProvider) ValidateConfig(raw json.RawMessage) (json.RawMessage, string, error) {
	var c unifiedPushConfig
	if err := decodeConfig(raw, &c); err != nil {
		return nil, "", err
	}
	c.Endpoint = strings.TrimSpace(c.Endpoint)
	u, err := url.Parse(c.Endpoint)
	if err != nil || u.Scheme != "https" || u.Host == "" {
		return nil, "", errors.New("the push endpoint must be an https URL")
	}
	norm, err := json.Marshal(c)
	return norm, "", err
}

// UnifiedPushEndpoint reads the endpoint out of a normalized config,
// for the dedupe key and the compatibility view.
func UnifiedPushEndpoint(config json.RawMessage) (string, error) {
	var c unifiedPushConfig
	if err := json.Unmarshal(config, &c); err != nil {
		return "", err
	}
	return c.Endpoint, nil
}

func (unifiedPushProvider) Deliver(ctx context.Context, client *http.Client, config json.RawMessage, msg Message) error {
	var c unifiedPushConfig
	if err := json.Unmarshal(config, &c); err != nil {
		return &Permanent{Err: fmt.Errorf("stored config unreadable: %w", err)}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.Endpoint, bytes.NewReader(pushBody(msg)))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	return send(client, req)
}

// pushBody renders the UnifiedPush payload within the transport's size
// budget.
func pushBody(msg Message) []byte {
	body := msg.Body
	for {
		raw, err := json.Marshal(map[string]string{
			"event": msg.Event,
			"title": msg.Title,
			"body":  body,
		})
		if err == nil && len(raw) <= pushBodyByteBudget {
			return raw
		}
		if len(body) < 64 {
			raw, _ := json.Marshal(map[string]string{"event": msg.Event, "title": msg.Title})
			return raw
		}
		body = body[:len(body)/2]
		// Halving can split a multi-byte rune, which the encoder would
		// deliver as a replacement character; back off until the tail
		// decodes cleanly. Decoding beats a whole-string validity scan:
		// it repairs the cut itself in O(1), even when earlier bytes
		// were invalid to begin with (those stay as they were). The
		// (RuneError, size 1) pair marks a broken tail; a valid
		// three-byte U+FFFD decodes with size 3 and stays.
		for i := 0; i < utf8.UTFMax-1 && len(body) > 0; i++ {
			if r, size := utf8.DecodeLastRuneInString(body); r != utf8.RuneError || size > 1 {
				break
			}
			body = body[:len(body)-1]
		}
	}
}
