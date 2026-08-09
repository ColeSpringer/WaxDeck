# The Linux host the readable goldens are baselined on.
#
# `goldens/linux/` renders real type, so it is the only pass that catches
# a wrong weight or a lost variable axis - and it is baselined on Linux
# and skipped everywhere else, which used to mean a macOS or Windows
# checkout could not produce one. This image is that host, so which OS a
# contributor develops on stops deciding which gates they can run.
#
# Two pins, both deliberate. The Flutter version comes from the Makefile,
# which reads it out of .github/workflows/ci.yaml so there is one pin
# rather than a second copy to go stale. And the platform is linux/amd64
# because the runner is x64: glyph rasterisation is the entire subject of
# these goldens, so an arm64 image would mint baselines only an arm64
# host could match, which is the bug this file exists to prevent.
FROM --platform=linux/amd64 ubuntu:24.04

ARG FLUTTER_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git rsync unzip xz-utils zip \
 && rm -rf /var/lib/apt/lists/*

RUN test -n "$FLUTTER_VERSION" || { echo "FLUTTER_VERSION build arg is required" >&2; exit 1; } \
 && curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
      -o /tmp/flutter.tar.xz \
 && tar xf /tmp/flutter.tar.xz -C /opt \
 && rm /tmp/flutter.tar.xz

ENV PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:$PATH

# The flutter tool shells out to git against its own SDK to read the
# version, and the SDK is root-owned while the container runs as the
# invoking user - which git refuses as "dubious ownership". The exception
# goes in the system config (/etc/gitconfig) rather than root's global
# one, because the user that hits it is not the user that built this.
#
# The version call warms the tool's snapshot into the image, so the first
# run is not paying for it, and fails the build here rather than
# mid-regeneration if the archive was bad.
RUN git config --system --add safe.directory /opt/flutter && flutter --version

# The container runs as the invoking user so the PNGs it writes into the
# mounted checkout are owned by whoever ran make, not by root. That user
# does not exist in this image and owns nothing in it, so the SDK has to
# be writable by anyone: the flutter tool takes a lock under bin/cache on
# every invocation. Safe here because the image is a single-purpose,
# throwaway build environment.
RUN chmod -R a+rwX /opt/flutter

# Where the pub cache lands. The Makefile mounts a named volume here, so
# a rebaseline resolves the workspace from disk instead of re-fetching
# every package over the network on a container that is thrown away each
# run. It has to exist in the image with open permissions: docker seeds a
# fresh named volume from the image path, ownership and mode included,
# and the container is not root.
RUN mkdir -p /pub-cache && chmod a+rwX /pub-cache
ENV PUB_CACHE=/pub-cache

COPY update-linux-goldens.sh /usr/local/bin/update-linux-goldens
RUN chmod +x /usr/local/bin/update-linux-goldens

ENTRYPOINT ["/usr/local/bin/update-linux-goldens"]
