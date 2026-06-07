# Garuda Terraform modules — organization contract

This directory holds the project's Terraform modules. New components are
self-contained modules with their artifacts co-located; the project is moving
away from Ansible roles as the home for workload images and config.

## 1. Layout

New **kube-only** modules live at `modules/<name>/` with **no `/kube` suffix**.
Precedents: `cert_manager/`, `k8s_gateway_bootstrap/`, `frr-sidecar/`,
`border_router/`. Legacy `*/kube` modules (`ipt_server/kube`, `firezone/kube`,
`wireguard/kube`) keep their suffix until separately refactored — they carry it
only because they once had compose-era `*/linux` siblings.

## 2. Structure

`main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`; `charts/<chart>/` for
Helm; `image/` for a component-local image build context when the module ships
its own image; `tests/` for tofu tests + helm goldens. Tests follow the project
test docstring template (`Validates: / Code: / Assertion: / Method:`) per
global-rules `testing.md`.

## 3. Image contract

The image build context is component-local in `modules/<name>/image/`, published
via the `.publish/public-workflows/publish-images.yml` matrix as
`ghcr.io/garuda-tunnel/garuda-<name>`, and defaulted inside the module's `variables.tf`
(`var.image`). Image source for new modules is co-located in `modules/<name>/image/`.

## 4. FRR sidecar reuse

OSPF-bearing modules consume the `frr-sidecar` library chart from OCI
(`oci://ghcr.io/garuda-tunnel/charts/frr-sidecar`, published by the external repo
`garuda-tunnel/garuda-frr-sidecar`) via a chart `dependencies:` entry with a pinned
version and `dependency_update = true` (per AGENTS.md), never by vendoring or
inlining. The consumer chart owns `mergeOverwrite` injections of workload-
specific OSPF invariants (interfaces list, passive interfaces,
`transit_provider`); the library chart is read-only.

## 5. Helm dependency artefacts

`.gitignore` MUST cover `/modules/**/charts/*/charts/` and
`/modules/**/charts/*/Chart.lock` (layout-agnostic — covers both
`modules/<name>/charts/...` and `modules/<name>/kube/charts/...`).

## 6. Direction (transitional state)

New components are self-contained Terraform modules with co-located artifacts.
The five existing images (`ipt-server`, `powerdns`, `wireguard`,
`ospf-injector`, `frr-sidecar`) are being migrated to co-located
`modules/<name>/image/` contexts. During this transition, matrix cells and
`paths:` filters in `publish-images.yml` mix legacy image dirs and
`modules/<name>/image/...` sources.
