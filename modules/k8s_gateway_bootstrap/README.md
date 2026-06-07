# k8s_gateway_bootstrap

Cluster-level (hub) bootstrap of the Gateway API ingress platform: enables
Traefik's kubernetesGateway provider, reconfigures websecure to :443, and
declares the single shared `platform-gateway` Gateway that any namespace's
HTTPRoute may attach to. Not garuda-specific.

## Inputs

| Variable | Type | Default | Description |
|---|---|---|---|
| `namespace` | string | (required) | Namespace where the Gateway lives (e.g. `gateway-system`). |
| `gateway_class_name` | string | (required) | Name of the GatewayClass to attach. For k3s+Traefik: `traefik`. |
| `cluster_issuer_name` | string | (required) | cert-manager ClusterIssuer name. cert-manager's gateway-shim creates one Certificate per listener `tls.certificateRefs[0]` Secret, using this issuer. |
| `hostnames` | list(object) | (required, non-empty) | One HTTPS listener per entry. Each object: `name` (lowercase kebab listener id), `hostname` (FQDN), `cert_secret_name` (Secret in the gateway namespace where cert-manager stores the leaf cert). |
| `labels` | map(string) | `{}` | Extra labels on the rendered Gateway. |
| `enable_traefik_gateway_provider` | bool | `true` | If true, renders a HelmChartConfig in `kube-system` that adds `providers.kubernetesGateway.enabled: true` to the bundled k3s Traefik release and reconfigures websecure to listen on :443. Set false if the stand already enables the provider out-of-band. |

## Outputs

| Output | Description |
|---|---|
| `gateway_name` | The rendered Gateway resource name (`platform-gateway`, owned by this module). |
| `gateway_namespace` | The namespace containing the Gateway. Pass both into consumer HTTPRoute `parentRefs`. |

## Consumer integration

Consumers create an `HTTPRoute` with a single `parentRef`:

```hcl
parentRefs = [{
  name      = module.k8s_gateway_bootstrap.gateway_name
  namespace = module.k8s_gateway_bootstrap.gateway_namespace
}]
```

cert-manager observes the Gateway annotation and creates one `Certificate`
per listener via the challenge type configured on the named ClusterIssuer
(no chart-side Certificate template required).
Routes from any namespace may attach (`allowedRoutes.namespaces.from: All`).

## Convention notes

- `hostnames[].name` is the listener id used by Gateway API
  (`listeners[].name`); keep it kebab-case and stable across revisions.
- `hostnames[].cert_secret_name` is the Secret cert-manager writes into.
  Convention: `<listener-name>-tls`.
- The Gateway name (`platform-gateway`) is the module's local constant,
  not a variable — there is exactly one Gateway per stand. Consumers
  must reference it via the output, not by hard-coded string.

## Design notes

### HelmChartConfig lives inside the chart, not as a top-level `kubernetes_manifest`

The `docs/artifacts/2026-05-29-gateway-api-precheck.md` artifact prescribed
rendering the Traefik `HelmChartConfig` overlay as a top-level
`kubernetes_manifest` resource in this module's `main.tf`, with an
explicit `depends_on` from the Gateway `helm_release` to that manifest.
The committed implementation deviates: the HelmChartConfig is a second
template inside the `platform-gateway` Helm chart and is therefore owned
by the same Helm release as the Gateway.

Tradeoffs:

- **Ownership coupling.** The HelmChartConfig (which controls the
  `kube-system/traefik` release) is now owned by the `platform-gateway`
  release in `gateway-system`. `helm uninstall platform-gateway` would
  also remove the `kubernetesGateway` provider override on Traefik.
  This is acceptable because the chart's whole reason to exist is the
  Gateway pipeline; the two resources lifecycle together by design.

- **Sequencing is implicit, not declared.** Inside one Helm release,
  HelmChartConfig and Gateway are applied together. k3s's bundled
  helm-controller reconciles the new HelmChartConfig asynchronously,
  so the Gateway will sit at `Programmed=Unknown / Waiting for
  controller` for a few seconds while Traefik restarts with the new
  provider arg. The smoke phase polls Gateway readiness, so this
  asynchrony is observed there, not silenced. Stands that already
  enable the provider out-of-band set
  `enable_traefik_gateway_provider = false` and avoid this dance.

- **No module-side validation that the provider was successfully
  enabled.** A consumer who sets `enable_traefik_gateway_provider =
  false` while the provider is in fact NOT enabled out-of-band gets a
  Gateway that never becomes Programmed. The smoke phase catches this
  failure mode; the module does not.

The in-chart placement is preferred over the top-level
`kubernetes_manifest` because the latter requires the Kubernetes
provider to fetch the `HelmChartConfig` CRD schema at plan time,
which is brittle in test environments without a live cluster
(notably the `tofu test` flow under `mock_provider`).

### This module is deliberately vendor-neutral

The module owns no garuda-specific configuration. The Gateway name
(`platform-gateway`), chart name (`platform-gateway`), and module
name (`k8s_gateway_bootstrap`) carry no `garuda` prefix because the
shared ingress primitive is a cluster-platform concern, not an
application concern. Garuda workloads consume this module only via
HTTPRoute `parentRefs` pointing at the module's `gateway_name` /
`gateway_namespace` outputs.
