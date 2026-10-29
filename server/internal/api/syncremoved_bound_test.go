package api

import (
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// The removed-check's page bound is the service's, and the contract states
// the same one: the request's maxItems is that bound, and its minItems the
// empty list the service refuses.
func TestTheRemovedCheckBoundIsTheContracts(t *testing.T) {
	t.Parallel()
	spec, err := GetSpec()
	if err != nil {
		t.Fatal(err)
	}
	item := spec.Paths.Find("/sync/catalog/removed")
	if item == nil || item.Post == nil || item.Post.RequestBody == nil || item.Post.RequestBody.Value == nil {
		t.Fatal("the contract has no removed-check request")
	}
	body := item.Post.RequestBody.Value.Content.Get("application/json")
	if body == nil || body.Schema == nil || body.Schema.Value == nil {
		t.Fatal("the removed-check request has no JSON body")
	}
	pids := body.Schema.Value.Properties["pids"]
	if pids == nil || pids.Value == nil || pids.Value.MaxItems == nil {
		t.Fatal("the removed-check request states no bound on its pids")
	}
	if got := *pids.Value.MaxItems; got != service.MaxRemovedAsk {
		t.Errorf("the contract bounds the pids at %d, the service at %d", got, service.MaxRemovedAsk)
	}
	if got := pids.Value.MinItems; got != 1 {
		t.Errorf("the contract's minItems = %d, want 1: the service refuses an empty list", got)
	}
}
