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

// discordProvider posts an embed to a Discord webhook. Only the
// service's own webhook hosts are accepted, which also exempts the
// kind from the private-address check.
type discordProvider struct{}

// Discord's documented embed caps.
const (
	discordTitleMax = 256
	discordBodyMax  = 4096
)

// discordWebhookHosts is the allowlist; Discord issues webhook URLs on
// discord.com (and historically discordapp.com).
var discordWebhookHosts = map[string]bool{
	"discord.com":    true,
	"discordapp.com": true,
}

type discordConfig struct {
	WebhookURL string `json:"webhookUrl"`
}

func (discordProvider) Kind() string { return KindDiscord }

func (discordProvider) ValidateConfig(raw json.RawMessage) (json.RawMessage, string, error) {
	var c discordConfig
	if err := decodeConfig(raw, &c); err != nil {
		return nil, "", err
	}
	c.WebhookURL = strings.TrimSpace(c.WebhookURL)
	u, err := url.Parse(c.WebhookURL)
	if err != nil || u.Scheme != "https" || u.Host == "" {
		return nil, "", errors.New("discord webhookUrl must be an https URL")
	}
	if !discordWebhookHosts[strings.ToLower(u.Hostname())] {
		return nil, "", errors.New("discord webhookUrl must be on discord.com or discordapp.com")
	}
	if !strings.HasPrefix(u.Path, "/api/webhooks/") {
		return nil, "", errors.New("discord webhookUrl must be a webhook URL (its path starts with /api/webhooks/)")
	}
	norm, err := json.Marshal(c)
	return norm, "", err
}

func (discordProvider) Deliver(ctx context.Context, client *http.Client, config json.RawMessage, msg Message) error {
	var c discordConfig
	if err := json.Unmarshal(config, &c); err != nil {
		return &Permanent{Err: fmt.Errorf("stored config unreadable: %w", err)}
	}
	payload, err := json.Marshal(map[string]any{
		"embeds": []map[string]string{{
			"title":       truncateRunes(msg.Title, discordTitleMax),
			"description": truncateRunes(msg.Body, discordBodyMax),
		}},
	})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.WebhookURL, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	// Allowlisted host: the service's own error text may surface.
	return sendDetailed(client, req)
}
