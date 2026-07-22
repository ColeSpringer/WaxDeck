package notify

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

// pushoverProvider posts to the Pushover message API. The host is
// fixed, so no private-address check applies.
type pushoverProvider struct{}

// pushoverMessageURL is variable for tests only.
var pushoverMessageURL = "https://api.pushover.net/1/messages.json"

// Pushover's documented field caps.
const (
	pushoverTitleMax = 250
	pushoverBodyMax  = 1024
)

type pushoverConfig struct {
	Token    string `json:"token"`
	UserKey  string `json:"userKey"`
	Priority *int   `json:"priority,omitempty"`
}

func (pushoverProvider) Kind() string { return KindPushover }

func (pushoverProvider) ValidateConfig(raw json.RawMessage) (json.RawMessage, string, error) {
	var c pushoverConfig
	if err := decodeConfig(raw, &c); err != nil {
		return nil, "", err
	}
	c.Token = strings.TrimSpace(c.Token)
	c.UserKey = strings.TrimSpace(c.UserKey)
	if c.Token == "" {
		return nil, "", errors.New("pushover needs a token (the application API token)")
	}
	if c.UserKey == "" {
		return nil, "", errors.New("pushover needs a userKey (the user or group key)")
	}
	if c.Priority != nil && (*c.Priority < -2 || *c.Priority > 2) {
		return nil, "", errors.New("pushover priority must be between -2 and 2")
	}
	norm, err := json.Marshal(c)
	return norm, "", err
}

func (pushoverProvider) Deliver(ctx context.Context, client *http.Client, config json.RawMessage, msg Message) error {
	var c pushoverConfig
	if err := json.Unmarshal(config, &c); err != nil {
		return &Permanent{Err: fmt.Errorf("stored config unreadable: %w", err)}
	}
	form := url.Values{
		"token":   {c.Token},
		"user":    {c.UserKey},
		"title":   {truncateRunes(msg.Title, pushoverTitleMax)},
		"message": {truncateRunes(msg.Body, pushoverBodyMax)},
	}
	if c.Priority != nil {
		form.Set("priority", strconv.Itoa(*c.Priority))
		if *c.Priority == 2 {
			// Emergency priority requires a retry cadence; use the
			// service's minimum retry with a one-hour expiry.
			form.Set("retry", "60")
			form.Set("expire", "3600")
		}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, pushoverMessageURL,
		strings.NewReader(form.Encode()))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	// Fixed host: the service's own error text may surface.
	return sendDetailed(client, req)
}
