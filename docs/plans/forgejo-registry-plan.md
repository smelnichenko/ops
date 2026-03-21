# Forgejo Container Registry Plan

## Goal

Switch from tarball-based image import (`docker save | k3s ctr import`) to pushing images to the Forgejo built-in container registry, enabling cleaner CI/CD, proper image tagging, and future container-based CI isolation.

## Architecture

```
Current flow:
  CD runner → docker build → docker save → k3s ctr images import → pullPolicy: Never
  (all on same host, tightly coupled)

New flow:
  CD runner → docker build → docker push git.pmon.dev → k3s pulls from registry → pullPolicy: IfNotPresent
  (decoupled, registry as intermediary)
```

## Image Naming

```
Old: ghcr.io/schnappy/monitor:latest          → git.pmon.dev/schnappy/monitor:abc1234
Old: ghcr.io/schnappy/monitor-frontend:latest → git.pmon.dev/schnappy/monitor-frontend:abc1234
```

- Tags use short git hash (7 chars) — unique, immutable, traceable
- No more `:latest` — every deploy is a specific commit
- `pullPolicy: IfNotPresent` — pulls once per tag (no re-pull needed)

## Steps

### Phase 1: Enable Forgejo Registry — DONE

- [x] 1.1 Verify Forgejo packages/registry is enabled (default: on)
- [x] 1.2 Create a Forgejo access token for the CD runner (scope: `write:package`, user: `schnappy`)
- [x] 1.3 Store token on runner host (`~/.docker/config.json` via `docker login git.pmon.dev`)

### Phase 2: Configure k3s Registry Access — DONE

- [x] 2.1 Create `/etc/rancher/k3s/registries.yaml` on ten (auth: schnappy token)
- [x] 2.2 Restart k3s to pick up registry config
- [x] 2.3 Verify k3s can pull from `git.pmon.dev/schnappy/test:v1` (tested with busybox)

### Phase 3: Update CD Pipeline — DONE

- [x] 3.1 Update `cd.yml` build steps — tag with git hash, push to registry
- [x] 3.2 Replace `docker save | k3s ctr import` with `docker push` (inline in build step)
- [x] 3.3 Pass `monitor_image_tag` to Ansible deploy
- [x] 3.4 Runner `docker login git.pmon.dev` pre-configured via `~/.docker/config.json`

### Phase 4: Update Helm Values & Ansible — DONE

- [x] 4.1 Update `values.yaml` defaults (repository: `git.pmon.dev/schnappy/...`, pullPolicy: `IfNotPresent`)
- [x] 4.2 Update `vars/production.yml` (repository URLs, pullPolicy: `IfNotPresent`)
- [x] 4.3 Update Ansible role — build+push in parallel, pass image tag to helm `--set`
- [x] 4.4 Remove `rollout restart` workaround (new tag = automatic new pod)

### Phase 5: Cleanup — DONE

- [x] 5.1 Remove `docker save | k3s ctr images import` from Ansible role
- [x] 5.2 Remove `k3s ctr images import -` from runner sudoers in `setup-forgejo.yml`
- [x] 5.3 Update `vars/development.yml` image repositories
- [ ] 5.4 Clean up old images from k3s containerd (after production deploy verified)

### Phase 6: Registry Maintenance

- [ ] 6.1 Add CD step or cron to prune old tags (keep last 10 per image)
- [ ] 6.2 Verify registry storage is in Forgejo PVC (already covered by Velero backup)

## Decisions

1. **Forgejo built-in registry** — zero extra pods, already running, supports OCI images
2. **Git hash tags** — immutable, traceable, no `:latest` ambiguity
3. **`pullPolicy: IfNotPresent`** — pulls once per unique tag, no unnecessary re-pulls
4. **k3s `registries.yaml`** — native k3s registry config, no imagePullSecrets needed per namespace
5. **Same host push** — runner and k3s are on the same machine, so push/pull is local loopback (fast)
6. **No imagePullSecrets in Helm** — k3s `registries.yaml` handles auth globally
7. **`schnappy` user** — images pushed under repo owner, not admin

## Notes

- Forgejo registry URL format: `git.pmon.dev/<owner>/<image>:<tag>`
- Forgejo registry is OCI-compliant, works with `docker push/pull`
- Since runner and k3s are on the same host, push goes to Traefik → Forgejo → disk, pull goes same path — still fast (loopback)
- TLS already works (Forgejo uses `git.pmon.dev` cert via cert-manager DNS-01)
- Future: enables container-based CI (runner can reference registry images for job containers)
- Token `registry-push` (last 8: `43e7cd0f`) — scope: `write:package`
