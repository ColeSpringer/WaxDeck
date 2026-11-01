package api

import (
	"bytes"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// A session's idleness is the server's, over the wire: next to none once
// created or once a chunk is kept, and none at all while a chunk's body is
// still arriving, however slowly.
func TestAnUploadIsNotIdleWhileItsBytesArrive(t *testing.T) {
	t.Parallel()
	staging := t.TempDir()
	h := newHarnessWith(t, func(c *service.Config) { c.StagingDir = staging })
	h.srv.chunkReadIdle = 2 * time.Second

	const size = 64
	resp := h.postJSON(t, "/api/v1/uploads", map[string]any{
		"fileName": "pace.flac", "mediaType": "music", "sizeBytes": size,
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create status = %d", resp.StatusCode)
	}
	up := decode[Upload](t, resp)
	if up.IdleMs < 0 || up.IdleMs > 60_000 {
		t.Fatalf("a new session idle for %d ms, want next to none", up.IdleMs)
	}

	// Half a chunk, then a pause on an open connection.
	conn, err := net.Dial("tcp", h.ts.Listener.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	if _, err := fmt.Fprintf(conn, "PUT /api/v1/uploads/%s/data?offset=0 HTTP/1.1\r\n"+
		"Host: waxdeck\r\nAuthorization: Bearer %s\r\n"+
		"Content-Type: application/octet-stream\r\nContent-Length: %d\r\n\r\n%s",
		up.Id, h.token, size, bytes.Repeat([]byte{'a'}, size/2)); err != nil {
		t.Fatal(err)
	}
	part := filepath.Join(staging, up.Id, "pace.flac.part")
	for deadline := time.Now().Add(5 * time.Second); ; time.Sleep(5 * time.Millisecond) {
		if fi, err := os.Stat(part); err == nil && fi.Size() == size/2 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the chunk never started arriving")
		}
	}
	if got := decode[Upload](t, get(t, h.ts, "/api/v1/uploads/"+up.Id, h.token)); got.IdleMs != 0 {
		t.Fatalf("idle %d ms while a chunk arrives, want none", got.IdleMs)
	}

	// The rest arrives and the chunk is kept.
	if _, err := conn.Write(bytes.Repeat([]byte{'a'}, size/2)); err != nil {
		t.Fatal(err)
	}
	for deadline := time.Now().Add(5 * time.Second); ; time.Sleep(5 * time.Millisecond) {
		got := decode[Upload](t, get(t, h.ts, "/api/v1/uploads/"+up.Id, h.token))
		if got.ReceivedBytes == size {
			if got.IdleMs < 0 || got.IdleMs > 60_000 {
				t.Fatalf("idle %d ms after the chunk was kept, want next to none", got.IdleMs)
			}
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the chunk was never kept")
		}
	}
}
