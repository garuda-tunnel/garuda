# Garuda Platform Rules for Agent Workers

> Canonical single-source platform rules for all `garuda-tunnel/*-internal` repos.
> Authoritative spec: `docs/superpowers/specs/2026-06-20-garuda-annotation-layer-design.md`
> Local path from any *-internal worktree: `../garuda/docs/AGENTS-platform.md`

---

## Injection engine

Garuda uses **upstream `MutatingAdmissionPolicy` (MAP) + `ValidatingAdmissionPolicy` (VAP)**
at `admissionregistration.k8s.io/v1` (GA on k3s v1.36.1+). No Kyverno. No custom
admission webhook. No custom CRD controller. No Docker-socket operator.

`reinvocationPolicy: Never` is a **required field** on every MAP spec (omitting it causes
a `Required value` API validation error). The value must be `Never` (not `IfNeeded`)
because this MAP includes JSONPatch `op: add` on atomic lists (`spec.securityContext.sysctls`,
`spec.volumes[].downwardAPI.items`); under `IfNeeded`, reinvocation duplicates entries,
causing admission failure — confirmed empirically in smoke 2
(`docs/artifacts/2026-06-21-vpn-test2-map-smoke2-structural.md`, findings E3 + E4).
With a single MAP in the admission chain, `Never` costs nothing in practice.

- MAP (`garuda-inject-fabric`): structural injection — frr-sidecar native sidecar
  (`spec.initContainers[]` with `restartPolicy: Always`), pod-level sysctls, volumes,
  conditional ConfigMap mounts (Tier 2/3), `profile-observed-rev` observability annotation.
- VAP (`garuda-validate-intent`): intent validation — profile label presence, XOR invariants
  (`transit-provider` vs `transit-interfaces`; `frr-mode=raw` vs `interfaces`/`redistribute`),
  schema/format checks. Does NOT validate NAD names.
- One MAPBinding per profile; `objectSelector` matches the `net.garuda-tunnel/profile` **label**.
- `paramRef` resolves to the matching profile ConfigMap (`garuda-profile-<name>` in `garuda` ns).

Spec reference: `docs/superpowers/specs/2026-06-20-garuda-annotation-layer-design.md` §3.

---

## Annotation prefix

All garuda-managed keys use the prefix `net.garuda-tunnel/`.

The **only** `net.garuda-tunnel/*` key that is a **label** (not an annotation) is
`net.garuda-tunnel/profile`. It is a label because `MutatingAdmissionPolicyBinding.spec.matchResources.objectSelector`
matches pod labels, routing each per-profile Binding to its ConfigMap. All other
`net.garuda-tunnel/*` keys are annotations (configuration intent).

---

## Profile is a LABEL on the pod template

```yaml
# On the workload Deployment spec.template.metadata.labels:
net.garuda-tunnel/profile: ospf-router
```

MAPBinding `objectSelector` dispatches on this label. Profile ConfigMaps are
named `garuda-profile-<name>` in the `garuda` namespace.

**Three canonical profiles (no others):**

| Profile | Workloads | Key invariants |
|---------|-----------|----------------|
| `ospf-router` | wireguard, firezone | `transit_role: none`; sysctl variant-A (with `src_valid_mark`) |
| `transit-provider` | ipt-server | `transit_role: provider`; `default_originate: true`; no `redistribute: kernel` |
| `border` | border-router | `transit_role: none`; interfaces/passive hardcoded; sysctl variant-B |

Do not create per-stand or per-workload profiles. Differentiation between instances of the
same role is done via per-instance annotations (`net.garuda-tunnel/redistribute`,
`default-originate`, `transit-interfaces`, `nic-attach`).

---

## Two-key annotation model (non-negotiable)

| Key | Owner | Purpose |
|-----|-------|---------|
| `net.garuda-tunnel/profile-rev` | `garuda_guest` Terraform | Rollout trigger: `sha256(jsonencode(all intent inputs) + ":" + garuda_chart_version)`. Written ONLY by `garuda_guest`. MAP does NOT write this key. Changing any intent input or the garuda chart version changes this value → rolling update. |
| `net.garuda-tunnel/profile-observed-rev` | MAP (`garuda-inject-fabric`) | Observability stamp: `params.metadata.resourceVersion` at admission. Records which ConfigMap revision was active when the pod was admitted. NOT a rollout trigger. Written ONLY by MAP via `ApplyConfiguration` on `metadata.annotations`. |

- `net.garuda-tunnel/profile-rev` MUST NOT be set from anywhere other than `garuda_guest` Terraform output.
- `net.garuda-tunnel/profile-observed-rev` MUST NOT be written from anywhere other than the MAP CEL expression `params.metadata.resourceVersion`.

---

## `garuda_guest` pure-data Terraform module

`garuda_guest` (at `garuda-internal/modules/garuda_guest/`) is a **pure data module**:

- No `helm_release`. No Kubernetes resources. No side effects.
- Outputs ONLY: `annotations map(string)`, `labels map(string)`, `configmaps map(string)`.
- Computes `k8s.v1.cni.cncf.io/networks` (HCL `name@iface` join of fabric + workload NADs).
- Computes all `net.garuda-tunnel/*` intent annotations.
- Computes `net.garuda-tunnel/profile-rev` rollout-trigger hash.
- Instantiated once per guest workload at the stand level; outputs are passed as generic
  `annotations`/`labels`/`configmaps` inputs to vanilla guest modules.
- Reads NO files — the rollout-trigger hash is purely TF-input-based + `garuda_chart_version`.

---

## Vanilla guest contract

Workload modules (`wireguard-internal/kube`, `firezone-internal/kube`, `router-internal/kube`,
`border-router-internal`) accept ONLY:

```hcl
variable "annotations"  { type = map(string) }
variable "labels"        { type = map(string) }
variable "configmaps"    { type = map(string) }
```

They NEVER:
- Reference `net.garuda-tunnel/*` key names internally.
- Import garuda-specific helpers or modules.
- Declare a Helm dependency on the garuda chart.
- Declare `frr-sidecar` in their `Chart.yaml` `dependencies:`.
- Call `frr-sidecar.container`, `frr-sidecar.volume`, or `frr-sidecar.configmap` templates.

Garuda knowledge lives exclusively in `garuda_guest` and stand-level wiring.

The `configmaps` output contract: if non-empty, the vanilla guest module MUST render
and apply each entry as a ConfigMap in its namespace BEFORE the pod is admitted. The MAP
then mounts them by name on the injected sidecar (Tier 2/3 conditional mounts).

---

## Bootstrap timing: `time_sleep 10s`

MAP/MAPBinding propagation to the API server takes ~3–5 s after object creation
(confirmed empirically, smoke 1). Terraform MUST include:

```hcl
resource "time_sleep" "map_propagation" {
  create_duration = "10s"
  depends_on      = [helm_release.garuda]
}
```

All workload modules MUST have `depends_on = [time_sleep.map_propagation]`.
`depends_on` alone sequences apply order but does NOT absorb propagation latency —
`time_sleep` is the only available mechanism.

---

## Multus attach-race: root fix + insurance

**Root fix — host-local IPAM (already adopted):** Both `backbone` (172.30.0.0/24) and
`border` (172.29.0.0/24) NADs MUST use `host-local` IPAM. This eliminates the
`whereabouts` allocation race on reboot. Never revert to `whereabouts`.

**Insurance — pod-reaper (RETAINED, project-owner decision):** The `target/pod-reaper`
Deployment watches for UNREADY pods (threshold ~120 s) and deletes them. The owning
ReplicaSet creates a new pod object → fresh API admission pass → fresh CNI ADD from
Multus. This is the recovery mechanism for residual attach-race anomalies that host-local
IPAM does not prevent (Multus crash mid-ADD, extreme reboot-edge-case timing). Do not
remove pod-reaper without an explicit project-owner decision.

Spec reference: `docs/superpowers/specs/2026-06-20-garuda-annotation-layer-design.md` §7.2.

---

## CEL guard invariants (mandatory, not optional)

Every CEL expression that reads `object.metadata.annotations` or `object.metadata.labels`
MUST be guarded with `has()` or `.?...orValue({})`. Unguarded access crashes CEL with
`no such key: annotations` (or `labels`), and with `failurePolicy: Fail` this DENIES the
pod at admission — silently rejecting all bare pods cluster-wide.

- Correct: `object.metadata.?annotations.orValue({})['key']`
- Correct: `has(object.metadata.annotations) && 'key' in object.metadata.annotations`
- WRONG: `object.metadata.annotations['key']` (crashes if annotations absent)

Confirmed empirically: smoke 2 finding E1
(`docs/artifacts/2026-06-21-vpn-test2-map-smoke2-structural.md`).

---

## ApplyConfiguration vs JSONPatch field rules

Atomic-list fields (`spec.securityContext.sysctls`, `spec.volumes[].downwardAPI.items`,
`spec.volumes[].downwardAPI.items[].fieldRef`) CANNOT be written via `ApplyConfiguration`
(apiserver returns `may not mutate atomic arrays` — smoke 2 findings E3, E6). Use
JSONPatch `op: add` on `/-` end-of-list paths instead.

`ApplyConfiguration` on `metadata.annotations` auto-creates the parent map and is safe
without a `has()` guard — preferred for annotation injection. JSONPatch `add` on an absent
`/metadata/annotations/<key>` fails if the parent map does not exist (smoke 2 finding E5).

SSA-only single-element list pattern (`[new_entry]` without prepending
`object.spec.initContainers + [new]`) is mandatory for `spec.initContainers` and
`spec.volumes` mutations. The concat pattern duplicates entries on reinvocation
(smoke 2 finding E2). SSA merge-by-name preserves existing entries and adds the new
entry idempotently.

---

## frr-sidecar image contract

- **`/readyz` endpoint:** the image MUST expose `0.0.0.0:9179` at path `/readyz`.
  Returns HTTP 200 when FRR is running and `vtysh` responds (NOT OSPF Full). Returns
  HTTP 503 otherwise. The existing `/health` on `127.0.0.1:7890` (loopback-only) is NOT
  usable as a kubelet readinessProbe target.
- **`render_frr.py`:** Python script at `/usr/lib/frr/render_frr.py` (Python stdlib only —
  no Jinja2, no `gomplate`, no `envsubst`). Reads env vars and renders the FRR config
  at container startup.
- **Single toolchain:** `python3` is the only scripting runtime in the image. No `jq`,
  no `envsubst`, no shell substring hacks.
- **BACKBONE_IP extraction:**
  ```sh
  BACKBONE_IP=$(ip -j addr show backbone | python3 -c \
    'import json,sys; print(json.load(sys.stdin)[0]["addr_info"][0]["local"])')
  ```
- **SIGTERM handling:** the entrypoint MUST trap SIGTERM, stop FRR daemons gracefully,
  and exit with code 0. Unhandled SIGTERM causes the pod to hang at shutdown.
- **Readiness probe does NOT gate on OSPF Full** — it gates on FRR process liveness only.
  Gating on OSPF Full would deadlock WireGuard/Firezone workloads (tunnel interface `wg0`
  only exists after the guest container starts; OSPF cannot reach Full before that).

Spec reference: `docs/superpowers/specs/2026-06-20-garuda-annotation-layer-design.md` §7.4, §13.

---

## Anti-patterns (applies to ALL repos in garuda-tunnel)

- **NO CUSTOM** mutating webhook / CRD controller / Docker-socket operator for sidecar
  injection. Upstream MAP/VAP at `admissionregistration.k8s.io/v1` are NOT custom webhooks —
  they are the approved in-tree injection engine. Any other injection mechanism is forbidden.
- **NO Kyverno.** Kyverno was evaluated and rejected (spec §3.2). Do not introduce it.
- **NO `garuda-allowed-nads` allowlist** ConfigMap or VAP rule validating NAD names at
  admission — it does not fit workloads that carry their own NADs (e.g. `wg-firezone`).
  NAD existence is enforced by bootstrap order only.
- **NO startup-gating** of guest containers on sidecar readiness. No `readinessGates`.
  No mechanism that waits for OSPF Full before starting the guest. This would deadlock
  WireGuard/Firezone.
- **NO `mutateExisting` healing.** Pod spec fields are immutable post-creation; healing
  requires pod delete + recreate (pod-reaper handles this).
- **NO `whereabouts` IPAM** on backbone or border NADs. Use `host-local` only.
- **NO** setting `net.garuda-tunnel/profile-rev` from anywhere other than `garuda_guest`
  Terraform output.
- **NO** writing `net.garuda-tunnel/profile-observed-rev` from anywhere other than the
  MAP CEL expression `params.metadata.resourceVersion`.
- Pin any image or chart to a non-immutable tag (e.g. `latest`) — always pin semver.
- Use `jq`, `envsubst`, or `gomplate` in the frr-sidecar entrypoint — Python stdlib only.
- Add `restartPolicy: Always` to `egress-setup` in border-router — it is a one-shot init
  container, NOT a native sidecar.
