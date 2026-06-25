# mxl-dmf-writer: producer-side image for the mxl-k8s demo pipeline.
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
#
# Bumping MXL_REF rebuilds against a different dmf-mxl/mxl commit. The
# repo defaults track the commit the gateway's libmxl was published
# from, so a plain `docker build` produces an image whose libmxl
# matches what's mmapped in the gateway container.

# renovate: datasource=docker depName=ghcr.io/qvest-digital/go-mxl-builder
ARG GO_MXL_TAG=1.0.0-rc.8

# Pin the dmf-mxl/mxl source commit. Bump in lockstep with the libmxl
# the runtime stage ships (the commit go-mxl-runtime:${GO_MXL_TAG}
# was built from). See README for how to find it.
#
# HOTFIX: temporarily building from the qvest-digital/mxl-dmf-demo fork's
# fix/writer-appsink-drop branch (= upstream main + the appsink
# max-buffers/drop fix that stops the producer drifting tens of minutes
# behind real time). Revert MXL_SRC back to dmf-mxl/mxl + MXL_REF=main
# once the fix lands upstream.
ARG MXL_SRC=https://github.com/qvest-digital/mxl-dmf-demo.git
ARG MXL_REF=fix/writer-appsink-drop

# ── Stage 1: build mxl-gst-testsrc against the canonical libmxl ─────────────
FROM ghcr.io/qvest-digital/go-mxl-builder:${GO_MXL_TAG} AS build
ARG MXL_REF
ARG MXL_SRC

WORKDIR /src
RUN git clone --depth=1 "${MXL_SRC}" . && \
    git fetch --depth=1 origin "${MXL_REF}" && \
    git checkout FETCH_HEAD

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

ENTRYPOINT ["/usr/bin/mxl-gst-testsrc"]
