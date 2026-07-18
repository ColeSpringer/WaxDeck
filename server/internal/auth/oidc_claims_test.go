package auth

import (
	"reflect"
	"testing"
)

func TestStringSliceClaimShapes(t *testing.T) {
	cases := []struct {
		name string
		in   any
		want []string
	}{
		// JSON arrays decode as []any.
		{"array", []any{"a", "b"}, []string{"a", "b"}},
		{"array with junk", []any{"a", 7, "b"}, []string{"a", "b"}},
		{"empty array", []any{}, []string{}},
		// Some providers ship a bare string when a user has one group.
		{"bare string", "admins", []string{"admins"}},
		{"empty string", "", nil},
		// Anything else reads as no groups.
		{"number", 42, nil},
		{"nil", nil, nil},
	}
	for _, c := range cases {
		if got := stringSlice(c.in); !reflect.DeepEqual(got, c.want) {
			t.Errorf("%s: stringSlice(%v) = %v, want %v", c.name, c.in, got, c.want)
		}
	}
}
