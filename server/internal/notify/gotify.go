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
)

// gotifyProvider posts to a Gotify server's message endpoint. The app
// token travels in a header, never in the URL, so it stays out of
// request logs.
type gotifyProvider struct{}

type gotifyConfig struct {
	ServerURL string `json:"serverUrl"`
	Token     string `json:"token"`
	Priority  *int   `json:"priority,omitempty"`
}

func (gotifyProvider) Kind() string { return KindGotify }

func (gotifyProvider) ValidateConfig(raw json.RawMessage) (json.RawMessage, string, error) {
	var c gotifyConfig
	if err := decodeConfig(raw, &c); err != nil {
		return nil, "", err
	}
	c.ServerURL = strings.TrimRight(strings.TrimSpace(c.ServerURL), "/")
	if c.ServerURL == "" {
		return nil, "", errors.New("gotify needs a serverUrl")
	}
	u, err := url.Parse(c.ServerURL)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return nil, "", errors.New("gotify serverUrl must be http or https")
	}
	c.Token = strings.TrimSpace(c.Token)
	if c.Token == "" {
		return nil, "", errors.New("gotify needs an application token")
	}
	if c.Priority != nil && (*c.Priority < 0 || *c.Priority > 10) {
		return nil, "", errors.New("gotify priority must be between 0 and 10")
	}
	norm, err := json.Marshal(c)
	return norm, u.Hostname(), err
}

func (gotifyProvider) Deliver(ctx context.Context, client *http.Client, config json.RawMessage, msg Message) error {
	var c gotifyConfig
	if err := json.Unmarshal(config, &c); err != nil {
		return &Permanent{Err: fmt.Errorf("stored config unreadable: %w", err)}
	}
	body := map[string]any{"title": msg.Title, "message": msg.Body}
	if c.Priority != nil {
		body["priority"] = *c.Priority
	}
	payload, err := json.Marshal(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.ServerURL+"/message", bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Gotify-Key", c.Token)
	return send(client, req)
}
