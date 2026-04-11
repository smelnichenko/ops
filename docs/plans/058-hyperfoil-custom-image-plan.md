# Plan 058: Custom Hyperfoil image with MinIO client

## Context

Hyperfoil jobs download mc binary at runtime. Pre-install it in a custom image.

## Step 1: Create Dockerfile in platform repo, build on ten

No separate repo, no Woodpecker pipeline. Dockerfile lives in `platform/docker/hyperfoil/Dockerfile`. Build manually on ten with Kaniko or docker, push to `git.pmon.dev/schnappy/hyperfoil:0.28.0`.

**Dockerfile:**
```dockerfile
FROM quay.io/hyperfoil/hyperfoil:0.28.0
USER root
RUN microdnf install -y wget && \
    wget -q -O /usr/local/bin/mc https://dl.min.io/client/mc/release/linux-amd64/mc && \
    chmod +x /usr/local/bin/mc && \
    microdnf clean all
USER default
```

## Step 2: Update configmaps — remove mc download

Replace `/tmp/mc` download + use with direct `mc` in both:
- `platform/helm/schnappy/templates/hyperfoil-load-configmap.yaml`
- `platform/helm/schnappy/templates/hyperfoil-stress-configmap.yaml`

## Step 3: Update image reference

`platform/helm/schnappy/values.yaml`: `image: git.pmon.dev/schnappy/hyperfoil:0.28.0`

## Verification

Trigger stress test, check logs show no mc download, report uploaded.
