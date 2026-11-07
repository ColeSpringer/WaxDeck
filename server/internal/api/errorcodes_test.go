package api

import (
	"encoding/json"
	"errors"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"maps"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"testing"

	"github.com/getkin/kin-openapi/openapi3"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// specPreamble is the authored fragment that documents the error codes.
var specPreamble = filepath.Join("..", "..", "..", "api", "spec", "_root.yaml")

// definedErrorCodes is the error vocabulary the contract documents. It is
// prose in the spec preamble rather than a schema enum, so this reads the
// backticked words of the code list. Against the authored fragment, not
// the generated bundle, so a code deleted from the vocabulary fails here
// rather than passing on a stale bundle; and against the list alone, since
// every one of these words also appears in ordinary prose elsewhere.
func definedErrorCodes(t *testing.T) map[string]bool {
	t.Helper()
	spec, err := os.ReadFile(specPreamble)
	if err != nil {
		t.Fatalf("reading the spec preamble: %v", err)
	}
	const (
		opens  = "currently defined codes:"
		closes = "New codes may appear"
	)
	_, after, found := strings.Cut(string(spec), opens)
	if !found {
		t.Fatalf("%s no longer says %q; this guard is reading the wrong thing", specPreamble, opens)
	}
	list, _, found := strings.Cut(after, closes)
	if !found {
		t.Fatalf("%s no longer says %q; this guard is reading the wrong thing", specPreamble, closes)
	}
	codes := map[string]bool{}
	for _, m := range regexp.MustCompile("`([^`]+)`").FindAllStringSubmatch(list, -1) {
		codes[m[1]] = true
	}
	return codes
}

// Every code the package answers by kind, by the refusal whitelist, or as
// a literal handed to refuse is one the contract documents; and refusals
// are built only by refuse and refusalError, so none carries a code this
// cannot read.
func TestErrorCodesAreDocumented(t *testing.T) {
	t.Parallel()
	defined := definedErrorCodes(t)
	for kind, c := range kindCodes {
		if !defined[c.code] {
			t.Errorf("kind %q answers %q, which is not in the code list in %s", kind, c.code, specPreamble)
		}
	}
	for code := range refusalCodes {
		if !defined[code] {
			t.Errorf("refusal code %q is not in the code list in %s", code, specPreamble)
		}
	}
	refused := refuseLiterals(t)
	if len(refused) == 0 {
		t.Fatal("found no code literal handed to refuse; the walk is reading the wrong thing")
	}
	for _, r := range refused {
		if !defined[r.code] {
			t.Errorf("%s refuses with %q, which is not in the code list in %s", r.at, r.code, specPreamble)
		}
	}
}

type refuseLiteral struct{ code, at string }

// refuseLiterals is each string literal the package's own code hands
// refuse as its code. A refuse whose code is no literal, and a wireError
// built outside wireerror.go, fail the test where they stand.
func refuseLiterals(t *testing.T) []refuseLiteral {
	t.Helper()
	names, err := filepath.Glob("*.go")
	if err != nil {
		t.Fatal(err)
	}
	fset := token.NewFileSet()
	var out []refuseLiteral
	for _, name := range names {
		if strings.HasSuffix(name, "_test.go") {
			continue
		}
		f, err := parser.ParseFile(fset, name, nil, parser.SkipObjectResolution)
		if err != nil {
			t.Fatal(err)
		}
		ast.Inspect(f, func(n ast.Node) bool {
			switch n := n.(type) {
			case *ast.CompositeLit:
				if typ, ok := n.Type.(*ast.Ident); ok && typ.Name == "wireError" && name != "wireerror.go" {
					t.Errorf("%s builds a wireError; refuse through refuse or refusalError", fset.Position(n.Pos()))
				}
			case *ast.CallExpr:
				if fn, ok := n.Fun.(*ast.Ident); !ok || fn.Name != "refuse" || len(n.Args) != 3 {
					return true
				}
				lit, ok := n.Args[1].(*ast.BasicLit)
				if !ok || lit.Kind != token.STRING {
					t.Errorf("%s hands refuse a code that is not a string literal", fset.Position(n.Args[1].Pos()))
					return true
				}
				code, err := strconv.Unquote(lit.Value)
				if err != nil {
					t.Fatal(err)
				}
				out = append(out, refuseLiteral{code, fset.Position(lit.Pos()).String()})
			}
			return true
		})
	}
	return out
}

// responseOf is what responseError writes for err: the status, the decoded
// body, and the body's fields as sent.
func responseOf(t *testing.T, err error) (int, Error, map[string]json.RawMessage) {
	t.Helper()
	rec := httptest.NewRecorder()
	responseError(rec, err)
	if got := rec.Header().Get("Content-Type"); got != "application/json" {
		t.Errorf("%v: Content-Type %q, want application/json", err, got)
	}
	var body Error
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decoding %q: %v", rec.Body.String(), err)
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &fields); err != nil {
		t.Fatalf("decoding %q: %v", rec.Body.String(), err)
	}
	return rec.Code, body, fields
}

// Clients word their errors by these, so each kind keeps its status, code
// and fallback words; a service error's own words replace the fallback,
// save the maintenance answer's, which are fixed.
func TestKindAnswersArePinned(t *testing.T) {
	t.Parallel()
	want := map[service.ErrorKind]struct {
		status        int
		code, message string
	}{
		service.KindMaintenance:       {http.StatusServiceUnavailable, "catalog-maintenance", "the catalog is temporarily under maintenance; retry shortly"},
		service.KindNotFound:          {http.StatusNotFound, "not-found", "not found"},
		service.KindInvalid:           {http.StatusBadRequest, "invalid-request", "invalid request"},
		service.KindConflict:          {http.StatusConflict, "conflict", "a conflicting operation is running"},
		service.KindCatalogBusy:       {http.StatusConflict, "catalog-busy", "another catalog job holds the file-mutation scope; retry shortly"},
		service.KindGone:              {http.StatusGone, "sync-reset", "re-mirror from a fresh snapshot"},
		service.KindForbidden:         {http.StatusForbidden, "forbidden", "not allowed"},
		service.KindUnsupported:       {http.StatusNotImplemented, "source-unavailable", "this server is not running the needed integration"},
		service.KindUpstream:          {http.StatusBadGateway, "feed-unreachable", "the upstream feed could not be fetched"},
		service.KindDirectory:         {http.StatusBadGateway, "directory-unavailable", "the external directory could not be reached"},
		service.KindService:           {http.StatusBadGateway, "service-unreachable", "an external service could not be reached"},
		service.KindQuota:             {http.StatusRequestEntityTooLarge, "quota-exceeded", "the upload would exceed your storage quota"},
		service.KindStorageFull:       {http.StatusInsufficientStorage, "storage-full", "the server has no room to stage this"},
		service.KindLocked:            {http.StatusConflict, "field-locked", "the field is locked; pass force to override"},
		service.KindFormat:            {http.StatusUnsupportedMediaType, "unsupported-format", "the file's format is not accepted"},
		service.KindDRM:               {http.StatusUnsupportedMediaType, "drm-protected", "the file is DRM-encrypted and can never play"},
		service.KindFeature:           {http.StatusNotImplemented, "feature-unavailable", "this server is not running the needed capability"},
		service.KindReadOnly:          {http.StatusConflict, "read-only", "the server or the target library is read-only"},
		service.KindStorageUnwritable: {http.StatusConflict, "storage-unwritable", "a library folder refused the write"},
		service.KindTranscodeLimit:    {http.StatusTooManyRequests, "transcode-limited", "the transcode session limit is reached"},
		service.KindInternal:          {http.StatusInternalServerError, "internal", "internal server error"},
		service.KindUnauthenticated:   {http.StatusUnauthorized, "unauthenticated", "no valid session or token was presented"},
	}
	for kind := range kindCodes {
		if _, pinned := want[kind]; !pinned {
			t.Errorf("%s answers from kindCodes but has no pinned answer here", kind)
		}
	}
	const own = "the service's own words"
	for kind, w := range want {
		status, body, _ := responseOf(t, &service.Error{Kind: kind})
		if status != w.status || body.Code != w.code || body.Message != w.message {
			t.Errorf("%s: answered %d %q %q, want %d %q %q", kind, status, body.Code, body.Message, w.status, w.code, w.message)
		}
		wantMessage := own
		if kind == service.KindMaintenance {
			wantMessage = w.message
		}
		status, body, _ = responseOf(t, &service.Error{Kind: kind, Msg: own})
		if status != w.status || body.Code != w.code || body.Message != wantMessage {
			t.Errorf("%s with its own words: answered %d %q %q, want %d %q %q", kind, status, body.Code, body.Message, w.status, w.code, wantMessage)
		}
	}
}

// A kind with no row answers 500 internal, so every ErrorKind the service
// declares has one.
func TestEveryServiceKindHasARow(t *testing.T) {
	t.Parallel()
	kinds := serviceKinds(t)
	if len(kinds) == 0 {
		t.Fatal("found no ErrorKind constant in the service; the walk is reading the wrong thing")
	}
	declared := map[service.ErrorKind]bool{}
	for _, name := range slices.Sorted(maps.Keys(kinds)) {
		declared[kinds[name]] = true
		if _, ok := kindCodes[kinds[name]]; !ok {
			t.Errorf("service.%s has no row in kindCodes, so it answers 500 internal", name)
		}
	}
	for kind := range kindCodes {
		if !declared[kind] {
			t.Errorf("kindCodes answers %q, which no constant the walk found holds; the walk is missing a declaration", kind)
		}
	}
}

// serviceKinds is each ErrorKind constant in the service's non-test
// files, by name: constants cannot be listed at run time, so this reads
// the source.
func serviceKinds(t *testing.T) map[string]service.ErrorKind {
	t.Helper()
	names, err := filepath.Glob(filepath.Join("..", "service", "*.go"))
	if err != nil {
		t.Fatal(err)
	}
	isKind := func(e ast.Expr) bool {
		id, ok := e.(*ast.Ident)
		return ok && id.Name == "ErrorKind"
	}
	fset := token.NewFileSet()
	out := map[string]service.ErrorKind{}
	for _, name := range names {
		if strings.HasSuffix(name, "_test.go") {
			continue
		}
		f, err := parser.ParseFile(fset, name, nil, parser.SkipObjectResolution)
		if err != nil {
			t.Fatal(err)
		}
		for _, decl := range f.Decls {
			gen, ok := decl.(*ast.GenDecl)
			if !ok || gen.Tok != token.CONST {
				continue
			}
			var typ ast.Expr
			var values []ast.Expr
			for _, spec := range gen.Specs {
				vs := spec.(*ast.ValueSpec)
				// A spec with neither type nor value repeats the one before.
				if vs.Type != nil || vs.Values != nil {
					typ, values = vs.Type, vs.Values
				}
				for i, id := range vs.Names {
					if i >= len(values) {
						continue
					}
					value := values[i]
					call, converted := value.(*ast.CallExpr)
					converted = converted && isKind(call.Fun) && len(call.Args) == 1
					if !converted && !isKind(typ) {
						continue
					}
					if converted {
						value = call.Args[0]
					}
					lit, ok := value.(*ast.BasicLit)
					if !ok || lit.Kind != token.STRING {
						t.Errorf("%s: cannot read the value of %s", fset.Position(value.Pos()), id.Name)
						continue
					}
					kind, err := strconv.Unquote(lit.Value)
					if err != nil {
						t.Fatal(err)
					}
					out[id.Name] = service.ErrorKind(kind)
				}
			}
		}
	}
	return out
}

// What the error holds reaches the body: a service error's params, and a
// refusal's own status, code, message and params.
func TestResponseErrorCarriesWhatTheErrorHolds(t *testing.T) {
	t.Parallel()
	params := map[string]string{"reason": "task-running", "task": "tt-1"}
	status, body, _ := responseOf(t, &service.Error{Kind: service.KindConflict, Msg: "a merge is running", Params: params})
	if status != http.StatusConflict || body.Code != "conflict" || body.Message != "a merge is running" ||
		body.Params == nil || !maps.Equal(*body.Params, params) {
		t.Errorf("service error with params: %d %+v, want 409 conflict carrying %v", status, body, params)
	}

	refusal := &wireError{Status: http.StatusTooManyRequests, Code: "rate-limited", Message: "slow down",
		Params: map[string]string{"retryAfter": "5"}}
	status, body, _ = responseOf(t, fmt.Errorf("wrapped: %w", refusal))
	if status != http.StatusTooManyRequests || body.Code != "rate-limited" || body.Message != "slow down" ||
		body.Params == nil || !maps.Equal(*body.Params, refusal.Params) {
		t.Errorf("refusal: %d %+v, want it as it stands", status, body)
	}

	// The refusal whitelist codes a refusal, degrading a code it does not
	// know and keeping the words either way.
	if status, body, _ := responseOf(t, refusalError("queue-end", "nothing after this")); status != http.StatusConflict ||
		body.Code != "queue-end" || body.Message != "nothing after this" {
		t.Errorf("whitelisted refusal: %d %+v, want 409 queue-end", status, body)
	}
	if status, body, _ := responseOf(t, refusalError("wat", "the client said no")); status != http.StatusBadRequest ||
		body.Code != "invalid-request" || body.Message != "the client said no" {
		t.Errorf("unlisted refusal: %d %+v, want 400 invalid-request", status, body)
	}

	// Neither an unclassed failure nor a kind the table does not know says
	// anything of itself.
	for _, err := range []error{
		errors.New("sql: no such table: users"),
		&service.Error{Kind: "made-up", Msg: "a detail for the log"},
	} {
		if status, body, _ := responseOf(t, err); status != http.StatusInternalServerError ||
			body.Code != "internal" || body.Message != "internal server error" {
			t.Errorf("%v: %d %+v, want 500 internal with the fixed words", err, status, body)
		}
	}

	// No params, or an empty set, leaves the field out.
	for _, err := range []error{
		&service.Error{Kind: service.KindNotFound},
		&service.Error{Kind: service.KindNotFound, Params: map[string]string{}},
		refuse(http.StatusBadRequest, "invalid-request", "no"),
		&wireError{Status: http.StatusBadRequest, Code: "invalid-request", Message: "no", Params: map[string]string{}},
	} {
		if _, _, fields := responseOf(t, err); fields["params"] != nil {
			t.Errorf("%v: sent params %s, want the field left out", err, fields["params"])
		}
	}
}

// A refusal whose status is not an error's is the handler's bug, and
// answers 500 internal with the fixed words rather than reaching
// WriteHeader, which panics on some statuses and sends others as no
// error at all.
func TestAStatusOutsideTheErrorRangeAnswersInternal(t *testing.T) {
	t.Parallel()
	for _, status := range []int{399, 600, 0, 4000} {
		refusal := &wireError{Status: status, Code: "invalid-request", Message: "the handler's words",
			Params: map[string]string{"reason": "made-up"}}
		got, body, fields := responseOf(t, refusal)
		if got != http.StatusInternalServerError || body.Code != "internal" ||
			body.Message != "internal server error" || fields["params"] != nil {
			t.Errorf("status %d: answered %d %+v, want 500 internal with the fixed words", status, got, body)
		}
	}
	for _, status := range []int{http.StatusBadRequest, 599} {
		if got, body, _ := responseOf(t, refuse(status, "invalid-request", "kept")); got != status ||
			body.Code != "invalid-request" || body.Message != "kept" {
			t.Errorf("status %d: answered %d %+v, want it as it stands", status, got, body)
		}
	}
}

// Each missing-body refusal is its own: a caller changing the one it got
// leaves the next caller's as it was.
func TestEachMissingBodyRefusalIsItsOwn(t *testing.T) {
	t.Parallel()
	var first *wireError
	if !errors.As(errNoBody(), &first) {
		t.Fatal("errNoBody is not a refusal")
	}
	first.Status, first.Message = http.StatusTeapot, "changed by its caller"
	if status, body, _ := responseOf(t, errNoBody()); status != http.StatusBadRequest ||
		body.Code != "invalid-request" || body.Message != "a request body is required" {
		t.Errorf("after a caller changed its own: %d %+v, want 400 invalid-request", status, body)
	}
}

// AuthMiddleware opens a request by the route it was routed by, the
// user-context middleware by its operation's name, and both agree with
// the contract as this reads it: an operation declaring none inherits the
// global requirement, an empty one is public, and one naming workerAuth
// is the worker's. An empty requirement object admits anonymous callers,
// which neither middleware supports, so no operation may hold one.
func TestOperationAndRouteAccessAreTheContracts(t *testing.T) {
	t.Parallel()
	spec, err := GetSpec()
	if err != nil {
		t.Fatal(err)
	}
	if len(spec.Security) == 0 || namesWorker(spec.Security) {
		t.Fatalf("the global requirement %v is no longer a user's credential", spec.Security)
	}
	for path, item := range spec.Paths.Map() {
		for method, op := range item.Operations() {
			reqs, want := spec.Security, opSecured
			if op.Security != nil {
				reqs = *op.Security
			}
			switch {
			case op.Security == nil:
				// The global requirement, checked above.
			case len(*op.Security) == 0:
				want = opPublic
			case namesWorker(*op.Security):
				want = opWorker
			}
			if slices.ContainsFunc(reqs, func(req openapi3.SecurityRequirement) bool { return len(req) == 0 }) {
				t.Errorf("%s admits anonymous callers through an empty security requirement, which neither AuthMiddleware nor the user-context middleware supports", op.OperationID)
			}
			if got := operationAccess()[op.OperationID]; got != want {
				t.Errorf("%s: operationAccess answers %s, the contract %s", op.OperationID, accessNames[got], accessNames[want])
			}
			route := method + " " + apiBaseURL + path
			if got, listed := routeAccess()[route]; !listed || got != want {
				t.Errorf("%s: routeAccess answers %s for %q (listed %v), the contract %s", op.OperationID, accessNames[got], route, listed, accessNames[want])
			}
		}
	}
}

func namesWorker(reqs openapi3.SecurityRequirements) bool {
	for _, req := range reqs {
		if _, ok := req["workerAuth"]; ok {
			return true
		}
	}
	return false
}
