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

// ntfyProvider publishes to an ntfy server in JSON mode: the topic
// rides the body, so titles keep full UTF-8 instead of the
// Latin-1-only header form.
type ntfyProvider struct{}

const ntfyDefaultServer = "https://ntfy.sh"

type ntfyConfig struct {
	Topic       string `json:"topic"`
	ServerURL   string `json:"serverUrl,omitempty"`
	AccessToken string `json:"accessToken,omitempty"`
}

func (ntfyProvider) Kind() string { return KindNtfy }

func (ntfyProvider) ValidateConfig(raw json.RawMessage) (json.RawMessage, string, error) {
	var c ntfyConfig
	if err := decodeConfig(raw, &c); err != nil {
		return nil, "", err
	}
	c.Topic = strings.TrimSpace(c.Topic)
	if c.Topic == "" {
		return nil, "", errors.New("ntfy needs a topic")
	}
	if strings.ContainsAny(c.Topic, "/ \t") {
		return nil, "", errors.New("an ntfy topic is a single name without slashes or spaces")
	}
	c.ServerURL = strings.TrimRight(strings.TrimSpace(c.ServerURL), "/")
	if c.ServerURL == "" {
		c.ServerURL = ntfyDefaultServer
	}
	u, err := url.Parse(c.ServerURL)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return nil, "", errors.New("ntfy serverUrl must be http or https")
	}
	norm, err := json.Marshal(c)
	return norm, u.Hostname(), err
}

func (ntfyProvider) Deliver(ctx context.Context, client *http.Client, config json.RawMessage, msg Message) error {
	var c ntfyConfig
	if err := json.Unmarshal(config, &c); err != nil {
		return &Permanent{Err: fmt.Errorf("stored config unreadable: %w", err)}
	}
	fields := map[string]any{
		"topic":   c.Topic,
		"title":   msg.Title,
		"message": msg.Body,
	}
	// Tapping the notification opens the thing it is about, and the
	// action button is the same destination for a reader who long-
	// presses instead. Both only when the server knows its public base:
	// a link into a host nobody outside the LAN can resolve is worse
	// than no link.
	if msg.Link != "" {
		fields["click"] = msg.Link
		fields["actions"] = []map[string]string{{
			"action": "view",
			"label":  "Open",
			"url":    msg.Link,
		}}
	}
	payload, err := json.Marshal(fields)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.ServerURL, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if c.AccessToken != "" {
		req.Header.Set("Authorization", "Bearer "+c.AccessToken)
	}
	return send(client, req)
}
