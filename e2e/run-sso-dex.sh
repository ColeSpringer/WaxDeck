#!/usr/bin/env bash
# The browser single sign-on journey against a real identity provider.
#
# The default suite drives the bare-binary test IdP, which is fast and
# proves the app's half. This proves the other half: a real OIDC server,
# with its own discovery document, consent behaviour, form and token
# endpoint. It runs dex in a container and the same waxdeck stack the
# rest of the suite runs, pointed at it through the OIDC variables
# run-stack.sh now takes from the environment.
set -euo pipefail

E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE=(docker compose -f "$E2E_DIR/sso/compose.yaml")

# Refuse a stack that is already up: outside CI, playwright reuses an
# existing server on 4420, and one booted without the dex OIDC variables
# fails much later as a locator timeout on the dex login form, naming
# nothing about the real cause.
if curl -fsS -m 2 http://localhost:4420/api/v1/health >/dev/null 2>&1; then
	echo "something already serves :4420; stop it first (this run needs a stack booted with the dex OIDC variables)" >&2
	exit 2
fi

cleanup() { "${COMPOSE[@]}" down --remove-orphans >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM HUP

"${COMPOSE[@]}" up -d --wait

# Discovery has to answer, and it has to answer with the issuer this
# stack is configured for: an issuer that drifted from the config is a
# token the server refuses much later, in a callback, as an opaque
# verification failure. Failing here names it.
DISCOVERY=http://127.0.0.1:5556/dex/.well-known/openid-configuration
for _ in $(seq 1 60); do
	if curl -fsS "$DISCOVERY" 2>/dev/null | grep -q '"issuer": *"http://127\.0\.0\.1:5556/dex"'; then
		break
	fi
	sleep 1
done
if ! curl -fsS "$DISCOVERY" 2>/dev/null | grep -q '"issuer": *"http://127\.0\.0\.1:5556/dex"'; then
	echo "dex never published http://127.0.0.1:5556/dex as its issuer" >&2
	curl -fsS "$DISCOVERY" >&2 || true
	"${COMPOSE[@]}" logs --no-color >&2 || true
	exit 1
fi

# The stack playwright boots inherits these, which is what points it at
# dex instead of the test IdP. WAXDECK_DEX_SSO also switches the config:
# it adds the sso-dex project and drops the wizard server, which this
# run has no use for.
cd "$E2E_DIR"
WAXDECK_DEX_SSO=1 \
	WAXDECK_OIDC_ISSUER=http://127.0.0.1:5556/dex \
	WAXDECK_OIDC_ID=dex \
	WAXDECK_OIDC_NAME="Dex" \
	WAXDECK_OIDC_CLIENT_ID=waxdeck-e2e \
	WAXDECK_OIDC_CLIENT_SECRET=waxdeck-e2e-secret \
	npx playwright test --project=sso-dex "$@"
