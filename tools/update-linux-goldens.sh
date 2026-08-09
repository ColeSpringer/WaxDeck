#!/usr/bin/env bash
# Rebaselines the readable Linux goldens. Runs inside the container
# tools/goldens.Dockerfile builds; `make goldens-linux` is the way in.
#
# The checkout arrives read-write at /repo and only the regenerated PNGs
# go back to it. The container runs as the invoking user, so what lands
# there is owned by whoever ran make rather than by root.
set -euo pipefail

WORK="${WORK:-/tmp/waxdeck-goldens}"

# Work on a copy rather than in the mounted tree. `flutter pub get`
# rewrites app/.dart_tool/package_config.json with container paths, and a
# host that then ran `flutter test` would get a resolution error rather
# than a test run - so the mount is read from, and written to only at the
# end. Every path dependency in the workspace resolves inside app/, which
# is why that subtree is the whole of what is copied.
rm -rf "$WORK"
mkdir -p "$WORK"
rsync -rlpt --exclude='.dart_tool/' --exclude='build/' /repo/app/ "$WORK/app/"

cd "$WORK/app"
flutter pub get

echo "==> waxdeck_ui"
cd "$WORK/app/packages/waxdeck_ui"
flutter test --update-goldens

echo "==> waxdeck_ui/example"
cd "$WORK/app/packages/waxdeck_ui/example"
flutter test --update-goldens

# Only the readable baselines come back. The CI goldens block their text
# out and are compared with a tolerance, so they are host-portable by
# construction and a plain `flutter test --update-goldens` updates them
# wherever you work; copying this container's copies over them would be
# churn rather than a change, and would put an unreviewable diff next to
# the reviewable one.
#
# --delete is what retires a baseline whose test was renamed or removed;
# without it the orphan sits in the tree forever with nothing comparing
# against it. It is safe here because both suites ran to completion
# above - `set -e` aborts before this loop otherwise - so the source
# directory holds every readable golden the suites still declare. The
# emptiness guard is for the one case that reasoning does not cover: a
# source that vanished for some reason this script cannot see, where
# --delete would take the whole committed set with it.
for dir in \
  packages/waxdeck_ui/test/goldens/linux \
  packages/waxdeck_ui/example/test/goldens/linux
do
  if [ -z "$(ls -A "$WORK/app/$dir" 2>/dev/null)" ]; then
    echo "refusing to sync: $dir rendered no goldens" >&2
    exit 1
  fi
  mkdir -p "/repo/app/$dir"
  rsync -rlpt --delete "$WORK/app/$dir/" "/repo/app/$dir/"
done

echo "==> rebaselined goldens/linux for waxdeck_ui and its example"
