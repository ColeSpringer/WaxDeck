package api

import (
	"bufio"
	"bytes"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// A chunk whose sender stops mid-body and never closes holds its session's
// append turn for the idle window only: the resend at the same offset gets
// in once the window passes, and the stalled request answers an error
// without counting its bytes.
func TestAStalledChunkGivesUpItsTurn(t *testing.T) {
	t.Parallel()
	staging := t.TempDir()
	h := newHarnessWith(t, func(c *service.Config) { c.StagingDir = staging })
	const idle = 500 * time.Millisecond
	h.srv.chunkReadIdle = idle

	const size = 64
	up := decode[Upload](t, h.postJSON(t, "/api/v1/uploads", map[string]any{
		"fileName": "stall.flac", "mediaType": "music", "sizeBytes": size,
	}))

	// Half a chunk, then silence on an open connection: a peer that
	// dropped off the network, as the server sees it.
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

	// Its half on disk means it holds the turn and waits for the rest.
	part := filepath.Join(staging, up.Id, "stall.flac.part")
	for deadline := time.Now().Add(5 * time.Second); ; {
		if fi, err := os.Stat(part); err == nil && fi.Size() == size/2 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the stalled chunk never started writing")
		}
		time.Sleep(5 * time.Millisecond)
	}

	whole := bytes.Repeat([]byte{'b'}, size)
	req, err := http.NewRequest("PUT", h.ts.URL+"/api/v1/uploads/"+up.Id+"/data?offset=0", bytes.NewReader(whole))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/octet-stream")
	req.Header.Set("Authorization", "Bearer "+h.token)
	resp, err := (&http.Client{Timeout: idle + 5*time.Second}).Do(req)
	if err != nil {
		t.Fatalf("the resend behind a stalled chunk did not answer: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("the resend answered %d, want 200", resp.StatusCode)
	}
	if got := decode[Upload](t, resp).ReceivedBytes; got != size {
		t.Fatalf("receivedBytes after the resend = %d, want %d", got, size)
	}

	if err := conn.SetReadDeadline(time.Now().Add(5 * time.Second)); err != nil {
		t.Fatal(err)
	}
	stalled, err := http.ReadResponse(bufio.NewReader(conn), nil)
	if err != nil {
		t.Fatalf("the stalled request never answered: %v", err)
	}
	stalled.Body.Close()
	if stalled.StatusCode < 400 {
		t.Fatalf("the stalled request answered %d, want an error", stalled.StatusCode)
	}
	if got, err := os.ReadFile(part); err != nil || !bytes.Equal(got, whole) {
		t.Fatalf("the part holds %q (%v), want the resend's bytes", got, err)
	}
}
