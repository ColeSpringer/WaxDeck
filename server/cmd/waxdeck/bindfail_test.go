package main

import (
	"context"
	"errors"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// TestMain lets a test run this binary's own start in a child process.
func TestMain(m *testing.M) {
	if os.Getenv("WAXDECK_TEST_RUN_MAIN") == "1" {
		main()
		return
	}
	os.Exit(m.Run())
}

// runFailingStart runs this binary's start in a child with args on top of
// the quiet defaults, which must fail it: exit 1, said, nothing claiming
// to listen, and nothing opened (no data dir). It answers the output.
func runFailingStart(t *testing.T, args ...string) string {
	t.Helper()
	data := filepath.Join(t.TempDir(), "data")
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, os.Args[0], append([]string{
		"-data-dir", data,
		"-scan-on-start=false", "-cast-discovery=false", "-youtube=false",
		"-matching=false", "-sonic-analysis=false", "-library-watch=false",
	}, args...)...)
	env := []string{"WAXDECK_TEST_RUN_MAIN=1"}
	for _, kv := range os.Environ() {
		if !strings.HasPrefix(kv, "WAXDECK_") {
			env = append(env, kv)
		}
	}
	cmd.Env = env
	out, err := cmd.CombinedOutput()
	var exit *exec.ExitError
	if !errors.As(err, &exit) || exit.ExitCode() != 1 {
		t.Fatalf("exit = %v, want status 1; output:\n%s", err, out)
	}
	if strings.Contains(string(out), "waxdeck listening") {
		t.Fatalf("a start that failed said it listens:\n%s", out)
	}
	if _, err := os.Stat(data); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("the data dir was touched before the start failed (%v):\n%s", err, out)
	}
	return string(out)
}

// A port another process holds fails the start before anything is
// opened or started: no data dir, no catalog, no workers to wait out,
// and no word of listening. It exits 1 naming the address.
func TestABindFailureStartsNothing(t *testing.T) {
	held, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer held.Close()
	addr := held.Addr().String()
	if out := runFailingStart(t, "-addr", addr); !strings.Contains(out, "waxdeck: listening on "+addr+": ") {
		t.Fatalf("output does not name the address it could not bind:\n%s", out)
	}
}

// A setting the server cannot run with fails the start the same way,
// before anything is opened or started: checked first rather than found
// once the catalog's workers are running, which would hold the exit (and
// now the port) until they finished.
func TestABadSettingStartsNothing(t *testing.T) {
	for _, c := range []struct {
		name string
		args []string
		says string
	}{
		{"a cors origin with a path", []string{"-cors-origins", "https://feishin.example/app"}, "cors origins"},
		{"a trusted proxy that is not an address", []string{"-trusted-proxies", "not-a-proxy"}, "trusted proxies"},
		{"single sign-on without a public base", []string{"-oidc-issuer", "https://idp.example"}, "WAXDECK_PUBLIC_BASE"},
		{"a streaming engine url without a host", []string{"-flow-url", "waxflow:4418"}, "waxflow:4418"},
	} {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			if out := runFailingStart(t, append([]string{"-addr", "127.0.0.1:0"}, c.args...)...); !strings.Contains(out, c.says) {
				t.Fatalf("output does not name the setting (%q):\n%s", c.says, out)
			}
		})
	}
}
