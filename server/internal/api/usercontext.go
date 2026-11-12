package api

import (
	"context"
	"net/http"
	"sync"

	"github.com/getkin/kin-openapi/openapi3"

	"github.com/colespringer/waxdeck/server/internal/service"
)

type ctxUserKey struct{}

// userCtx is the caller the user-context middleware resolved: non-nil
// for every secured operation, save on a server built without a service.
func userCtx(ctx context.Context) *service.UserCtx {
	uc, _ := ctx.Value(ctxUserKey{}).(*service.UserCtx)
	return uc
}

// requireAdmin refuses any caller but an administrator.
func requireAdmin(ctx context.Context) error {
	if p, ok := principalFromContext(ctx); !ok || !p.IsAdmin() {
		return refuse(http.StatusForbidden, "forbidden", "administrators only")
	}
	return nil
}

// opAccess is whom an operation's security admits. The zero value is
// secured, so an operation or route the contract does not name counts as
// one.
type opAccess int

const (
	opSecured opAccess = iota // a user's session or token
	opPublic                  // anyone: `security: []`
	opWorker                  // the similarity worker token
)

// contractAccess classes each operation by the security the embedded
// contract gives it, keyed two ways: by the name the strict handler
// passes its middlewares (the generator writes that name into the
// embedded spec), and by the route pattern the generated router
// registers it under, which routing sets as the request's Pattern.
var contractAccess = sync.OnceValues(func() (byOperation, byRoute map[string]opAccess) {
	spec, err := GetSpec()
	if err != nil {
		panic("the embedded contract does not load: " + err.Error())
	}
	byOperation, byRoute = map[string]opAccess{}, map[string]opAccess{}
	for path, item := range spec.Paths.Map() {
		for method, op := range item.Operations() {
			reqs := spec.Security
			if op.Security != nil {
				reqs = *op.Security
			}
			access := accessOf(reqs)
			byOperation[op.OperationID] = access
			byRoute[method+" "+apiBaseURL+path] = access
		}
	}
	return byOperation, byRoute
})

// operationAccess is whom each operation admits, by operation name.
func operationAccess() map[string]opAccess {
	byOperation, _ := contractAccess()
	return byOperation
}

// routeAccess is whom each operation admits, by the pattern the generated
// router registers it under: its method, a space, and its path under
// apiBaseURL.
func routeAccess() map[string]opAccess {
	_, byRoute := contractAccess()
	return byRoute
}

// accessOf reads an operation's effective requirements: none is public,
// the worker scheme alone is the worker's, and anything else is secured,
// an empty requirement (anonymous allowed) included, since neither
// AuthMiddleware nor userContextMiddleware supports optional auth.
func accessOf(reqs openapi3.SecurityRequirements) opAccess {
	if len(reqs) == 0 {
		return opPublic
	}
	for _, req := range reqs {
		if _, ok := req["workerAuth"]; !ok || len(req) != 1 {
			return opSecured
		}
	}
	return opWorker
}

// userContextMiddleware resolves the caller ahead of every secured
// operation, for its handler to read with userCtx. Public and worker
// operations have no user to resolve, and a server built without a
// service resolves none.
func (s *Server) userContextMiddleware(f StrictHandlerFunc, operationID string) StrictHandlerFunc {
	if operationAccess()[operationID] != opSecured {
		return f
	}
	return func(ctx context.Context, w http.ResponseWriter, r *http.Request, request any) (any, error) {
		p, ok := principalFromContext(ctx)
		// AuthMiddleware refuses a request with no principal before this
		// backstop; the worker token opens worker operations alone.
		if !ok || workerFromContext(ctx) {
			return nil, &service.Error{Kind: service.KindUnauthenticated}
		}
		if s.svc == nil {
			return f(ctx, w, r, request)
		}
		uc, err := s.svc.Grants.UserCtx(ctx, p.User)
		if err != nil {
			return nil, err
		}
		return f(context.WithValue(ctx, ctxUserKey{}, uc), w, r, request)
	}
}
