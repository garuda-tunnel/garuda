# Operator runbook — Sub-project D rollout (Multus attach race fix)

**Scope:** propagate the Sub-project D Multus attach-race fix from
`feature/image-digest-release` into the three production-shaped stands
(`mini-site`, `<stand-name>`, `vpn2`) after the umbrella release.

**Audience:** operator on duty for the garuda-tunnel release.

---

## Sub-project D summary

Three layers of defense, all delivered inside the `garuda` umbrella chart
(`modules/garuda_k8s/charts/garuda`, chart version bumped 0.2.2 → **0.3.0**):

| Layer | Mechanism | Off-switch |
|---|---|---|
| **L1** Helm pre-install/pre-upgrade hook | Job (`bitnami/kubectl`) `kubectl rollout status ds/kube-multus-ds -n kube-system` + `kubectl wait --for=condition=Ready node --all`. Blocks the chart release until kubelet has ingested the Multus delegate. | `--set multusReadiness.enabled=false` |
| **L2** Terraform gate | `null_resource.multus_ready` in `modules/garuda_k8s/main.tf` local-execs the same kubectl waits; consumer modules `depends_on` it via output `multus_ready_id`. | (no values flag; remove the `depends_on` entries — see Known limitations) |
| **L3** Pod-reaper insurance | `target/pod-reaper` Deployment namespace-scoped to `garuda`, evicts pods stuck `Ready=False > 120s` in the namespace. Self-reap protection via `EXCLUDE_LABEL_KEY=app.kubernetes.io/name` / `EXCLUDE_LABEL_VALUES=pod-reaper`. | `--set podReaper.enabled=false` |

Both new images are digest-pinned in `values.yaml`. **Image digest updates
are out-of-band** (Renovate or manual) — release-please does **not** update
`@sha256:` digests in `values.yaml` (the generic updater rewrites semver
markers, not digest pins; and external images are Renovate-managed).

Implementation commits on `feature/image-digest-release`:
`e7c0dc2` (L1) · `be99431` (L3) · `ee014f4` (L2 module) · `2e9a6cb`
(L2 mini-site wiring) · `3b60c44` (chart 0.3.0 + release-please config).

---

## Pre-release checklist

- [ ] release-please PR for the `garuda` chart package
      (`modules/garuda_k8s/charts/garuda`) is open and shows
      `0.2.2 → 0.3.0` in `Chart.yaml`.
- [ ] release-please PR for the umbrella root (`.`) package is open with
      the next umbrella semver (expected `v0.3.0`) reflecting the bumped
      chart + mini-site consumers.
- [ ] release-please dry-run executed locally by the operator:
      ```bash
      npx release-please release-pr --dry-run --debug \
        --repo-url=garuda-tunnel/garuda-internal \
        --target-branch=main --token="$GITHUB_TOKEN" 2>&1 | tail -60
      ```
      Confirm: `paths_released` contains `modules/garuda_k8s/charts/garuda`,
      candidate version `0.3.0`. **Note:** release-please will NOT update
      `values.yaml` digest pins — `extra-files` has been removed because the
      generic updater only rewrites semver tags (not `@sha256:` digests), and
      external images (`bitnami/kubectl`, `target/pod-reaper`) are managed by
      Renovate or manually.
- [ ] CI pipelines green on the release-please PR(s):
      - golden helm tests (`modules/garuda_k8s/tests/helm/run-helm-tests.sh`),
      - tofu tests (`modules/garuda_k8s` 13/13, `examples/mini-site/garuda` 21/21),
      - `helm lint modules/garuda_k8s/charts/garuda`.

---

## Image digest updates

The images used by Sub-project D (`bitnami/kubectl`, `target/pod-reaper`) are
**external** and their digest pins in `values.yaml` are **not** managed by
release-please. To update a digest:

1. Pull the new image and record the digest:
   ```bash
   docker pull bitnami/kubectl:1.36.2
   docker inspect bitnami/kubectl:1.36.2 --format '{{index .RepoDigests 0}}'
   ```
2. Update the `image:` field in
   `modules/garuda_k8s/charts/garuda/values.yaml` to the new
   `<registry>/<name>:<tag>@sha256:<hex>` value.
3. Regenerate helm goldens: `REGEN_GOLDEN=1 bash modules/garuda_k8s/tests/helm/run-helm-tests.sh`.
4. Run helm tests + tofu tests to confirm green.
5. Open a PR with the digest bump.

Alternatively, configure **Renovate** with a `docker` datasource rule for
`values.yaml` — it will open PRs automatically when new digests are available.

---

## Release sequence

1. **Merge release-please PR(s)** in `garuda-internal` `main`:
   - Chart package release creates tag for the `garuda` chart at `0.3.0`.
   - Umbrella root package release creates the umbrella semver tag
     (expected `v0.3.0`).
2. **Verify OCI chart published**:
   ```bash
   helm pull oci://ghcr.io/garuda-tunnel/charts/garuda --version 0.3.0
   ```
   Expect success; digest non-empty.
3. **Verify public umbrella mirror synced** (Sub-project C2a pipeline):
   ```bash
   git ls-remote --tags https://github.com/garuda-tunnel/garuda.git | grep v0.3.0
   ```
   Expect a single matching tag. If empty: re-check the umbrella `sync` job
   in `garuda-internal` Actions and the `paths_released` / `release_tag`
   output keys (see Sub-project C2a completeness doc for the
   un-prefixed-root-output-key trap).
4. **Verify image digests in published chart** are the ones from
   `values.yaml` (`bitnami/kubectl@sha256:08afc8…`,
   `target/pod-reaper@sha256:b8f908…`); no `:latest` references.

---

## Stand cutover

### mini-site (in-repo)

In-repo umbrella consumer; bump happens via a PR in this repo.

- [ ] Open PR bumping `examples/mini-site/garuda/terragrunt.hcl` umbrella
      source `?ref=` to the new umbrella semver (e.g. `v0.3.0`).
- [ ] CI green; merge.
- [ ] (Optional) live apply on the mini-site stand and re-run z2g smoke if
      the mini-site has a live target.

### `<stand-name>` — production hub stand (out-of-repo)

> `<stand-name>` refers to the production hub stand managed in the operator's
> private inventory (not named publicly).

Local-only git repo for the production hub stand, currently
pinned at umbrella `v0.1.0`.

- [ ] Edit `<stand-name>/garuda/terragrunt.hcl` umbrella source pin
      `?ref=v0.1.0` → `?ref=v0.3.0` (or whichever umbrella semver embeds
      `garuda` chart `0.3.0`).
- [ ] `terragrunt init` resolves the new ref.
- [ ] `terragrunt apply` (parallelism=1 recommended to avoid helm races).
- [ ] On apply, observe: the L1 readiness Job runs and completes before
      consumer helm_releases fire. No more `Cannot find device backbone`
      Init:Errors on freshly created hub VMs.
- [ ] If apply recreates the hub VM (module source-string change is a
      replacement), the same k3s cloud-init transient noted in the C2b
      completeness report can recur — recover manually if so.

### vpn2

Stand managed by terragrunt at `test-config/vpn2/deploy/garuda/terragrunt.hcl`,
currently pinned at umbrella `v0.2.0`.

- [ ] Edit `test-config/vpn2/deploy/garuda/terragrunt.hcl` umbrella source
      `?ref=v0.2.0` → `?ref=v0.3.0`.
- [ ] `terragrunt apply`.
- [ ] Run the z2g live gate:
      ```bash
      ansible-playbook test-config/vpn2/smoke/z2g.yml
      ```
      Expect Phases 0–7 PASS as in C2b; Phase 8 §8.1 may still trip on
      fz-client fixture drift (orthogonal, see existing runbook).

---

## Verification post-cutover

Run on the stand kubeconfig (hub):

```bash
# L1 — readiness Job completed successfully (TTL 300s, so it may already be gone)
kubectl -n garuda get jobs -l app.kubernetes.io/component=multus-readiness
kubectl -n garuda logs job/<release>-multus-ready    # while it exists

# L3 — pod-reaper Running
kubectl -n garuda get deploy -l app.kubernetes.io/name=pod-reaper
kubectl -n garuda logs deploy/<release>-pod-reaper --tail=50

# Workload sanity — backbone/border NADs attached on first try
kubectl -n garuda get pods -o wide
kubectl -n garuda describe pod <wg-*-pod> | grep -E 'k8s.v1.cni.cncf.io/network-status|backbone|border'
```

Force-recreate scenario (the original failure mode):

```bash
# Force-replace hub VM (operator command) → after apply:
# 1. garuda chart release blocks on L1 (Job runs ≤ 60s on a small cluster).
# 2. Consumer helm_releases gated by L2 wait until L1 cleared.
# 3. Workloads come up Ready on first attempt — no manual `kubectl rollout restart`.
```

If a workload still arrives `Ready=False`, L3 (pod-reaper) evicts it after
`MAX_UNREADY=120s` + `GRACE=30s` and the recreated pod gets a fresh CNI ADD.

---

## Rollback

Pick the smallest action that unblocks:

1. **Disable a single layer** via Helm values override at the consumer
   `helm_release` for the umbrella chart:
   - `--set multusReadiness.enabled=false` (skip L1 hook).
   - `--set podReaper.enabled=false` (stop L3 evictions).
2. **Disable L2 TF gate**: there is **no values off-switch** today; the
   gate fires unconditionally inside `modules/garuda_k8s/main.tf`. To
   disable, either:
   - remove `null_resource.multus_ready` and the `depends_on` reference
     in `helm_release.garuda` in a local hotfix branch, or
   - rely on `terragrunt apply -refresh-only` after manually marking the
     resource tainted/replaced.
   (Tracked as follow-up — see Known limitations.)
3. **Chart downgrade**: pin the umbrella source to a pre-D umbrella semver
   (e.g. `?ref=v0.2.0` for vpn2, `?ref=v0.1.0` for `<stand-name>`) and
   `terragrunt apply`. Reverts all three layers atomically.

---

## Known limitations / follow-ups

1. **pod-reaper label filter (resolved):** The `REQUIRE_LABEL_KEY` filter
   has been removed (MF1 Task 9 remediation). L3 now evicts **all** unready
   pods in the `garuda` namespace, scoped only by `NAMESPACE`. Self-reap
   protection is provided via `EXCLUDE_LABEL_KEY=app.kubernetes.io/name` /
   `EXCLUDE_LABEL_VALUES=pod-reaper`. Consumer charts
   (`wireguard`, `firezone`, `router`/`ipt-server`, `powerdns`,
   `border-router`) do not need to emit `app.kubernetes.io/part-of=garuda`.
   (`D-follow1` closed.)
2. **L2 TF gate has no off-switch:** `null_resource.multus_ready` is
   unconditional. A minor PR can add `count = var.multus_wait_enabled ? 1 : 0`
   plus a `multus_wait_enabled` variable defaulting to `true`. Not blocking;
   queued as `D-follow2`.
3. **kubectl image skew:** `bitnami/kubectl` no longer publishes
   per-minor tags, so L1 uses `latest` → kubectl `v1.36.2` against k3s
   `1.31` (5 minor versions ahead, exceeds the official ±1 skew window).
   Functionally fine for `rollout status` / `wait`, but not best practice.
   `D-follow3`: switch to a k3s-skew-friendly image (e.g. a self-built
   `kubectl` from the matching k3s minor) once one is available.
4. **L1 Job uses `kube-system/kube-multus-ds`**: hard-coded DaemonSet
   namespace + name. If the cluster ever renames or relocates Multus, the
   Job will time out. Not currently parameterised.

---

## Cross-references

- Spec: `docs/superpowers/specs/2026-06-16-subproject-d-multus-attach-race-fix-design.md`
- Plan: `docs/superpowers/plans/2026-06-16-subproject-d-multus-attach-race-fix.md`
- Completeness: `docs/artifacts/2026-06-16-subproject-d-completeness.md`
- Task 0 validation: `docs/artifacts/2026-06-16-subproject-d-task0-validation.md`
- Research: `<stand-name>/docs/artifacts/2026-06-13-multus-attach-race-research.md` (operator's private stand repo)
- Related operator runbook (orthogonal): `docs/operations/operator-runbook-fz-client-handshake.md`
