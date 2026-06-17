# Changelog

## [0.4.0](https://github.com/garuda-tunnel/garuda-internal/compare/v0.3.0...v0.4.0) (2026-06-17)


### Features

* **garuda:** enable pod-reaper part-of label filter by default ([cf1ab61](https://github.com/garuda-tunnel/garuda-internal/commit/cf1ab61e97f5d294dcf56ac5f515021a78ed164b))
* **garuda:** enable pod-reaper part-of label filter by default ([0197ca6](https://github.com/garuda-tunnel/garuda-internal/commit/0197ca6a0b2c88a669c3aa4d8fc9384dcd4ddac6))

## [0.3.0](https://github.com/garuda-tunnel/garuda-internal/compare/v0.2.2...v0.3.0) (2026-06-17)


### Features

* **garuda:** add Multus readiness pre-install hook + RBAC ([34e0561](https://github.com/garuda-tunnel/garuda-internal/commit/34e056130e87b084c9109e3819d61e61c1b052bc))
* **garuda:** add pod-reaper insurance layer for Multus attach race ([906baa5](https://github.com/garuda-tunnel/garuda-internal/commit/906baa5cceda300a2035b877d564b749bb3b4cc2))
* **k3s-edge:** Phase 1 — modules/garuda_k8s + modules/wireguard/kube + operator scripts ([#39](https://github.com/garuda-tunnel/garuda-internal/issues/39)) ([bcf25ed](https://github.com/garuda-tunnel/garuda-internal/commit/bcf25edc1d2dc16c53ccb876374a707c404509ea))


### Bug Fixes

* **garuda_k8s/chart:** move NOTES.md out of templates/ ([05eae5c](https://github.com/garuda-tunnel/garuda-internal/commit/05eae5c69b87356b781020f926cab95cff62d971))
* **garuda_k8s:** create namespace via explicit kubernetes resource ([c9451b9](https://github.com/garuda-tunnel/garuda-internal/commit/c9451b954f8a2d3ca803af33dbdfad7dfd660af4))
* **garuda_k8s:** split CNI install into garuda-cni chart so NAD CRD exists before NADs apply ([96ab965](https://github.com/garuda-tunnel/garuda-internal/commit/96ab96528cfa5f41c62e59ecfca0d4f65e650419))
* **garuda,tests:** Sub-project D review must-fixes ([fc22e6d](https://github.com/garuda-tunnel/garuda-internal/commit/fc22e6db94a5362e513a484845ee24efd7da601c))
* **modules/charts:** exclude .terragrunt-source-manifest from Helm chart ([096ac94](https://github.com/garuda-tunnel/garuda-internal/commit/096ac94ae6195208c35d5f92f73b0b69d6977c85))
* **phase2-border:** rely on CNI bridge ipMasq for border egress (revert WG_EGRESS_IFACE detour) ([bda7764](https://github.com/garuda-tunnel/garuda-internal/commit/bda77646e6226da9d0cc5bcb8b9150c1a840719c))
