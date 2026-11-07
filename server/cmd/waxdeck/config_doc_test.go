package main

import (
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"sort"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

// Every WAXDECK_* env var the server binaries read must appear in
// docs/configuration.md: deploy/.env reaches the server verbatim, so an
// undocumented variable is a knob nobody can find.
func TestEveryServerEnvVarIsDocumented(t *testing.T) {
	doc, err := os.ReadFile(filepath.Join("..", "..", "..", "docs", "configuration.md"))
	if err != nil {
		t.Fatalf("reading docs/configuration.md: %v", err)
	}

	read := regexp.MustCompile(`(?:(?:envOr|os\.Getenv)\(\s*|\.(?:Bool|Int|Int64)\(\s*"[a-z0-9-]+",\s*)"(WAXDECK_[A-Z0-9_]+)"`)
	keys := map[string][]string{}
	root := filepath.Join("..", "..")
	err = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		src, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		for _, m := range read.FindAllStringSubmatch(string(src), -1) {
			keys[m[1]] = append(keys[m[1]], path)
		}
		return nil
	})
	if err != nil {
		t.Fatalf("walking server sources: %v", err)
	}
	if len(keys) == 0 {
		t.Fatal("found no WAXDECK_ env reads at all; the scan is broken")
	}

	// Backticked, as the doc spells every key, so a key that is a prefix
	// of a documented sibling cannot pass on the sibling's entry.
	var missing []string
	for key := range keys {
		if !strings.Contains(string(doc), "`"+key+"`") {
			missing = append(missing, key)
		}
	}
	sort.Strings(missing)
	for _, key := range missing {
		t.Errorf("%s (read in %s) is not documented in docs/configuration.md", key, filepath.Base(keys[key][0]))
	}

	// And the other direction: a documented WAXDECK_ key must exist,
	// either as a server read or as a compose-level variable, so the doc
	// cannot keep describing a knob that was removed.
	composeSrc := ""
	for _, f := range []string{"compose.yaml", ".env.example"} {
		b, err := os.ReadFile(filepath.Join("..", "..", "..", "deploy", f))
		if err != nil {
			t.Fatalf("reading deploy/%s: %v", f, err)
		}
		composeSrc += string(b)
	}
	documented := regexp.MustCompile("`(WAXDECK_[A-Z0-9_]+)`").FindAllStringSubmatch(string(doc), -1)
	var stale []string
	seen := map[string]bool{}
	for _, m := range documented {
		key := m[1]
		if seen[key] {
			continue
		}
		seen[key] = true
		if _, ok := keys[key]; !ok && !strings.Contains(composeSrc, key) {
			stale = append(stale, key)
		}
	}
	sort.Strings(stale)
	for _, key := range stale {
		t.Errorf("%s is documented but nothing reads it (not in server code, compose.yaml, or .env.example)", key)
	}
}

// composeService reads a service loosely; each test checks the form it expects.
type composeService struct {
	DependsOn   any               `yaml:"depends_on"`
	Build       any               `yaml:"build"`
	NetworkMode string            `yaml:"network_mode"`
	Ports       any               `yaml:"ports"`
	Environment map[string]string `yaml:"environment"`
	Command     []string          `yaml:"command"`
}

func loadComposeServices(t *testing.T) map[string]composeService {
	t.Helper()
	src, err := os.ReadFile(filepath.Join("..", "..", "..", "deploy", "compose.yaml"))
	if err != nil {
		t.Fatalf("reading deploy/compose.yaml: %v", err)
	}
	var compose struct {
		Services map[string]composeService `yaml:"services"`
	}
	if err := yaml.Unmarshal(src, &compose); err != nil {
		t.Fatalf("parsing deploy/compose.yaml: %v", err)
	}
	return compose.Services
}

// The engine waits for a healthy server: the server writes the roots file
// it reads, and the shared volume takes its mode from the server image.
func TestComposeStartsTheEngineOnceWaxDeckIsHealthy(t *testing.T) {
	engine, ok := loadComposeServices(t)["waxflow"]
	if !ok {
		t.Fatal("deploy/compose.yaml has no waxflow service")
	}
	deps, _ := engine.DependsOn.(map[string]any)
	waxdeck, _ := deps["waxdeck"].(map[string]any)
	if waxdeck["condition"] != "service_healthy" {
		t.Errorf("waxflow depends_on = %v, want waxdeck with condition service_healthy", engine.DependsOn)
	}
}

// A build block makes a copied compose file build from a missing context.
func TestComposeShipsImagesOnly(t *testing.T) {
	for name, svc := range loadComposeServices(t) {
		if svc.Build != nil {
			t.Errorf("%s has a build block; the shipped compose file carries images only", name)
		}
	}
}

// Discovery is multicast; ports on a host-networked service only warn.
func TestComposeServerSharesTheHostNetwork(t *testing.T) {
	server, ok := loadComposeServices(t)["waxdeck"]
	if !ok {
		t.Fatal("deploy/compose.yaml has no waxdeck service")
	}
	if server.NetworkMode != "host" {
		t.Errorf("waxdeck network_mode = %q, want host", server.NetworkMode)
	}
	if server.Ports != nil {
		t.Errorf("waxdeck publishes %v on the host network, where ports are discarded", server.Ports)
	}
}

// make up pipes the same override the getting-started guide tells Docker
// Desktop users to save, so the two copies must not drift.
func TestDockerDesktopOverrideMatchesTheDocs(t *testing.T) {
	mk, err := os.ReadFile(filepath.Join("..", "..", "..", "Makefile"))
	if err != nil {
		t.Fatal(err)
	}
	var lines []string
	quoted := regexp.MustCompile(`'([^']*)'`)
	inUp, inPrintf := false, false
	for _, l := range strings.Split(string(mk), "\n") {
		// Only the up recipe's printf: other recipes use the same form.
		if strings.HasPrefix(l, "up:") {
			inUp = true
		}
		if inUp && strings.Contains(l, `printf '%s\n'`) {
			inPrintf = true
		}
		if !inPrintf {
			continue
		}
		for _, m := range quoted.FindAllStringSubmatch(l, -1) {
			if m[1] != `%s\n` {
				lines = append(lines, strings.ReplaceAll(m[1], "$$", "$"))
			}
		}
		if strings.Contains(l, "| env") {
			break
		}
	}
	fromMake := strings.Join(lines, "\n")

	doc, err := os.ReadFile(filepath.Join("..", "..", "..", "docs", "getting-started.md"))
	if err != nil {
		t.Fatal(err)
	}
	rest := string(doc)[strings.Index(string(doc), "compose.override.yaml"):]
	start := strings.Index(rest, "```yaml\n") + len("```yaml\n")
	end := strings.Index(rest[start:], "```")
	fromDoc := strings.TrimSpace(rest[start : start+end])
	if fromMake == "" || fromMake != fromDoc {
		t.Errorf("make up pipes:\n%s\n\nthe guide shows:\n%s", fromMake, fromDoc)
	}
}

// The sidecars share the host network too and bind its loopback, so no
// port is published anywhere: engines before Docker 28 let the LAN reach
// ports published to 127.0.0.1.
func TestComposeSidecarsBindTheHostLoopback(t *testing.T) {
	services := loadComposeServices(t)
	for name, svc := range services {
		if svc.Ports != nil {
			t.Errorf("%s publishes %v; nothing in the stack publishes a port", name, svc.Ports)
		}
		if svc.NetworkMode != "host" {
			t.Errorf("%s network_mode = %q, want host", name, svc.NetworkMode)
		}
	}
	if addr := services["waxflow"].Environment["WAXFLOW_ADDR"]; !strings.HasPrefix(addr, "127.0.0.1:") {
		t.Errorf("waxflow binds %q, want the host loopback", addr)
	}
	if cmd := services["waxseal"].Command; !slices.Contains(cmd, "127.0.0.1") {
		t.Errorf("waxseal command %v does not bind the host loopback", cmd)
	}
}
