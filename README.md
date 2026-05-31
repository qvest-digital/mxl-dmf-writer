# mxl-dmf-writer

Producer-side container image for the mxl-k8s demo pipeline.

Bundles `mxl-gst-testsrc` + `mxl-info`, built from
[`dmf-mxl/mxl`](https://github.com/dmf-mxl/mxl) against the
`ghcr.io/qvest-digital/go-mxl-runtime` libmxl, so the writer, the
mxl-k8s gateway DaemonSet, and the demo-app compositor all link
against a single libmxl ABI.

## Image

`ghcr.io/qvest-digital/mxl-dmf-writer:<tag>`

Tags follow `<git-sha>` and `latest`.

## Build locally

```bash
docker build -t mxl-dmf-writer:dev .
```

Override defaults with `--build-arg`:

```bash
docker build \
  --build-arg GO_MXL_TAG=1.0.0-rc.8 \
  --build-arg MXL_REF=<commit> \
  -t mxl-dmf-writer:dev .
```

## Tag bump policy

`GO_MXL_TAG` must match the `ARG GO_MXL_TAG` in
[`qvest-digital/mxl-k8s`](https://github.com/qvest-digital/mxl-k8s)'s
`docker/gateway.Dockerfile` and the base tag in
[`qvest-digital/mxl-dmf-demo-app`](https://github.com/qvest-digital/mxl-dmf-demo-app)'s
`compositor/Dockerfile.mxlk8s`. Bumping the three together keeps the
producer, gateway, and consumer on the same libmxl + libfabric.

`MXL_REF` defaults to `main` of `dmf-mxl/mxl`. Pin to a commit for
reproducible builds; bump in lockstep with whatever libmxl the
runtime stage ships (the commit `go-mxl-runtime:${GO_MXL_TAG}` was
built from).
