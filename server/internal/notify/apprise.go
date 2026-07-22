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

// appriseProvider relays through an Apprise API server: one
// integration for many downstream services, posted as JSON to the
// server's notify endpoint.
type appriseProvider struct{}

type appriseConfig struct {
	ServerURL string `json:"serverUrl"`
	Targets   string `json:"targets,omitempty"`
}

func (appriseProvider) Kind() string { return KindApprise }

func (appriseProvider) ValidateConfig(raw json.RawMessage) (json.RawMessage, string, error) {
	var c appriseConfig
	if err := decodeConfig(raw, &c); err != nil {
		return nil, "", err
	}
	c.ServerURL = strings.TrimSpace(c.ServerURL)
	if c.ServerURL == "" {
		return nil, "", errors.New("apprise needs a serverUrl")
	}
	u, err := url.Parse(c.ServerURL)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return nil, "", errors.New("apprise serverUrl must be http or https")
	}
	norm, err := json.Marshal(c)
	return norm, u.Hostname(), err
}

func (appriseProvider) Deliver(ctx context.Context, client *http.Client, config json.RawMessage, msg Message) error {
	var c appriseConfig
	if err := json.Unmarshal(config, &c); err != nil {
		return &Permanent{Err: fmt.Errorf("stored config unreadable: %w", err)}
	}
	payload := map[string]any{"title": msg.Title, "body": msg.Body, "type": "info"}
	if c.Targets != "" {
		payload["urls"] = c.Targets
	}
	raw, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, appriseNotifyURL(c.ServerURL), bytes.NewReader(raw))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	return send(client, req)
}

// appriseNotifyURL derives the notify endpoint from the configured
// base: a bare host gains the stateless /notify path, while a URL that
// already names a notify path (stateful keys included) is used as is.
func appriseNotifyURL(base string) string {
	trimmed := strings.TrimRight(base, "/")
	if u, err := url.Parse(trimmed); err == nil {
		if u.Path == "" || u.Path == "/" {
			return trimmed + "/notify"
		}
	}
	return trimmed
}
