package service

import (
	"encoding/json"
	"strings"
	"testing"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

func TestPushBodyBudgetKeepsUTF8Clean(t *testing.T) {
	// 2334 three-byte euros (7002 bytes) force the halving loop, and
	// the first halving lands mid-rune; the payload must fit the
	// budget with no replacement characters in the delivered text.
	row := wdb.NotifyRow{
		Event: "test",
		Title: "Budget",
		Body:  strings.Repeat("€", 2334),
	}
	raw := pushBody(row)
	if len(raw) > pushBodyByteBudget {
		t.Fatalf("payload = %d bytes, want <= %d", len(raw), pushBodyByteBudget)
	}
	var got map[string]string
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatalf("payload does not parse: %v", err)
	}
	if got["body"] == "" {
		t.Fatal("body was dropped entirely; halving should have fit it")
	}
	if strings.ContainsRune(got["body"], '�') {
		t.Fatalf("delivered body carries a replacement character: %q...", got["body"][:12])
	}
}
