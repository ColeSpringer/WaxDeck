package main

import (
	"flag"
	"io"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/auth"
)

// envOf is a lookupEnv over vars, so no test reads the process environment.
func envOf(vars map[string]string) func(string) (string, bool) {
	return func(key string) (string, bool) {
		v, ok := vars[key]
		return v, ok
	}
}

// parseWith parses args on a fresh, quiet flag set against vars.
func parseWith(args []string, vars map[string]string) (*config, error) {
	fs := flag.NewFlagSet("waxdeck", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	return parseConfig(fs, args, envOf(vars))
}

// A variable beats its flag's default and the flag beats the variable,
// for strings and typed values alike.
func TestAFlagBeatsItsVariableAndAVariableBeatsTheDefault(t *testing.T) {
	vars := map[string]string{
		"WAXDECK_ADDR":                      "127.0.0.1:5000",
		"WAXDECK_SESSION_CAP":               "7",
		"WAXDECK_LIBRARY_WATCH":             "false",
		"WAXDECK_PODCAST_RETENTION_DEFAULT": "3",
	}
	for _, c := range []struct {
		name      string
		args      []string
		vars      map[string]string
		addr      string
		cap       int
		watch     bool
		retention int64
	}{
		{"the defaults", nil, nil, ":4420", auth.DefaultSessionCap, true, 0},
		{"the variables", nil, vars, "127.0.0.1:5000", 7, false, 3},
		{"the flags", []string{"-addr", "127.0.0.1:6000", "-session-cap=9", "-library-watch=true", "-podcast-retention-default=4"}, vars, "127.0.0.1:6000", 9, true, 4},
	} {
		t.Run(c.name, func(t *testing.T) {
			cfg, err := parseWith(c.args, c.vars)
			if err != nil {
				t.Fatal(err)
			}
			if cfg.core.addr != c.addr || cfg.core.sessionCap != c.cap || cfg.roots.watch != c.watch || cfg.podcasts.retentionKeep != c.retention {
				t.Errorf("addr %q, session cap %d, watch %v, retention %d; want %q, %d, %v, %d",
					cfg.core.addr, cfg.core.sessionCap, cfg.roots.watch, cfg.podcasts.retentionKeep,
					c.addr, c.cap, c.watch, c.retention)
			}
		})
	}
}

// A variable its flag could not have taken fails the parse by name rather
// than start on a default nobody chose. The command line excuses the
// variable of a flag it sets, and a mode that answers without serving
// (-version) never gets that far.
func TestAnUnreadableVariableIsRefused(t *testing.T) {
	bad := map[string]string{"WAXDECK_SESSION_CAP": "abc", "WAXDECK_LIBRARY_WATCH": "maybe"}
	_, err := parseWith(nil, bad)
	for _, key := range []string{"WAXDECK_SESSION_CAP", "WAXDECK_LIBRARY_WATCH"} {
		if err == nil || !strings.Contains(err.Error(), key) {
			t.Errorf("parse = %v, want a refusal naming %s", err, key)
		}
	}
	_, err = parseWith([]string{"-session-cap=3"}, bad)
	if err == nil || strings.Contains(err.Error(), "WAXDECK_SESSION_CAP") || !strings.Contains(err.Error(), "WAXDECK_LIBRARY_WATCH") {
		t.Errorf("with -session-cap set, parse = %v; want only WAXDECK_LIBRARY_WATCH refused", err)
	}
	if cfg, err := parseWith([]string{"-version"}, bad); err != nil || cfg == nil || !cfg.showVersion {
		t.Errorf("-version = %v; want the version mode despite the variables", err)
	}
}

// The settings parsing checks fail it naming what is wrong.
func TestParseConfigRefusesSettingsTheServerCannotRunWith(t *testing.T) {
	for _, c := range []struct {
		args []string
		says string
	}{
		{[]string{"-session-cap=0"}, "WAXDECK_SESSION_CAP"},
		{[]string{"-enrichment-retry-misses-days=-1"}, "WAXDECK_ENRICHMENT_RETRY_MISSES_DAYS"},
		{[]string{"-library-roots", "music"}, `bad library root "music"`},
	} {
		if _, err := parseWith(c.args, nil); err == nil || !strings.Contains(err.Error(), c.says) {
			t.Errorf("%v: parse = %v, want a refusal naming %s", c.args, err, c.says)
		}
	}
}

// An explicitly empty podcast dir turns podcasts off whichever way it is
// said; saying nothing puts them beside the databases.
func TestAnExplicitlyEmptyPodcastDirTurnsPodcastsOff(t *testing.T) {
	data := filepath.Join("srv", "data")
	for _, c := range []struct {
		name string
		args []string
		vars map[string]string
		want string
	}{
		{"nothing said", []string{"-data-dir", data}, nil, filepath.Join(data, "podcasts")},
		{"nothing said, the data dir from its variable", nil, map[string]string{"WAXDECK_DATA_DIR": data}, filepath.Join(data, "podcasts")},
		{"-podcast-dir empty", []string{"-data-dir", data, "-podcast-dir="}, nil, ""},
		{"WAXDECK_PODCAST_DIR set and empty", []string{"-data-dir", data}, map[string]string{"WAXDECK_PODCAST_DIR": ""}, ""},
		{"WAXDECK_PODCAST_DIR set", []string{"-data-dir", data}, map[string]string{"WAXDECK_PODCAST_DIR": "/pods"}, "/pods"},
		{"-podcast-dir beats an empty variable", []string{"-data-dir", data, "-podcast-dir", "/pods"}, map[string]string{"WAXDECK_PODCAST_DIR": ""}, "/pods"},
	} {
		t.Run(c.name, func(t *testing.T) {
			cfg, err := parseWith(c.args, c.vars)
			if err != nil {
				t.Fatal(err)
			}
			if cfg.podcasts.dir != c.want {
				t.Errorf("podcast dir = %q, want %q", cfg.podcasts.dir, c.want)
			}
		})
	}
}

// An explicitly empty SponsorBlock list turns cutting off whichever way it
// is said; saying nothing cuts sponsors and non-music sections.
func TestAnExplicitlyEmptySponsorBlockTurnsCuttingOff(t *testing.T) {
	for _, c := range []struct {
		name string
		args []string
		vars map[string]string
		want []string
	}{
		{"-youtube-sponsorblock empty", []string{"-youtube-sponsorblock="}, nil, nil},
		{"WAXDECK_YOUTUBE_SPONSORBLOCK set and empty", nil, map[string]string{"WAXDECK_YOUTUBE_SPONSORBLOCK": ""}, nil},
		{"nothing said", nil, nil, []string{"sponsor", "music_offtopic"}},
	} {
		t.Run(c.name, func(t *testing.T) {
			cfg, err := parseWith(c.args, c.vars)
			if err != nil {
				t.Fatal(err)
			}
			if !slices.Equal(cfg.acquisition.sponsorBlock, c.want) {
				t.Errorf("sponsorblock categories = %v, want %v", cfg.acquisition.sponsorBlock, c.want)
			}
		})
	}
}

// flagWasSet tells an explicit value, empty included, from a default, and
// reads only the set it is given.
func TestFlagWasSet(t *testing.T) {
	fs := flag.NewFlagSet("t", flag.ContinueOnError)
	fs.String("given", "", "")
	fs.String("empty", "", "")
	fs.String("unset", "x", "")
	other := flag.NewFlagSet("other", flag.ContinueOnError)
	other.String("unset", "x", "")
	if err := fs.Parse([]string{"-given=a", "-empty="}); err != nil {
		t.Fatal(err)
	}
	if err := other.Parse([]string{"-unset=y"}); err != nil {
		t.Fatal(err)
	}
	for name, want := range map[string]bool{"given": true, "empty": true, "unset": false, "undefined": false} {
		if got := flagWasSet(fs, name); got != want {
			t.Errorf("flagWasSet(%q) = %v, want %v", name, got, want)
		}
	}
}

// Every variable the configuration reads is documented, whichever path
// reads it: the source scan in TestEveryServerEnvVarIsDocumented sees only
// the read shapes it knows.
func TestEveryVariableTheConfigReadsIsDocumented(t *testing.T) {
	doc, err := os.ReadFile(filepath.Join("..", "..", "..", "docs", "configuration.md"))
	if err != nil {
		t.Fatal(err)
	}
	read := map[string]bool{}
	fs := flag.NewFlagSet("waxdeck", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	if _, err := parseConfig(fs, nil, func(key string) (string, bool) {
		read[key] = true
		return "", false
	}); err != nil {
		t.Fatal(err)
	}
	if len(read) == 0 {
		t.Fatal("parseConfig read no variables at all")
	}
	keys := make([]string, 0, len(read))
	for key := range read {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		if !strings.Contains(string(doc), "`"+key+"`") {
			t.Errorf("parseConfig reads %s, which docs/configuration.md does not document", key)
		}
	}
}
