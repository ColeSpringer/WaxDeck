package service

import "testing"

func TestShareCursorRoundTrip(t *testing.T) {
	t.Parallel()
	wantNS := int64(1753000000000000000)
	wantID := "01JZX5N8QW3F4V9T2B7KDEXAMPLE"
	ns, id, err := decodeShareCursor(encodeShareCursor(wantNS, wantID))
	if err != nil || ns != wantNS || id != wantID {
		t.Fatalf("round trip = (%d, %q, %v), want (%d, %q, nil)", ns, id, err, wantNS, wantID)
	}
	// The empty cursor is the first page, never an error.
	if ns, id, err := decodeShareCursor(""); err != nil || ns != 0 || id != "" {
		t.Fatalf("empty cursor = (%d, %q, %v), want (0, \"\", nil)", ns, id, err)
	}
}

func TestShareCursorMalformed(t *testing.T) {
	t.Parallel()
	for _, bad := range []string{
		"nodot",             // no separator at all
		"%%%.someid",        // prefix is not base64url
		"!!!.",              // empty id and broken prefix
		"bm9jb2xvbg.someid", // prefix decodes but carries no ns:id pair
	} {
		if _, _, err := decodeShareCursor(bad); err == nil {
			t.Errorf("cursor %q decoded, want error", bad)
		}
	}
}
