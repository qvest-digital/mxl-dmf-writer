# dmf-mf-mxl-writer: producer-side image for the mxl-k8s demo pipeline.
#
# Builds mxl-gst-testsrc (and supporting binaries) from dmf-mxl/mxl
# source against the same go-mxl-builder/runtime pair the mxl-k8s
# gateway and demo-app compositor use, so writer, gateway, and
# compositor all link against a single libmxl ABI and the on-disk flow
# header layout is identical across all three actors.
#
# Tag bump policy: keep GO_MXL_TAG in sync with
#   - mxl-k8s gateway's docker/gateway.Dockerfile ARG GO_MXL_TAG
#   - mxl-dmf-demo-app compositor's compositor/Dockerfile.mxlk8s base
# gateway and compositor ship the same go-mxl rc.9 tag; writer must match.
#
# Bumping MXL_REF rebuilds against a different dmf-mxl/mxl commit. The
# repo defaults track the commit the gateway's libmxl was published
# from, so a plain `docker build` produces an image whose libmxl
# matches what's mmapped in the gateway container.

# renovate: datasource=docker depName=ghcr.io/qvest-digital/go-mxl-builder
ARG GO_MXL_TAG=1.0.0-rc.12

# Producer-pacing delta: we build mxl-gst-testsrc from STOCK dmf-mxl/mxl plus a
# small, in-repo patch series (patches/). These 7 patches (overlay-on-I420 +
# wall-clock pacing + single-batch commit + audio tone knobs) are a deliberate,
# PERMANENT qvest delta — by team decision they are NOT upstreamed. The delta is visible and
# reviewable in patches/; nothing depends on the demo-fork anymore.
#
# MXL_REF pins the stock commit the patches apply onto. Bump it (and re-run the
# patch apply) in lock-step with the libmxl the runtime stage ships. See README.
ARG MXL_SRC=https://github.com/dmf-mxl/mxl.git
ARG MXL_REF=4a8a50e7

# ── Stage 1: build mxl-gst-testsrc against the canonical libmxl ─────────────
FROM ghcr.io/qvest-digital/go-mxl-builder:${GO_MXL_TAG} AS build
ARG MXL_REF
ARG MXL_SRC

WORKDIR /src
COPY patches/ /patches/
# Full clone, then checkout the pinned ref. A shallow `git fetch --depth=1
# origin <SHA>` fails (exit 128) when the server doesn't allow fetching an
# arbitrary commit by SHA (uploadpack.allowReachableSHA1InWant off) — which is
# the GitHub default. A full clone has the commit in history, so checkout works
# whether MXL_REF is a SHA, branch, or tag.
RUN git clone "${MXL_SRC}" . \
 && git checkout "${MXL_REF}" \
 && git apply /patches/*.patch

# go-mxl-builder ships vcpkg with stduuid + spdlog + fmt + libfabric
# already provisioned; reuse its toolchain rather than re-fetching.
RUN cmake -S . -B build \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DMXL_ENABLE_FABRICS_OFI=ON \
        -DCMAKE_TOOLCHAIN_FILE=/root/vcpkg/scripts/buildsystems/vcpkg.cmake \
    && cmake --build build --target mxl-gst-testsrc mxl-info -j

# ── Stage 2: runtime ────────────────────────────────────────────────────────
FROM ghcr.io/qvest-digital/go-mxl-runtime:${GO_MXL_TAG}

# GStreamer plugin set the testsrc pipeline needs. Kept minimal — no
# x11 / playbin chain here; the writer is headless and pushes v210 into
# libmxl, not a display sink.
RUN apt-get update && apt-get install -y --no-install-recommends \
        gstreamer1.0-plugins-base \
        gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad \
        gstreamer1.0-x \
        libpango-1.0-0 \
        libpangocairo-1.0-0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/build/tools/mxl-gst/mxl-gst-testsrc /usr/bin/mxl-gst-testsrc
COPY --from=build /src/build/tools/mxl-info/mxl-info       /usr/bin/mxl-info

# Flow definition template the producer script substitutes per-flow UUIDs
# into before handing the rendered JSON to mxl-gst-testsrc -v. Path
# matches the upstream jonasohland/mxl image so existing producer scripts
# keep working without modification.
RUN mkdir -p /home/mxl
COPY --from=build /src/lib/tests/data/v210_flow.json  /home/mxl/v210_flow.json
COPY --from=build /src/lib/tests/data/audio_flow.json /home/mxl/audio_flow.json

# Default to 720p (1284x720, chroma 642x720) instead of the upstream 1080p:
# ~44% the pixels -> the v210<->I420 overlay conversions (single-thread bound)
# run well under one core, with zero grain backfill. Width is 1284, not 1280:
# the v210 unpacker requires width divisible by 6 (1280 is not), and 1284 is
# a 16:9-ish width. 1296 (not 1284) is also divisible by 48, so the v210
# row stride has no padding (packed == padded) — the GStreamer videoconvert in
# the compositor rejects the padded case, showing empty (green) tiles.
RUN sed -i 's/1920/1296/g; s/1080/720/g; s/960/648/g' /home/mxl/v210_flow.json

ENTRYPOINT ["/usr/bin/mxl-gst-testsrc"]
