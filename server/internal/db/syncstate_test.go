package db

import (
	"context"
	"maps"
	"testing"
)

// A prefix read answers exactly the keys that start with the prefix.
func TestSyncStateWithPrefix(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	for k, v := range map[string]string{
		"show_private:a": "1", "show_private:b": "1", "show_private:": "root",
		"show_privat": "short", "show_private;x": "past", "show_privateX": "past", "other": "x",
	} {
		if err := d.SyncStateSet(ctx, k, v); err != nil {
			t.Fatal(err)
		}
	}
	got, err := d.SyncStateWithPrefix(ctx, "show_private:")
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]string{"show_private:a": "1", "show_private:b": "1", "show_private:": "root"}
	if !maps.Equal(got, want) {
		t.Errorf("show_private: = %v, want %v", got, want)
	}
	if none, err := d.SyncStateWithPrefix(ctx, "absent:"); err != nil || len(none) != 0 {
		t.Errorf("an absent prefix = %v, %v; want nothing", none, err)
	}
}

func TestPrefixEnd(t *testing.T) {
	for in, want := range map[string]string{
		"show_private:": "show_private;",
		"a\xff":         "b",
		"\xff\xff":      "",
	} {
		if got := prefixEnd(in); got != want {
			t.Errorf("prefixEnd(%q) = %q, want %q", in, got, want)
		}
	}
}
