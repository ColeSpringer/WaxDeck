# ADR-0001: Contract-first API with generated server and client

Date: 2026-07-11. Status: accepted

## Context

WaxDeck is agent-built to an unusual degree. The cheapest place for a human to
catch a design error is the API contract, and the cheapest way to keep server
and clients honest is to generate both from it.

## Decision

- `api/openapi.yaml` is the single source of truth for the `/api/v1` REST
  surface. WebSocket payloads will be defined as components in the same spec
  (envelope documented in `api/events.md`).
- Go server: `oapi-codegen` v2, **strict-server** + std-http-server over the
  stdlib `net/http` ServeMux, no web framework. The tool is pinned via the
  `tool` directive in `server/go.mod` (`go tool oapi-codegen`).
- Dart client: `openapi-generator` **dart-dio** (see ADR-0002).
- Generated code is **committed**. CI regenerates and fails on drift
  (`make drift-check`); `oasdiff` gates breaking spec changes; `spectral`
  lints style. Every spec delta gets human review before
  implementation.
- The Subsonic and gpodder compatibility surfaces are external contracts and
  live outside this spec, tested with golden files (added later).

## Consequences

Handlers and DTOs cannot drift from the documented API. The cost is codegen
ceremony on every spec change (`make generate`), accepted deliberately: it
turns API design into a reviewable artifact instead of an emergent property of
handler code.
