# Vendored CNI installation manifests

| Component    | Upstream tag/build | Source URL |
|--------------|--------------------|------------|
| multus-cni   | v4.2.4             | https://github.com/k8snetworkplumbingwg/multus-cni |
| rke2-multus  | v4.2.413           | https://rke2-charts.rancher.io |

Re-vendoring procedure: download new upstream YAML, replace the file in this
directory (`templates/multus-daemonset.yaml`),
re-wrap each document in `{{- if .Values.installCni }}` … `{{- end }}`,
bump the tag table above, preserve the k3s-native CNI paths documented in
`https://docs.k3s.io/networking/multus-ipams`, run `helm lint`, regenerate
the golden files in `modules/garuda_k8s/tests/golden/`.

This chart is installed BEFORE the main `garuda` chart by
`modules/garuda_k8s/main.tf::helm_release.garuda_cni` with `wait = true`.
The wait blocks Terraform until the Multus DaemonSet becomes Ready, which is
when the `NetworkAttachmentDefinition` CRD (registered at runtime by
the Multus thick-plugin init container) is observable on the API server.
The main `garuda` chart's NAD resources then apply without race.

IPAM for the `backbone`/`border` NADs is the built-in `host-local` plugin
(no DaemonSet, no CRD); see `modules/garuda_k8s/charts/garuda/templates/`.
