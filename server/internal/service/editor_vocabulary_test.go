package service

import (
	"testing"

	"github.com/colespringer/waxbin/meta"
)

// A book field writes back exactly when the catalog's writer has a tag
// for it: series through its packed grouping, the rest through the
// writer's own book mapping.
func TestTheBookVocabularyMatchesTheWriter(t *testing.T) {
	t.Parallel()
	for _, f := range editorBookFields {
		_, mapped := meta.BookFieldTagKeys(f.Name)
		if want := mapped || f.Name == "series"; f.WriteBack != want {
			t.Errorf("book %s writeBack = %v, want %v as the writer has it", f.Name, f.WriteBack, want)
		}
	}
}
