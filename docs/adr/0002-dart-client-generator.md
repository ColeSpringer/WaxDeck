# ADR-0002: Dart client generator - dart-dio behind a hand-written wrapper

Date: 2026-07-11. Status: accepted (evaluation done; re-visit only on real pain)

## Context

The plan pinned `openapi-generator` dart-dio provisionally and required an
evaluation before locking the pipeline, because dart-dio's generated
nullability/oneOf handling is historically rough and agents churn badly on
awkward generated APIs.

## Options considered

1. **openapi-generator `dart-dio`** (built_value serialization): most mature
   Dart generator; heavy DTOs but reliable; JVM tool.
2. **openapi-generator `dart`** (plain): lighter output, weaker null-safety
   and oneOf story, less maintained than dart-dio.
3. **swagger_dart_code_generator / chopper**: pure-Dart (no JVM), but
   Chopper-centric, weaker OpenAPI 3 coverage, and would put a second HTTP
   stack beside dio.
4. Hand-written client only: no drift protection; rejected outright.

## Decision

Keep **dart-dio (7.14.0, pinned in `tools/openapitools.json`)**, with the
mitigations that make its roughness irrelevant to feature code:

- Generated output is its **own package**, `app/packages/waxdeck_api_gen`,
  fully owned by the generator (safe to delete and regenerate; never
  hand-edited; generator scaffolding like `test/`/`doc/` is dropped and lints
  are relaxed inside that package only).
- A **hand-written repository layer**, `app/packages/waxdeck_api`, is the only
  package app code may import. It exposes plain-Dart models and translates
  transport errors into the spec's structured error model. Generator churn
  stops at this boundary, which is also the seam where a different generator
  could be swapped in later without touching feature code.
- The JVM requirement is contained in `tools/generate-dart.sh`, which
  provisions its own JRE into `tools/.cache` when none is installed (CI uses
  setup-java). The evaluation verified the full loop: spec to generator to
  build_runner to `flutter analyze` clean to widget test consuming the wrapper.

## Consequences

Two packages instead of one, and built_value ceremony inside the generated
package (build_runner step in `make generate`). In exchange: drift-checked
DTOs, a stable import surface for agents, and a cheap exit if dart-dio
becomes a liability.
