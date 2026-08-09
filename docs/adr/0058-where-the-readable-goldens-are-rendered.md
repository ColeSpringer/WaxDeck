# ADR-0058: Where the readable goldens are rendered

Status: accepted

## Context

The design system's golden suite runs twice. The CI goldens obscure text
as coloured blocks and are compared with a measured tolerance, so they
gate layout, spacing, and colour on any host. The readable goldens render
real type with the bundled fonts, which is the only way a wrong weight or
a lost variable axis is visible - and that is the same difference host
font rasterisation makes on its own, so no tolerance can tell the two
apart. ADR-0045 settled the consequence: the readable set is baselined on
Linux and skipped everywhere else.

The skip was then read as a property of the suite when it is a property
of the machine. A macOS or Windows checkout could run the readable pass
and never produce a baseline for it, so the set went stale the moment the
components moved, and nothing said so - the pass is skipped on the very
host that changed the widget, and no CI job ran the design system at all.
When one was finally added, four baselines that had been stale for nine
days failed together, which reads as a regression in the commit that
merely made them visible. The example package's composites were stale the
same way and had not been reported only because their step ran later in
the same job.

A second cost had already been paid quietly.
`components_late_golden_test.dart` declared itself CI-only, with a
deferred-work entry standing in for the readable half, because the host
it was written on could not baseline it. A gate was dropped to fit the
tooling.

The rasterisation argument is sound and is not what is being revisited.
What was wrong is the step from "these must be rendered on Linux" to
"these can only be maintained by somebody running Linux". WaxDeck is a
cross-platform app built by contributors on whichever desktop they have;
a gate only one OS can satisfy is a gate that rots, and it rots silently,
because the person who broke it is the person who cannot see it.

## Decision

Rendering happens in a container rather than on a workstation.
`make goldens-linux` builds ubuntu-24.04 with the Flutter the CI workflow
pins, runs both golden suites under `--update-goldens`, and copies back
only `goldens/linux/`. Docker is the only prerequisite, and the OS
somebody develops on stops deciding which gates they can run.

Three choices in it are deliberate. The Flutter version is read out of
`.github/workflows/ci.yaml` rather than pinned a second time, so the
baselines are always rendered by the toolchain that will check them. The
image is `linux/amd64` because the runner is x64: glyph rasterisation is
the entire subject here, so an arm64 image would mint baselines only an
arm64 host could match, which is the failure this file exists to prevent.
And only the readable baselines are written back, because the CI goldens
are host-portable by construction and a plain `flutter test
--update-goldens` updates them anywhere; copying the container's own
copies over them would put an unreviewable diff beside the reviewable
one.

Two mechanics worth knowing. The container works on a copy of `app/`
rather than in the mounted checkout, because `flutter pub get` would
otherwise leave `app/.dart_tool/package_config.json` pointing at
container paths and the host's next `flutter test` would fail to resolve
rather than run. And it runs as the invoking user, so what lands in the
tree is owned by whoever ran make rather than by root.

With rendering available from any host, `components_late_golden_test.dart`
drops its CI-only config and takes the readable pass like every other
golden suite; its deferred-work entry closes with it.

## Consequences

Every gate this repo has can be run, and repaired, from any host with
Docker. The readable suite becomes a real gate rather than one that
happened to pass, which means a design-system change is now two golden
updates in the same commit: `flutter test --update-goldens` for the
portable set wherever you work, and `make goldens-linux` for the
readable one. CI runs both, so a missed second half is caught on the PR
instead of accumulating.

The price is a container build - a few minutes and about a gigabyte,
once, then cached - and one more thing that needs Docker. That is the
same prerequisite `make up` and `make dist` already carry.

ADR-0045's statement that the readable set "stays Linux-only" still holds
for where the images are rendered. It no longer holds for who can render
them.
