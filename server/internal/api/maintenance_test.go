package api

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/colespringer/waxbin/proxy"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// While the CLI holds the catalog, a failure the service could not class
// answers maintenance like the rest, over REST, over the socket, as a
// bulk edit's part refusal and on a raw route; outside a hand-off it stays
// internal. A handler's own refusal is classed, so it keeps its answer
// either way.
func TestAnUnclassedFailureInAHandOffAnswersMaintenance(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.DiscardHandler)
	dataDir, err := os.MkdirTemp("", "wdmaint")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dataDir) })
	store, err := db.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	group := supervise.NewGroup(log)
	svc, err := service.Open(ctx, service.Config{DataDir: dataDir, Logger: log}, store, group)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cancel()
		group.Wait()
		svc.Close()
		store.Close()
	})
	srv := NewServer("test", Options{Service: svc, Sessions: auth.NewSessions(store)})
	failure := &service.Error{Kind: service.KindInternal, Err: errors.New("sql: connection is already closed")}
	answer := func(err error) (int, string) {
		rec := httptest.NewRecorder()
		srv.ResponseErrorHandler(rec, httptest.NewRequest(http.MethodGet, "/api/v1/items", nil), err)
		var body Error
		if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
			t.Fatal(err)
		}
		return rec.Code, body.Code
	}
	if status, code := answer(failure); status != http.StatusInternalServerError || code != "internal" {
		t.Fatalf("outside a hand-off: %d %s, want 500 internal", status, code)
	}
	if code, _, _ := srv.wsRefusal(failure); code != "internal" {
		t.Fatalf("outside a hand-off, the socket answers %s, want internal", code)
	}
	if part := srv.partRefusal(failure); part.Code != "internal" {
		t.Fatalf("outside a hand-off, a part refusal answers %s, want internal", part.Code)
	}
	raw := func() int {
		rec := httptest.NewRecorder()
		writeDownloadSourceError(rec, srv.kindOf(failure))
		return rec.Code
	}
	if status := raw(); status != http.StatusInternalServerError {
		t.Fatalf("outside a hand-off, a raw route answers %d, want 500", status)
	}

	var c *proxy.Client
	for deadline := time.Now().Add(5 * time.Second); ; {
		if c, err = proxy.Dial(filepath.Join(dataDir, service.SocketFileName)); err == nil {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal(err)
		}
		time.Sleep(10 * time.Millisecond)
	}
	defer c.Close()
	if err := c.MaintenanceBegin(ctx); err != nil {
		t.Fatal(err)
	}
	status, code := answer(failure)
	refusedStatus, refusedCode := answer(errNoBody())
	socketCode, socketWords, _ := srv.wsRefusal(failure)
	part := srv.partRefusal(failure)
	rawStatus := raw()
	if err := c.MaintenanceEnd(ctx); err != nil {
		t.Fatal(err)
	}
	if status != http.StatusServiceUnavailable || code != "catalog-maintenance" {
		t.Fatalf("inside a hand-off: %d %s, want 503 catalog-maintenance", status, code)
	}
	if want := maintenanceAnswer(); socketCode != want.Code || socketWords != want.Message {
		t.Fatalf("inside a hand-off, the socket answers %s %q, want %s %q", socketCode, socketWords, want.Code, want.Message)
	}
	if part.Code != "catalog-maintenance" {
		t.Fatalf("inside a hand-off, a part refusal answers %s, want catalog-maintenance", part.Code)
	}
	if rawStatus != http.StatusServiceUnavailable {
		t.Fatalf("inside a hand-off, a raw route answers %d, want 503", rawStatus)
	}
	if refusedStatus != http.StatusBadRequest || refusedCode != "invalid-request" {
		t.Fatalf("a refusal inside a hand-off: %d %s, want 400 invalid-request", refusedStatus, refusedCode)
	}
}
