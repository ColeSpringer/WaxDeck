package service

import (
	"errors"
	"log/slog"
	"strings"
	"testing"
	"time"
)

// An address runs to where text delimits one, so a sub-delim inside it, an
// apostrophe included, cuts with the rest of the path, query or user part.
func TestTheAddressCutterTakesTheWholeAddress(t *testing.T) {
	t.Parallel()
	for in, want := range map[string]string{
		"fetching https://feeds.example/rss?auth=ab'cd3f9s3cr3t failed":    "fetching https://feeds.example failed",
		"fetching https://member:pa'ss3cr3t@feeds.example/rss failed":      "fetching https://feeds.example failed",
		`Get "https://feeds.example/rss/tok'en-s3cr3t": dial tcp: timeout`: `Get "https://feeds.example": dial tcp: timeout`,
		"https://feeds.example/rss?a=1&b=(2)*3+4,5;6=!$'s3cr3t":            "https://feeds.example",
		"see 'https://feeds.example/s3cr3t'.":                              "see 'https://feeds.example'.",
	} {
		if got := hostOnly(in); got != want {
			t.Errorf("hostOnly(%q) = %q, want %q", in, got, want)
		}
	}
}

// Cutting is linear in the line: a long run of closing brackets after an
// address is trimmed in one pass.
func TestTheAddressCutterIsLinear(t *testing.T) {
	t.Parallel()
	in := "https://a.example/s3cr3t" + strings.Repeat("]", 1<<20)
	start := time.Now()
	out := hostOnly(in)
	if took := time.Since(start); took > 5*time.Second {
		t.Fatalf("cutting a 1 MiB bracket run took %v", took)
	}
	if strings.Contains(out, "s3cr3t") || !strings.HasPrefix(out, "https://a.example]") {
		t.Fatalf("hostOnly = %.40q..., want the host and the brackets", out)
	}
}

// The service's own lines go through the cut the catalog's do, so an
// error that repeats a feed's address keeps only its host, wherever the
// line is written from.
func TestTheServicesOwnLogKeepsHostsOnly(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	ctx, svc, _, _ := openServiceAt(t, t.TempDir(), func(cfg *Config) {
		cfg.Logger = slog.New(slog.NewTextHandler(&logged, &slog.HandlerOptions{Level: slog.LevelDebug}))
	})
	cause := errors.New(`podcast.Sync: netsafe.Do: fetching https://host.example/feed?auth=SECRET returned HTTP 403`)
	svc.syncWithoutVerdict(ctx, "show-1", syncOwn, cause)
	svc.log.Debug("podping: sync failed", "show", "show-1", "err", cause)
	out := logged.String()
	if strings.Contains(out, "SECRET") || !strings.Contains(out, "https://host.example") {
		t.Fatalf("log = %q, want the host and no query", out)
	}
}
