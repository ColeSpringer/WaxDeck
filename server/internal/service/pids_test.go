package service

import "testing"

// Crockford's alphabet reads either case, so every by-id path finds the
// same row whichever case the caller typed.
func TestAnAPIPIDReadsEitherCase(t *testing.T) {
	for _, in := range []string{"sh-01JZX5N8QW3F4V9T2B7KD3M9R6", "sh-01jzx5n8qw3f4v9t2b7kd3m9r6"} {
		prefix, pid, ok := parseAPIPID(in)
		if !ok || prefix != "sh" || pid != "01JZX5N8QW3F4V9T2B7KD3M9R6" {
			t.Errorf("parseAPIPID(%q) = (%q, %q, %v), want the upper-case pid", in, prefix, pid, ok)
		}
	}
}
