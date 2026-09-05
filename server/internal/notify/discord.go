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

// Embed stripe colours, by what an event means rather than by which
// event it is: a failure is red, a thing that finished is green, a
// thing waiting on somebody is blue, and anything a newer server
// invents is grey rather than mis-coloured.
const (
	discordRed   = 0xE05252
	discordGreen = 0x4CAF7D
	discordBlue  = 0x4C8BF5
	discordGrey  = 0x8A8F98
)

func discordColorFor(event string) int {
	switch event {
	case "backup-failed", "feed-disabled":
		return discordRed
	case "backup-completed", "episode-downloaded", "import-completed", "playlist-synced":
		return discordGreen
	case "signup-requested", "review-ready":
		return discordBlue
	default:
		return discordGrey
	}
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
	embed := map[string]any{
		"title":       truncateRunes(msg.Title, discordTitleMax),
		"description": truncateRunes(msg.Body, discordBodyMax),
		"timestamp":   msg.Timestamp.UTC().Format(time.RFC3339),
		"color":       discordColorFor(msg.Event),
		"footer":      map[string]string{"text": "WaxDeck"},
	}
	// Discord makes the embed title the link when there is one, so the
	// whole card becomes the way in.
	if msg.Link != "" {
		embed["url"] = msg.Link
	}
	payload, err := json.Marshal(map[string]any{
		"embeds": []map[string]any{embed},
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
