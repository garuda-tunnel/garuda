# Garuda platform — agent notes (AGENTS-platform.md)

Platform contracts and rules for agents working on garuda-tunnel. This document
is referenced by the repo root `AGENTS.md`.

> Status: sections for the injection engine (MAP/VAP at
> `admissionregistration.k8s.io/v1`), `net.garuda-tunnel/*` annotation model,
> profile-as-label / two-key annotation model, `garuda_guest` pure-data module,
> vanilla guest contract, bootstrap `time_sleep 10s`, Multus attach-race fix,
> frr-sidecar image contract, CEL guard invariants and anti-patterns are pending
> and tracked in the root `AGENTS.md` table of contents. The dependency-management
> contract below is authoritative.

## Dependency management & repin (Renovate)

### How it runs
- Org-wide Renovate runs from `garuda-tunnel/.github` on a schedule
  (`.github/workflows/renovate.yml`), self-hosted via GitHub Actions (no external
  service), authenticating as the `garuda-renovate` GitHub App.
- Configuration is a single org-wide file, `garuda-tunnel/.github/renovate.json`,
  inherited by every `*-internal` repo via Renovate `inheritConfig`. The runner
  overrides `RENOVATE_INHERIT_CONFIG_REPO_NAME=garuda-tunnel/.github` and
  `RENOVATE_INHERIT_CONFIG_FILE_NAME=renovate.json` — the Renovate *default*
  inheritance target is `renovate-config/org-inherited-config.json`, which we do
  NOT use. There is no per-repo `renovate.json`.
- Scope: `autodiscoverFilter: garuda-tunnel/*-internal`. Public mirror repos are
  intentionally excluded — they are generated snapshots and the publish sync
  overwrites them.

### What gets repinned automatically
1. **Terraform module refs** — `git::https://github.com/garuda-tunnel/<component>.git//...?ref=vX.Y.Z`
   (in `examples/mini-site/garuda/main.tf` and component modules). Renovate's
   native `terraform` manager tracks the component's git tags and opens a PR
   bumping `?ref=`. No annotation needed.
2. **OCI Helm chart pins** — `chart_version = "X.Y.Z"`, consumed as
   `oci://ghcr.io/garuda-tunnel/charts/<name>`. Renovate does NOT auto-detect
   these bespoke pins; they are activated by an inline annotation placed
   immediately above the pinned value:
   ```hcl
   # renovate: datasource=docker depName=ghcr.io/garuda-tunnel/charts/<name>
   chart_version = "X.Y.Z"
   ```
   A generic `customManagers` (regex) entry in `renovate.json` reads these
   annotations.
3. **Container image pins** — e.g.
   `frr_sidecar_image: "ghcr.io/garuda-tunnel/garuda-frr-sidecar:X.Y.Z"` in a
   `values.yaml`, via the same annotation mechanism (`datasource=docker`).

### What is NOT tracked (by design)
- The **garuda umbrella chart** is the deployment entry point and is consumed
  from the local shallow clone (`chart = "${path.module}/charts/garuda"`, no
  `version`/`repository`) — NOT from OCI. It is deliberately outside Renovate.
- `garuda_chart_version` is NOT a dependency pin — it is only an input to the
  `net.garuda-tunnel/profile-rev` rollout-trigger hash. Do not add a `# renovate:`
  annotation to it (there is no `charts/garuda` OCI package). Keep it in sync with
  the umbrella `Chart.yaml` version (ideally derive it from that file rather than
  hardcoding, so it cannot go stale and silently break rollout triggering).

### Version-detection guardrail
- The `*-internal` component repos carry CalVer/CI snapshot tags (e.g.
  `26.10615.10647`) alongside the real `vX.Y.Z` release-please tags. A packageRule
  `allowedVersions: "< 20.0.0"` on garuda git deps suppresses the CalVer noise so
  Renovate only proposes real releases.

### The repin cascade (component release → deployment)
1. A component `<x>-internal` cuts a release → git tag `vX.Y.Z` and OCI chart
   `ghcr.io/garuda-tunnel/charts/<x>` are published.
2. Renovate opens a PR in `garuda-internal` bumping that component's `?ref=`
   and/or annotated `chart_version` in `examples/mini-site/garuda/main.tf`
   (mini-site is the canonical topology).
3. Merge → garuda-internal's own release-please cuts a new garuda umbrella tag.
4. Stands consume the umbrella at a pinned ref:
   - `test-config/vpn2` pulls the whole mini-site stand:
     `garuda-internal.git//examples/mini-site/garuda?ref=vX.Y.Z`.
   - Bespoke internal stands that pre-date the mini-site keep their own
     stand copy pinning `garuda.git//modules/garuda_k8s?ref=vX.Y.Z` instead
     of consuming the whole mini-site module.
   Bumping the stand's `?ref=` (also a Renovate-trackable terraform pin) followed
   by `tofu apply` rolls it out.

### Adding a new OCI pin to Renovate tracking
Put the annotation comment directly above the pinned value:
```
# renovate: datasource=docker depName=ghcr.io/garuda-tunnel/charts/<name>
```
Terraform `?ref=` pins need no annotation (native manager).

### Maintenance gotchas (learned the hard way)
- `renovatebot/github-action` publishes only full-semver tags — pin the exact
  version (`@v46.1.17`); there is no floating `@v46` tag.
- `renovate-config-validator` validates config as *repo* config, not *inherited*
  config — it can PASS while the runtime rejects the inherited config. In
  inherited config, `description` MUST be a JSON array, not a string.
- `config:recommended` (`:ignoreModulesAndTests`) ignores `**/examples/**`. Since
  the canonical pins live under `examples/mini-site/`, `renovate.json` overrides
  `ignorePaths` to un-ignore examples (tests/legacy stay ignored).
