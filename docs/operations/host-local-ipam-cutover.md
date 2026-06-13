# Operator runbook: host-local IPAM cutover (whereabouts removal)

Applies the `garuda_k8s` change that switches the `backbone`/`border`
NetworkAttachmentDefinitions from `whereabouts` IPAM to `host-local`, and removes
the whereabouts DaemonSet/CRDs. See design:
`docs/superpowers/specs/2026-06-13-host-local-ipam-design.md`.

## Why drain

An in-place `apply` is unsafe for two reasons:

1. Terraform upgrades `garuda-cni` before `garuda` (`helm_release.garuda
   depends_on helm_release.garuda_cni`), so for a moment the live NADs still say
   `whereabouts` while the whereabouts CRDs/binary are already gone — any pod CNI
   ADD in that window fails.
2. Already-running pods keep their whereabouts-era secondary IPs; host-local has
   no record of them, so a pod created during the window could collide on an
   in-use IP.

Cordoning + draining the single-node hub removes all NAD-consuming workloads for
the duration of the apply, closing both windows. After uncordon every pod is
recreated fresh against the host-local NADs.

## Procedure (run from the operator workstation with hub kubeconfig)

Set the node name first:

```bash
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
echo "hub node: ${NODE}"
```

1. Cordon and drain:

   ```bash
   kubectl cordon "${NODE}"
   kubectl drain "${NODE}" --ignore-daemonsets --delete-emptydir-data --force --timeout=300s
   ```

   On a single-node hub this drain evicts every non-DaemonSet pod, but those
   pods cannot reschedule (the only node is cordoned) — they go `Pending` until
   uncordon. A non-zero exit from `kubectl drain` due to `--timeout` is therefore
   EXPECTED and acceptable, provided the only thing keeping it from finishing is
   un-reschedulable system pods. Confirm the drain is benign:

   ```bash
   # All non-Running/Completed pods should be Pending (waiting for uncordon),
   # NOT stuck Terminating. No NAD-consumer (wg-hub-ros, ipt-server, firezone,
   # wg-hub-*) should still be Running/Terminating:
   kubectl get pods -A -o wide | grep -vE 'Running|Completed' || echo "all settled"
   kubectl get pods -A -o wide | grep -E 'wg-hub|ipt-server|firezone' || echo "no NAD-consumers left (good)"
   ```

   If `kubectl drain` hangs instead of timing out, a PodDisruptionBudget is
   blocking it (firezone / ipt-server may define one). `--force` does NOT override
   a PDB. Either temporarily relax the PDB, or evict the specific blocked
   NAD-consumer pods directly:

   ```bash
   kubectl delete pod -n <ns> <nad-consumer-pod> --grace-period=0 --force
   ```

   OSPF adjacency WILL drop while the FRR-sidecar pods are evicted; this is
   expected for the duration of the cutover window and recovers after uncordon.

2. Only once the gate above shows no NAD-consumer pods are Running/Terminating,
   apply the garuda stack for this stand. Run `terragrunt apply` from the stand's
   `deploy/garuda` unit (e.g. `test-config/vpn2/deploy/garuda` for vpn2) and pass
   `-parallelism=1` (stand convention to avoid the helm OCI frr-sidecar race).
   This upgrades both the `garuda-cni` and `garuda` helm releases.

3. Uncordon:

   ```bash
   kubectl uncordon "${NODE}"
   ```

4. Verify workloads come back with both secondary interfaces:

   ```bash
   kubectl get pods -A -o wide
   # For a representative NAD-consuming pod (wg-hub-ros, ipt-server, firezone):
   kubectl get pod -n <ns> <pod> -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}' | jq .
   ```

   Expected: `network-status` lists `garuda/backbone` and `garuda/border`
   interfaces with IPs (not just `eth0`).

5. Verify host-local lease files exist on tmpfs (SSH to the hub):

   ```bash
   ls -la /var/run/cni/backbone /var/run/cni/border 2>/dev/null || echo "no leases yet (no NAD pod scheduled?)"
   ```

   Expected: one file per allocated pod IP under each directory.

6. Verify OSPF adjacency reformed (FRR sidecars reach backbone). Use the stand's
   normal OSPF check (e.g. RouterOS neighbor count back to its expected value).

## Whereabouts cleanup verification

The whereabouts CRDs are template-managed (not under a `crds/` dir), so the helm
upgrade deletes the DaemonSet, RBAC, ConfigMap, and the three CRDs; deleting a CRD
cascades to its CRs. Verify across all scopes:

```bash
# Namespaced resources (whereabouts ran in kube-system):
kubectl get ds,sa,cm -n kube-system | grep -i whereabouts || echo "none (good)"
kubectl get ds,sa,cm -n garuda     | grep -i whereabouts || echo "none (good)"
# Cluster-scoped:
kubectl get clusterrole,clusterrolebinding | grep -i whereabouts || echo "none (good)"
# CRDs:
kubectl get crd | grep whereabouts || echo "none (good)"
```

Fallback if any whereabouts CRD lingers:

```bash
kubectl delete crd \
  ippools.whereabouts.cni.cncf.io \
  overlappingrangeipreservations.whereabouts.cni.cncf.io \
  nodeslicepools.whereabouts.cni.cncf.io
```

Optional host hygiene (non-functional; the orphaned binary/config are inert once
no NAD references whereabouts):

```bash
# Locate any leftover whereabouts artifacts on the host (paths can vary by
# k3s version), then remove them:
find /var/lib/rancher/k3s -name '*whereabouts*' 2>/dev/null
# rm -f the paths reported above once confirmed.
```

## Rollback

Revert the `garuda_k8s` change on the consumed ref and re-apply with the same
cordon/drain → apply → uncordon procedure. (whereabouts is reinstalled by the
restored `garuda-cni` chart; NADs revert to `whereabouts` IPAM.)
