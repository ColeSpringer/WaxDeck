package api

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// Every counter the service carries goes out under its own camelCase name,
// including one a later WaxBin adds.
func TestEnrichmentLastRunNamesEveryCounter(t *testing.T) {
	t.Parallel()
	var dto service.EnrichmentLastRunDTO
	dv := reflect.ValueOf(&dto).Elem()
	want := map[string]float64{}
	for i := range dv.NumField() {
		if f := dv.Field(i); f.Kind() == reflect.Int {
			f.SetInt(int64(i + 1))
			name := dv.Type().Field(i).Name
			want[strings.ToLower(name[:1])+name[1:]] = float64(i + 1)
		}
	}
	raw, err := json.Marshal(enrichmentLastRun(&dto))
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatal(err)
	}
	if len(got) != len(want) {
		t.Errorf("last run carries %d keys, want %d: %s", len(got), len(want), raw)
	}
	for key, n := range want {
		if got[key] != n {
			t.Errorf("%s = %v, want %v", key, got[key], n)
		}
	}
}
