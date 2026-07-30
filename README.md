# dmf-mf-mxl-writer

Producer-side container image for the mxl-k8s demo pipeline.

Bundles `mxl-gst-testsrc` + `mxl-info`, built from
[`dmf-mxl/mxl`](https://github.com/dmf-mxl/mxl) against the
`ghcr.io/qvest-digital/go-mxl-runtime` libmxl, so the writer, the
mxl-k8s gateway DaemonSet, and the demo-app compositor all link
against a single libmxl ABI.

## Image

`ghcr.io/qvest-digital/dmf-mf-mxl-writer:<tag>`

Tags follow `<git-sha>` (every build), `latest` (main only), and `<version>` on release.

`ghcr.io/qvest-digital/mxl-dmf-writer` carries the same tags, from the name this
repository had before the rename, and stops being pushed once no consumer
resolves it.

## Build locally

```bash
docker build -t dmf-mf-mxl-writer:dev .
```

Override defaults with `--build-arg`:

```bash
docker build \
  --build-arg GO_MXL_TAG=1.0.0-rc.9 \
  --build-arg MXL_REF=<commit> \
  -t dmf-mf-mxl-writer:dev .
```

## Tag bump policy

`GO_MXL_TAG` must match the `ARG GO_MXL_TAG` in
[`qvest-digital/mxl-k8s`](https://github.com/qvest-digital/mxl-k8s)'s
`docker/gateway.Dockerfile` and the base tag in
[`qvest-digital/mxl-dmf-demo-app`](https://github.com/qvest-digital/mxl-dmf-demo-app)'s
`compositor/Dockerfile.mxlk8s`. Bumping the three together keeps the
producer, gateway, and consumer on the same libmxl + libfabric.

`MXL_REF` pins to a specific stock commit of `dmf-mxl/mxl` (currently
`d3771a4`). Bump in lockstep with whatever libmxl the runtime stage
ships (the commit `go-mxl-runtime:${GO_MXL_TAG}` was built from).

## Producer-pacing patches

The image builds stock `dmf-mxl/mxl` @ `MXL_REF` and then applies
`patches/*.patch` on top. The 6 patches in the series are a deliberate,
permanent qvest delta — they fix producer-pacing behaviour that is
specific to this pipeline and are not upstreamed.

To bump the stock base:
1. Raise `MXL_REF` to the new commit.
2. Re-apply the series: `git apply --3way patches/*.patch` (resolve any
   conflicts against the new base).
3. Re-test the pipeline end-to-end before shipping.

`GO_MXL_TAG` must stay in lock-step with the gateway and compositor
(see **Tag bump policy** above) — all three must link the same libmxl ABI.
