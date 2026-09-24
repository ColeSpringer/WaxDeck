package flow

import (
	"testing"

	"github.com/colespringer/waxflow/waxerr"
)

// Every engine code is placed on one side on purpose, so a code a later
// WaxFlow adds fails here instead of silently reading as transient.
func TestPermanentJobErrClassifiesEveryCode(t *testing.T) {
	t.Parallel()
	permanent := map[waxerr.Code]bool{
		waxerr.CodeInvalidRequest:     true,
		waxerr.CodeUnauthorized:       true,
		waxerr.CodeSignatureInvalid:   true,
		waxerr.CodeSignatureExpired:   true,
		waxerr.CodeSourceChanged:      true,
		waxerr.CodeNotFound:           true,
		waxerr.CodeUnsupportedFormat:  true,
		waxerr.CodeUnsupportedSource:  true,
		waxerr.CodeMalformedInput:     true,
		waxerr.CodePayloadTooLarge:    true,
		waxerr.CodeSourceUnreadable:   false,
		waxerr.CodeOutputUnwritable:   false,
		waxerr.CodeOverloaded:         false,
		waxerr.CodeCanceled:           false,
		waxerr.CodeCatalogUnavailable: false,
		waxerr.CodeInternal:           false,
	}
	for _, code := range waxerr.Codes() {
		want, ok := permanent[code]
		if !ok {
			t.Errorf("%s is unclassified: does the same input always reproduce it?", code)
			continue
		}
		if got := PermanentJobErr(waxerr.New(code, "x")); got != want {
			t.Errorf("PermanentJobErr(%s) = %v, want %v", code, got, want)
		}
	}
}
