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
	"time"
)

// webhookProvider posts the documented generic payload to a
// caller-chosen URL: {event, title, body, timestamp}, timestamp in
// RFC 3339 UTC.
type webhookProvider struct{}

type webhookConfig struct {
	URL string `json:"url"`
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
	norm, err := json.Marshal(c)
	return norm, u.Hostname(), err
}

func (webhookProvider) Deliver(ctx context.Context, client *http.Client, config json.RawMessage, msg Message) error {
	var c webhookConfig
	if err := json.Unmarshal(config, &c); err != nil {
		return &Permanent{Err: fmt.Errorf("stored config unreadable: %w", err)}
	}
	payload, err := json.Marshal(map[string]string{
		"event":     msg.Event,
		"title":     msg.Title,
		"body":      msg.Body,
		"timestamp": msg.Timestamp.UTC().Format(time.RFC3339),
	})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.URL, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	return send(client, req)
}
