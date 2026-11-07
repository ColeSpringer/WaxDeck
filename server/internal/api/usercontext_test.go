package api

import (
	"context"
	"go/ast"
	"go/parser"
	"go/token"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// openCallerLibrary is a service over a fresh database, for resolving
// callers against real grants.
func openCallerLibrary(t *testing.T) (*service.Library, *db.DB) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	log := slog.New(slog.DiscardHandler)
	dataDir := t.TempDir()
	store, err := db.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })
	group := supervise.NewGroup(log)
	svc, err := service.Open(ctx, service.Config{DataDir: dataDir, Logger: log}, store, group)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cancel()
		group.Wait()
		svc.Close()
	})
	return svc, store
}

// The middleware resolves the caller ahead of every secured operation and
// of nothing else. Operations go by the generated method's name, which is
// what the strict handler passes its middlewares.
func TestUserContextMiddlewareResolvesOnlySecuredOperations(t *testing.T) {
	t.Parallel()
	svc, store := openCallerLibrary(t)
	ctx := context.Background()
	user := &db.User{ID: "us-granted", Username: "granted", LibraryAccess: "granted"}
	if err := store.CreateUser(ctx, user, false); err != nil {
		t.Fatal(err)
	}
	if err := store.SetLibraryGrants(ctx, user.ID, []string{"lib-a"}); err != nil {
		t.Fatal(err)
	}
	s := &Server{svc: svc}
	signedIn := context.WithValue(ctx, ctxPrincipal, &auth.Principal{User: user})
	worker := context.WithValue(ctx, ctxWorkerKey{}, true)

	run := func(ctx context.Context, operationID string) (uc *service.UserCtx, ran bool, err error) {
		f := func(ctx context.Context, _ http.ResponseWriter, _ *http.Request, _ any) (any, error) {
			uc, ran = userCtx(ctx), true
			return nil, nil
		}
		_, err = s.userContextMiddleware(f, operationID)(ctx, httptest.NewRecorder(),
			httptest.NewRequest(http.MethodGet, "/", nil), nil)
		return uc, ran, err
	}

	// A public operation resolves nobody, even with a session in hand.
	for _, c := range []context.Context{ctx, signedIn} {
		if uc, ran, err := run(c, "GetHealth"); !ran || uc != nil || err != nil {
			t.Errorf("GetHealth: ran %v, user %+v, err %v; want it run with no user", ran, uc, err)
		}
	}

	uc, ran, err := run(signedIn, "ListPlaylists")
	if !ran || err != nil || uc == nil {
		t.Fatalf("ListPlaylists: ran %v, user %+v, err %v; want it run with the caller", ran, uc, err)
	}
	if uc.ID != user.ID || uc.AllLibraries || len(uc.Libraries) != 1 || !uc.Libraries["lib-a"] {
		t.Errorf("ListPlaylists resolved %+v, want %s granted lib-a alone", uc, user.ID)
	}

	// A worker operation has no user to resolve, whoever asks.
	for _, c := range []struct {
		name string
		ctx  context.Context
		op   string
	}{
		{"worker", worker, "PullSimilarityWork"},
		{"unmarked", ctx, "ReportEmbeddings"},
		{"signed in", signedIn, "ReportEmbeddings"},
	} {
		if uc, ran, err := run(c.ctx, c.op); !ran || uc != nil || err != nil {
			t.Errorf("%s on %s: ran %v, user %+v, err %v; want it run with no user", c.name, c.op, ran, uc, err)
		}
	}

	// The worker token opens worker operations alone: a worker request on
	// a secured one is refused, a session in hand or not.
	for _, c := range []struct {
		name string
		ctx  context.Context
	}{
		{"worker", worker},
		{"worker with a session", context.WithValue(signedIn, ctxWorkerKey{}, true)},
	} {
		if _, ran, err := run(c.ctx, "ListPlaylists"); ran || service.KindOf(err) != service.KindUnauthenticated {
			t.Errorf("%s on ListPlaylists: ran %v, err %v; want it refused unauthenticated", c.name, ran, err)
		}
	}

	// Nobody signed in is refused a secured operation, and an operation
	// the contract does not name counts as secured.
	for _, op := range []string{"ListPlaylists", "NoSuchOperation"} {
		if _, ran, err := run(ctx, op); ran || service.KindOf(err) != service.KindUnauthenticated {
			t.Errorf("%s with no principal: ran %v, err %v; want it refused unauthenticated", op, ran, err)
		}
	}
	if uc, ran, err := run(signedIn, "NoSuchOperation"); !ran || err != nil || uc == nil || uc.ID != user.ID {
		t.Errorf("NoSuchOperation: ran %v, user %+v, err %v; want it run with the caller", ran, uc, err)
	}
}

// A server with no service resolves no user, so a secured operation that
// reads only the principal answers as its handler does; the backstop
// still refuses one reached with no principal or with the worker token.
func TestAServerWithNoServiceResolvesNoUser(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	store, err := db.Open(ctx, filepath.Join(t.TempDir(), "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })
	user := &db.User{ID: "us-sessions", Username: "sessions"}
	if err := store.CreateUser(ctx, user, false); err != nil {
		t.Fatal(err)
	}
	sessions := auth.NewSessions(store)
	created, err := sessions.Create(ctx, user.ID, "device", "phone", "")
	if err != nil {
		t.Fatal(err)
	}
	srv := NewServer("test", Options{Sessions: sessions})
	mux := http.NewServeMux()
	mux.Handle("/api/v1/", srv.Handler())
	ts := httptest.NewServer(mux)
	t.Cleanup(ts.Close)

	resp := get(t, ts, "/api/v1/auth/sessions", created.Token)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("listing sessions: %d, want 200", resp.StatusCode)
	}
	if list := decode[SessionList](t, resp); len(list.Sessions) != 1 ||
		list.Sessions[0].Id != created.Session.ID || !list.Sessions[0].Current {
		t.Errorf("listing sessions: %+v, want the caller's one", list)
	}
	resp = postJSON(t, ts.URL+"/api/v1/auth/refresh", created.Token, "")
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("refreshing the token: %d, want 200", resp.StatusCode)
	}
	if login := decode[LoginResponse](t, resp); login.Token == "" || login.Token == created.Token {
		t.Errorf("refreshing the token: %+v, want a new token", login)
	}

	run := func(ctx context.Context) (uc *service.UserCtx, ran bool, err error) {
		f := func(ctx context.Context, _ http.ResponseWriter, _ *http.Request, _ any) (any, error) {
			uc, ran = userCtx(ctx), true
			return nil, nil
		}
		_, err = srv.userContextMiddleware(f, "ListSessions")(ctx, httptest.NewRecorder(),
			httptest.NewRequest(http.MethodGet, "/", nil), nil)
		return uc, ran, err
	}
	signedIn := context.WithValue(ctx, ctxPrincipal, &auth.Principal{User: user, Session: created.Session})
	if uc, ran, err := run(signedIn); !ran || uc != nil || err != nil {
		t.Errorf("signed in: ran %v, user %+v, err %v; want it run with no user", ran, uc, err)
	}
	for _, c := range []struct {
		name string
		ctx  context.Context
	}{
		{"no principal", ctx},
		{"the worker token", context.WithValue(ctx, ctxWorkerKey{}, true)},
		{"the worker token with a session", context.WithValue(signedIn, ctxWorkerKey{}, true)},
	} {
		if _, ran, err := run(c.ctx); ran || service.KindOf(err) != service.KindUnauthenticated {
			t.Errorf("%s: ran %v, err %v; want it refused unauthenticated", c.name, ran, err)
		}
	}
}

// The generator writes each operation's method name into the embedded
// contract, which the access table is keyed by; a name missing from it
// would silently count as secured.
func TestOperationAccessKnowsEveryHandler(t *testing.T) {
	t.Parallel()
	methods := reflect.TypeFor[StrictServerInterface]()
	for i := range methods.NumMethod() {
		name := methods.Method(i).Name
		if _, ok := operationAccess()[name]; !ok {
			t.Errorf("%s is not in the contract under its method name", name)
		}
	}
	if got, want := len(operationAccess()), methods.NumMethod(); got != want {
		t.Errorf("the contract names %d operations, the strict handler %d", got, want)
	}
}

// AuthMiddleware reads the pattern the generated router registered and
// routing set on the request, so every route gen.go registers is in
// routeAccess with its operation's access, and routeAccess holds no
// other.
func TestRouteAccessKnowsEveryRegisteredRoute(t *testing.T) {
	t.Parallel()
	routes := registeredRoutes(t)
	if len(routes) == 0 {
		t.Fatal("found no route registration in gen.go; the walk is reading the wrong thing")
	}
	for _, r := range routes {
		want, ok := operationAccess()[r.operation]
		if !ok {
			t.Errorf("gen.go registers %q for %s, which the contract does not name", r.pattern, r.operation)
			continue
		}
		if got, listed := routeAccess()[r.pattern]; !listed || got != want {
			t.Errorf("%s: routeAccess answers %s for %q (listed %v), operationAccess %s", r.operation, accessNames[got], r.pattern, listed, accessNames[want])
		}
	}
	if got, want := len(routeAccess()), len(routes); got != want {
		t.Errorf("routeAccess holds %d routes, gen.go registers %d", got, want)
	}
}

// A public operation takes no CSRF proof: a browser signs out with its
// session cookie alone, and the session ends.
func TestPublicOperationsTakeNoCSRFProof(t *testing.T) {
	t.Parallel()
	ts := newAuthTestServer(t)
	lr := bootstrap(t, ts)
	req, _ := http.NewRequest(http.MethodPost, ts.URL+"/api/v1/auth/logout", nil)
	req.AddCookie(&http.Cookie{Name: sessionCookie, Value: lr.Token})
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("signing out by cookie without CSRF proof: %d, want 204", resp.StatusCode)
	}
	resp = get(t, ts, "/api/v1/library/items", lr.Token)
	resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("the session after signing out: %d, want 401", resp.StatusCode)
	}
}

// A pattern the contract does not name is secured: a request served
// outside any router carries none, even on a public operation's path, and
// the event channel's pattern is main's, not the contract's.
func TestAnUnnamedPatternIsSecured(t *testing.T) {
	t.Parallel()
	srv := NewServer("test", Options{})
	for _, c := range []struct{ path, pattern string }{
		{"/api/v1/health", ""},
		{"/api/v1/ws", "GET /api/v1/ws"},
	} {
		ran := false
		next := http.HandlerFunc(func(http.ResponseWriter, *http.Request) { ran = true })
		req := httptest.NewRequest(http.MethodGet, c.path, nil)
		req.Pattern = c.pattern
		rec := httptest.NewRecorder()
		srv.AuthMiddleware(next).ServeHTTP(rec, req)
		if rec.Code != http.StatusUnauthorized || ran {
			t.Errorf("anonymous GET %s with pattern %q: %d, next ran %v; want 401 and next never run", c.path, c.pattern, rec.Code, ran)
		}
	}
}

var accessNames = map[opAccess]string{opSecured: "secured", opPublic: "public", opWorker: "worker"}

type registeredRoute struct{ pattern, operation string }

// registeredRoutes is each route HandlerWithOptions registers in gen.go:
// its pattern, evaluated with the BaseURL Handler passes, and the wrapper
// method it routes to, which is named for its operation.
func registeredRoutes(t *testing.T) []registeredRoute {
	t.Helper()
	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, "gen.go", nil, parser.SkipObjectResolution)
	if err != nil {
		t.Fatal(err)
	}
	var out []registeredRoute
	for _, decl := range f.Decls {
		fn, ok := decl.(*ast.FuncDecl)
		if !ok || fn.Recv != nil || fn.Name.Name != "HandlerWithOptions" {
			continue
		}
		ast.Inspect(fn.Body, func(n ast.Node) bool {
			call, ok := n.(*ast.CallExpr)
			if !ok {
				return true
			}
			if sel, ok := call.Fun.(*ast.SelectorExpr); !ok || sel.Sel.Name != "HandleFunc" {
				return true
			}
			if len(call.Args) == 2 {
				pattern, ok := patternOf(call.Args[0])
				if wrapper, isSel := call.Args[1].(*ast.SelectorExpr); ok && isSel {
					out = append(out, registeredRoute{pattern, wrapper.Sel.Name})
					return true
				}
			}
			t.Errorf("%s: a route registration this cannot read", fset.Position(call.Pos()))
			return true
		})
	}
	return out
}

// patternOf evaluates a registration's pattern, a sum of http.Method
// constants, string literals and options.BaseURL.
func patternOf(e ast.Expr) (string, bool) {
	switch e := e.(type) {
	case *ast.BinaryExpr:
		x, xok := patternOf(e.X)
		y, yok := patternOf(e.Y)
		return x + y, xok && yok && e.Op == token.ADD
	case *ast.BasicLit:
		s, err := strconv.Unquote(e.Value)
		return s, err == nil && e.Kind == token.STRING
	case *ast.SelectorExpr:
		pkg, ok := e.X.(*ast.Ident)
		switch {
		case ok && pkg.Name == "options" && e.Sel.Name == "BaseURL":
			return apiBaseURL, true
		case ok && pkg.Name == "http" && strings.HasPrefix(e.Sel.Name, "Method"):
			return strings.ToUpper(strings.TrimPrefix(e.Sel.Name, "Method")), true
		}
	}
	return "", false
}
