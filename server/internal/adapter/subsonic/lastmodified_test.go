package subsonic

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// serviceHandler is a handler over a real, empty catalog, and an account
// that sees all of it.
func serviceHandler(t *testing.T) (*Handler, *service.UserCtx) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	dataDir := t.TempDir()
	store, err := db.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	sealer, err := auth.NewSealer([]byte("0123456789abcdef0123456789abcdef"), "waxdeck-app-password-v1")
	if err != nil {
		t.Fatal(err)
	}
	group := supervise.NewGroup(log)
	svc, err := service.Open(ctx, service.Config{
		DataDir: dataDir, Roots: []service.Root{{Name: "lib", Path: t.TempDir()}}, Sealer: sealer, Logger: log,
	}, store, group)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cancel()
		group.Wait()
		svc.Close()
		store.Close()
	})
	acct, err := svc.CreateAccount(ctx, service.AccountCreate{Username: "alice", Password: "login-password-1"})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return New(svc, nil, nil, "test", log), uc
}

func indexesLastModified(t *testing.T, h *Handler, uc *service.UserCtx) int64 {
	t.Helper()
	r := httptest.NewRequest("GET", "/rest/getIndexes?f=json", nil)
	if err := r.ParseForm(); err != nil {
		t.Fatal(err)
	}
	w := httptest.NewRecorder()
	h.getIndexes(w, r, uc)
	var out struct {
		Response struct {
			Status  string `json:"status"`
			Indexes struct {
				LastModified int64 `json:"lastModified"`
			} `json:"indexes"`
		} `json:"subsonic-response"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &out); err != nil || out.Response.Status != "ok" {
		t.Fatalf("getIndexes = %s (%v)", w.Body.String(), err)
	}
	return out.Response.Indexes.LastModified
}

// lastModified is the catalog position the index getIndexes answers with
// was built at, not a second look at the catalog, which can name a newer
// position than the one served or, when it cannot tell, the feed's.
func TestGetIndexesReportsThePositionOfTheIndexItServes(t *testing.T) {
	h, uc := serviceHandler(t)
	first := indexesLastModified(t, h, uc)
	h.idxMu.Lock()
	served := h.idxShared
	if indexScope(uc) != "" {
		served = h.idxScoped[indexScope(uc)]
	}
	h.idxMu.Unlock()
	if served == nil || served.tail != first {
		t.Fatalf("cached index = %+v, want one built at %d", served, first)
	}
	// Marked so the answer shows whose position it reports.
	served.tail = first - 1
	if got := indexesLastModified(t, h, uc); got != first-1 {
		t.Errorf("lastModified = %d, want %d, the position of the index served", got, first-1)
	}
}
