package api

import (
	"encoding/json"
	"reflect"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// fillNonZero sets every exported scalar field of the struct v points
// at, and of the structs its pointer fields point at, to a value that is
// not its zero, so an omitempty field is on the wire.
func fillNonZero(v reflect.Value) {
	for i := range v.NumField() {
		f := v.Field(i)
		if !f.CanSet() {
			continue
		}
		switch f.Kind() {
		case reflect.String:
			f.SetString("x")
		case reflect.Int, reflect.Int64:
			f.SetInt(7)
		case reflect.Float64:
			f.SetFloat(1.5)
		case reflect.Bool:
			f.SetBool(true)
		case reflect.Pointer:
			if f.Type().Elem().Kind() == reflect.Struct {
				f.Set(reflect.New(f.Type().Elem()))
				fillNonZero(f.Elem())
			}
		case reflect.Struct:
			if f.Type() == reflect.TypeFor[time.Time]() {
				f.Set(reflect.ValueOf(time.Unix(1_700_000_000, 0).UTC()))
			}
		}
	}
}

// wantSuperset fails unless every field base puts on the wire is on out
// with the same value.
func wantSuperset(t *testing.T, name string, base, out any) {
	t.Helper()
	asMap := func(v any) map[string]any {
		raw, err := json.Marshal(v)
		if err != nil {
			t.Fatal(err)
		}
		var m map[string]any
		if err := json.Unmarshal(raw, &m); err != nil {
			t.Fatal(err)
		}
		return m
	}
	b, o := asMap(base), asMap(out)
	for k, v := range b {
		if !reflect.DeepEqual(o[k], v) {
			t.Errorf("%s: %s = %v, want %v as its base has it", name, k, o[k], v)
		}
	}
}

// An answer the generator flattens from an allOf carries every field of
// the schema it extends; the hand copy is what drops one when the base
// grows.
func TestFlattenedAnswersCarryTheirBase(t *testing.T) {
	var detail service.ReviewDetailDTO
	fillNonZero(reflect.ValueOf(&detail.ReviewEntryDTO).Elem())
	wantSuperset(t, "review entry detail", reviewEntryJSON(detail.ReviewEntryDTO), reviewDetailJSON(detail))

	var lib service.LibraryInfo
	fillNonZero(reflect.ValueOf(&lib).Elem())
	wantSuperset(t, "created library", libraryDTO(lib), libraryCreatedJSON(lib))
	wantSuperset(t, "library media change", libraryDTO(lib), libraryMediaChangedJSON(lib))
}
