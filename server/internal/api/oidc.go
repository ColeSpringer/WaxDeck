package api

import (
	"context"
	"fmt"
	"html/template"
	"net/url"
	"strings"

	"github.com/colespringer/waxdeck/server/internal/service"
)

func (s *Server) ListOidcProviders(ctx context.Context, _ ListOidcProvidersRequestObject) (ListOidcProvidersResponseObject, error) {
	out := OidcProviders{Providers: []OidcProvider{}}
	if s.oidc != nil {
		cfg := s.oidc.Config()
		out.Providers = append(out.Providers, OidcProvider{
			Id:          cfg.ID,
			DisplayName: cfg.DisplayName,
			StartUrl:    "/api/v1/auth/oidc/start?provider=" + url.QueryEscape(cfg.ID),
		})
	}
	return ListOidcProviders200JSONResponse(out), nil
}

func (s *Server) StartOidc(ctx context.Context, req StartOidcRequestObject) (StartOidcResponseObject, error) {
	if s.oidc == nil || req.Params.Provider != s.oidc.Config().ID {
		return StartOidc404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such provider"))}, nil
	}
	mode := "web"
	if req.Params.Mode != nil {
		mode = string(*req.Params.Mode)
	}
	redirectTo := "/"
	loopbackPort := 0
	switch mode {
	case "web":
		if req.Params.Redirect != nil {
			p := *req.Params.Redirect
			if !safeRedirectPath(p) {
				return StartOidc400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "redirect must be a rooted path on this origin"))}, nil
			}
			redirectTo = p
		}
	case "app", "code":
		// Nothing extra to validate.
	case "loopback":
		if req.Params.Port == nil || *req.Params.Port < 1024 || *req.Params.Port > 65535 {
			return StartOidc400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "loopback mode requires port between 1024 and 65535"))}, nil
		}
		loopbackPort = *req.Params.Port
	default:
		return StartOidc400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "unknown mode"))}, nil
	}
	authURL, err := s.oidc.StartFlow(ctx, mode, s.oidcRedirectURI(), redirectTo, deref(req.Params.Challenge), loopbackPort)
	if err != nil {
		return nil, err
	}
	return StartOidc302Response{Headers: StartOidc302ResponseHeaders{Location: &authURL}}, nil
}

func (s *Server) OidcCallback(ctx context.Context, req OidcCallbackRequestObject) (OidcCallbackResponseObject, error) {
	if s.oidc == nil {
		return oidcErrorPage("single sign-on is not configured on this server"), nil
	}
	if e := deref(req.Params.Error); e != "" {
		return oidcErrorPage(fmt.Sprintf("the identity provider reported: %s %s", e, deref(req.Params.ErrorDescription))), nil
	}
	state := deref(req.Params.State)
	code := deref(req.Params.Code)
	if state == "" || code == "" {
		return oidcErrorPage("the identity provider sent an incomplete callback"), nil
	}
	done, err := s.oidc.HandleCallback(ctx, state, code)
	if err != nil {
		s.log.Warn("oidc callback failed", "err", err)
		return oidcErrorPage("sign-on could not be completed: " + err.Error()), nil
	}
	acct, err := s.svc.ResolveOidcAccount(ctx, service.OidcIdentity{
		Provider: done.Identity.Provider,
		Subject:  done.Identity.Subject,
		Email:    done.Identity.Email,
		Username: done.Identity.Username,
		Name:     done.Identity.Name,
		Roles:    done.Identity.Roles,
	})
	if err != nil {
		s.log.Warn("oidc account resolution failed", "err", err)
		return oidcErrorPage("sign-on could not be completed: " + err.Error()), nil
	}
	switch done.Mode {
	case "web":
		created, err := s.sessions.Create(ctx, acct.User.ID, "web", "", clientFromContext(ctx))
		if err != nil {
			return nil, err
		}
		setCookie := s.newSessionCookie(created.Token)
		location := done.RedirectTo
		if !safeRedirectPath(location) {
			location = "/"
		}
		return OidcCallback302Response{Headers: OidcCallback302ResponseHeaders{
			Location:  &location,
			SetCookie: &setCookie,
		}}, nil
	case "app":
		otc, err := s.oidc.MintCode(ctx, acct.User.ID, done.Challenge)
		if err != nil {
			return nil, err
		}
		location := "waxdeck://auth?code=" + url.QueryEscape(otc)
		return OidcCallback302Response{Headers: OidcCallback302ResponseHeaders{Location: &location}}, nil
	case "loopback":
		otc, err := s.oidc.MintCode(ctx, acct.User.ID, done.Challenge)
		if err != nil {
			return nil, err
		}
		location := fmt.Sprintf("http://127.0.0.1:%d/callback?code=%s", done.LoopbackPort, url.QueryEscape(otc))
		return OidcCallback302Response{Headers: OidcCallback302ResponseHeaders{Location: &location}}, nil
	case "code":
		otc, err := s.oidc.MintCode(ctx, acct.User.ID, done.Challenge)
		if err != nil {
			return nil, err
		}
		return oidcCodePage(otc), nil
	default:
		return oidcErrorPage("unknown flow mode"), nil
	}
}

func (s *Server) ExchangeOidcCode(ctx context.Context, req ExchangeOidcCodeRequestObject) (ExchangeOidcCodeResponseObject, error) {
	if req.Body == nil || req.Body.Code == "" {
		return ExchangeOidcCode400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "code is required"))}, nil
	}
	ip := remoteIPFromContext(ctx)
	key := "oidc-exchange:" + ip
	if s.oidc == nil {
		return ExchangeOidcCode401JSONResponse{UnauthenticatedJSONResponse(errObj("unauthenticated", "single sign-on is not configured"))}, nil
	}
	if !s.limiter.Allowed(key) {
		return ExchangeOidcCode429JSONResponse{RateLimitedJSONResponse(errObj("rate-limited", "too many attempts; retry later"))}, nil
	}
	userID, err := s.oidc.RedeemCode(ctx, req.Body.Code, deref(req.Body.Verifier))
	if err != nil {
		s.limiter.Failure(key)
		s.log.Warn(authFailureLog, "user", "oidc-exchange", "ip", ip)
		return ExchangeOidcCode401JSONResponse{UnauthenticatedJSONResponse(errObj("unauthenticated", "invalid code"))}, nil
	}
	s.limiter.Success(key)
	acct, err := s.svc.Account(ctx, userID)
	if err != nil {
		return nil, err
	}
	kind := "device"
	created, err := s.sessions.Create(ctx, acct.User.ID, kind,
		truncatedDeviceName(deref(req.Body.DeviceName)), clientFromContext(ctx))
	if err != nil {
		return nil, err
	}
	return ExchangeOidcCode200JSONResponse(LoginResponse{
		User: userJSON(acct.User), Token: created.Token, CsrfToken: created.CSRFToken,
	}), nil
}

// oidcRedirectURI is the provider-registered callback URL, derived from
// the configured public base.
func (s *Server) oidcRedirectURI() string {
	return strings.TrimSuffix(s.publicBase, "/") + "/api/v1/auth/oidc/callback"
}

// safeRedirectPath admits only single-slash-rooted same-origin paths.
// This redirect fires after the session cookie is set, so anything
// looser is a post-auth open redirect. Browsers strip ASCII tab and
// newline anywhere in a URL and treat backslash as a slash, so
// "/\t/evil.com" and "/\evil.com" both render as scheme-relative
// "//evil.com" after the redirect: every shaping character (controls,
// backslash) is rejected outright rather than modeled, and a parse
// with no scheme and no authority backstops the rest.
func safeRedirectPath(p string) bool {
	if p == "" || p[0] != '/' {
		return false
	}
	if len(p) > 1 && p[1] == '/' {
		return false
	}
	for i := 0; i < len(p); i++ {
		if p[i] < 0x20 || p[i] == 0x7f || p[i] == '\\' {
			return false
		}
	}
	u, err := url.Parse(p)
	return err == nil && !u.IsAbs() && u.Host == ""
}

// The completion pages carry no user-agent-derived content; everything
// interpolated is escaped by html/template.
var (
	codePageTmpl = template.Must(template.New("code").Parse(`<!doctype html>
<title>WaxDeck sign-on</title>
<style>body{font-family:system-ui;margin:3rem auto;max-width:30rem;text-align:center}code{font-size:1.4rem;background:#eee;padding:.4rem .8rem;border-radius:.4rem;display:inline-block;margin:1rem}</style>
<h1>Almost there</h1>
<p>Enter this one-time code in the app to finish signing in. It expires in a few minutes.</p>
<code>{{.}}</code>`))

	errorPageTmpl = template.Must(template.New("error").Parse(`<!doctype html>
<title>WaxDeck sign-on</title>
<style>body{font-family:system-ui;margin:3rem auto;max-width:30rem;text-align:center}</style>
<h1>Sign-on failed</h1>
<p>{{.}}</p>
<p><a href="/">Back to WaxDeck</a></p>`))
)

func oidcCodePage(code string) OidcCallbackResponseObject {
	var b strings.Builder
	_ = codePageTmpl.Execute(&b, code)
	return OidcCallback200TexthtmlResponse{Body: strings.NewReader(b.String()), ContentLength: int64(b.Len())}
}

func oidcErrorPage(msg string) OidcCallbackResponseObject {
	var b strings.Builder
	_ = errorPageTmpl.Execute(&b, msg)
	return OidcCallback200TexthtmlResponse{Body: strings.NewReader(b.String()), ContentLength: int64(b.Len())}
}
