package service

import (
	"strings"
	"testing"
)

// A decision whose files the library's folder will not take is refused
// as the library's to fix, in words that name neither the server's
// folders nor the importer's operations, and the upload stays staged
// for the same decision once the folder is fixed.
func TestAnUploadIntoAnUnwritableLibraryIsSaidSo(t *testing.T) {
	skipWithoutUnwritablePaths(t)
	ctx, svc, uc := managedUploadFixture(t)
	up, id := pendingUploadEntry(t, ctx, svc, uc)
	var root string
	for _, r := range svc.libraryRoots() {
		if r.Name == "lib" {
			root = r.Path
		}
	}
	lockFolder(t, root)
	_, _, err := svc.DecideReviewEntry(ctx, uc, id, "as-is", "")
	if KindOf(err) != KindStorageUnwritable {
		t.Fatalf("decision = %v (%s), want storage-unwritable", err, KindOf(err))
	}
	wantPlainRefusal(t, svc, err)
	if msg := err.Error(); !strings.Contains(msg, "permission denied") || strings.Contains(msg, root) {
		t.Fatalf("refusal %q, want the refusal in words without the library's folder", msg)
	}
	stagedStill(t, ctx, svc, up.ID)
}
