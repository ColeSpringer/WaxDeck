package main

import (
	"bytes"
	"context"
	"database/sql"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/db"
)

// A server started with no streaming engine lets go of the unmounts a
// library removal owed the bridge: with no sidecar there is no config
// file to take a root out of, and nothing would ever take them off.
func TestAServerWithNoEngineLetsGoOfTheUnmountsItOwed(t *testing.T) {
	data := filepath.Join(t.TempDir(), "data")
	if err := os.MkdirAll(data, 0o755); err != nil {
		t.Fatal(err)
	}
	dbPath := filepath.Join(data, "waxdeck.db")
	const owed = "flow-unmount:books"
	store, err := db.Open(context.Background(), dbPath)
	if err != nil {
		t.Fatal(err)
	}
	if err := store.SettingSet(context.Background(), owed, "/gone/books", time.Now().UnixNano()); err != nil {
		t.Fatal(err)
	}
	if err := store.Close(); err != nil {
		t.Fatal(err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, os.Args[0],
		"-data-dir", data, "-addr", "127.0.0.1:0",
		"-scan-on-start=false", "-cast-discovery=false", "-youtube=false",
		"-matching=false", "-sonic-analysis=false", "-library-watch=false")
	env := []string{"WAXDECK_TEST_RUN_MAIN=1"}
	for _, kv := range os.Environ() {
		if !strings.HasPrefix(kv, "WAXDECK_") {
			env = append(env, kv)
		}
	}
	cmd.Env = env
	var out bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &out
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	exited := make(chan error, 1)
	go func() { exited <- cmd.Wait() }()
	stopped := false
	stop := func() {
		if !stopped {
			stopped = true
			_ = cmd.Process.Signal(syscall.SIGTERM)
			<-exited
		}
	}
	defer stop()

	ro, err := sql.Open("sqlite", "file:"+dbPath+"?mode=ro&_pragma=busy_timeout(5000)")
	if err != nil {
		t.Fatal(err)
	}
	defer ro.Close()
	for deadline := time.Now().Add(time.Minute); ; {
		var n int
		if err := ro.QueryRowContext(ctx, `SELECT COUNT(*) FROM settings WHERE key = ?`, owed).Scan(&n); err == nil && n == 0 {
			break
		}
		select {
		case err := <-exited:
			stopped = true
			t.Fatalf("the server ended (%v) still owing the unmount:\n%s", err, out.String())
		default:
		}
		if time.Now().After(deadline) {
			stop()
			t.Fatalf("the server still owes the unmount a minute after starting:\n%s", out.String())
		}
		time.Sleep(100 * time.Millisecond)
	}
}
