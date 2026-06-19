# Operator runbook — MTU / TCP-MSS clamping defense-in-depth

**Scope:** roll out, verify, and (if needed) roll back the 3-layer bidirectional
TCP-MSS clamping + WireGuard MTU alignment across the garuda-tunnel data path.

**Audience:** operator on duty for the garuda-tunnel release.

**Cross-references:**
- Spec: `docs/superpowers/specs/2026-06-17-mtu-mss-clamping-defense-in-depth-design.md`
- Plan: `docs/superpowers/plans/2026-06-17-mtu-mss-clamping-defense-in-depth.md` (Task 8)
- Task 0 discovery: `docs/artifacts/2026-06-17-mtu-mss-task0-discovery.md` (gitignored)

> **Address policy (AGENTS.md):** this runbook uses only `example.net`,
> RFC5737 (`203.0.113.0/24`), RFC1918 (`192.168.88.0/24`, `10.0.24.0/24`,
> `172.30.0.0/24`) and CGNAT (`100.64.0.0/10`). The real hub address is written
> `<hub-endpoint>` and lives only in operator-private notes — never committed.
> Substitute a real large-object / QUIC test endpoint (`<large-object-url>`,
> `<quic-test-url>`) at verification time; do not commit one here.

---

## 1. Summary

Three layers of **bidirectional** transit-TCP MSS clamping, plus WireGuard MTU
alignment, so no single missing or mis-sized hop can blackhole a TCP flow and
QUIC keeps working over a consistent MTU + transiting ICMP PTB.

| Layer | Node(s) | Mechanism | Direction(s) |
|---|---|---|---|
| **WG pods** | `wg-hub-ros`, `wg-usa`, `wg-mexico`, both edge VMs | `postup.sh`: `oifname` clamp-to-pmtu (`rt mtu`) + `iifname` fixed MSS (`WG_FIXED_MSS`, chart-injected), gated on `WG_MSS_CLAMP_ENABLED`, in `table inet border_<iface>` | `oifname` = load-bearing return on the last WG hop; `iifname` = inbound-initiated defense |
| **firezone sidecar** | `firezone` (`wg-firezone`) | idempotent, readiness-gated NET_ADMIN sidecar installs **both** `oifname wg-firezone` clamp-to-pmtu (1280⇒MSS 1240, load-bearing Chain-B return) AND `iifname wg-firezone` fixed MSS 1240, in `table inet firezone_mss` (never edits `table inet firezone`) | both |
| **ipt-server central** | `ipt-server` (`backbone`) | `table inet ipt_server_mss`, fixed MSS 1240 on `iifname`+`oifname backbone` | **forward only** (return is asymmetric — bypasses ipt-server, see §1 note) |
| **border-router** | `border-router` (`backbone`) | `egress-setup` init container installs `table inet border_mss`, fixed MSS on `iifname`+`oifname backbone`, gated on `BR_MSS_CLAMP_ENABLED` | both, RU egress |
| **RouterOS** | RouterOS own tunnel `wg-hub-ros` (module); `wg_tik` only via operator CLI handoff (§4) | `change-mss new-mss=clamp-to-pmtu` mangle on `in-interface` + `out-interface` (PMTU per-flow) | bidirectional |

**Return-path fact (Task 0 DQ2 — ASYMMETRIC):** internet→client return traffic
does **not** traverse ipt-server. It routes via OSPF directly from the egress
WG pod across `backbone` to the **last WG pod facing the client**, where it is
clamped on `oifname`. So the load-bearing return clamp is:
- **Chain B (Firezone clients):** `firezone` `oifname wg-firezone`.
- **Chain A (RouterOS LAN clients):** `wg-hub-ros` `oifname wg-hub-ros`.

The ipt-server clamp is the **forward-direction** central defense layer; the
per-WG `iifname` rules cover inbound-initiated flows (defense-in-depth).

**MTU alignment (D6):** align both sides of each tunnel to the min:
`wg-usa`/`wg-mexico` hub side `1370 → 1330` (match edge); `wg-hub-ros` RouterOS
side `1420 → 1370` (match hub). `wg-firezone` already aligned at 1280.

**Default fixed MSS = 1240** everywhere (≥ QUIC's RFC 9000 1200-byte floor).

---

## 2. Rollout order (CRITICAL — spec §7.1, AC13)

Lowering MTU before the clamps are in place increases PMTUD/ICMP-PTB churn
(more segments need re-sizing while no clamp absorbs them). Therefore:

1. **Merge the 5 component PRs**, let release-please cut per-repo versions:
   - wireguard `#14` (postup bidirectional) + `#15` (RouterOS return + `wg_tik`
     handoff + `var.mtu`)
   - firezone `#13` (readiness-gated sidecar clamp)
   - router `#15` (ipt-server central forward clamp)
   - border-router `#11` (backbone forward clamp)

2. **Stand pin bump — land the clamps in risk order:**

   ```
   ipt-server  →  border-router  →  wireguard  →  firezone
   ```

   firezone is **last** — it is the riskiest (adds a NET_ADMIN sidecar + a
   readiness gate that blocks the firezone pod until the clamp is installed).
   Validate each layer before advancing to the next.

3. **Deploy the clamps BEFORE MTU alignment.** MTU lowering (Task 6) is a
   **separate, later wave** — only after the clamps are verified live.

4. **Per-stand order** (apply the whole sequence per stand before advancing):

   ```
   mini-site  →  vpn2  →  prod (prod last)
   ```

> The stand pin bump itself is a follow-up sub-project; this runbook only fixes
> the **order** it must follow.

---

## 3. Verification (run after each deploy wave, before advancing)

Run on the stand kubeconfig (hub). Repeat the egress checks through **all three
egress** (RU border / USA / Mexico) and in **both** directions.

### 3.1 Clamp rules are firing (nft counters)

```bash
# ipt-server central forward clamp (dedicated inet table):
sudo kubectl -n garuda exec deploy/ipt-server -c ipt-server -- nft list table inet ipt_server_mss
# firezone load-bearing Chain-B return clamp:
sudo kubectl -n garuda exec deploy/firezone   -c mss-clamp   -- nft list table inet firezone_mss
# each WG pod (oifname rt mtu + iifname fixed MSS):
sudo kubectl -n garuda exec deploy/wg-hub-ros -c wg -- nft list table inet border_wg-hub-ros
sudo kubectl -n garuda exec deploy/wg-usa     -c wg -- nft list table inet border_wg-usa
sudo kubectl -n garuda exec deploy/wg-mexico  -c wg -- nft list table inet border_wg-mexico
# border-router backbone clamp (egress-setup is an init container; nft state is not
# observable after it exits — verify via logs that the clamp was installed):
sudo kubectl -n garuda logs deploy/border-router -c egress-setup | grep 'MSS clamp installed'
```
Confirm the `tcp option maxseg size set ...` rules are present and their packet
counters are non-zero on an active stand (run some TCP traffic first).

### 3.2 Observed MSS on a live session

```bash
# On an active TCP session through each egress (expect advmss ~1240, never above):
ss -ti | grep -A1 ESTAB | grep -oE 'mss:[0-9]+|rcv_mss:[0-9]+|advmss:[0-9]+'
```

### 3.3 firezone sidecar readiness gate

```bash
# Ready flag exists (gates firezone readiness) and firezone pod is Ready:
sudo kubectl -n garuda exec deploy/firezone -c mss-clamp -- test -f /var/lib/clamp/ready && echo READY-FLAG-OK
sudo kubectl -n garuda get pod -l app.kubernetes.io/name=firezone -o wide
```

### 3.4 ICMP PTB still transits (regression guard for PMTUD/QUIC)

```bash
# PMTU is discovered (ICMP type-3 code-4 / ICMPv6 PtB not dropped):
tracepath -n <large-object-url> 2>&1 | grep -i pmtu
```

### 3.5 Large-object HTTPS — no blackhole (both directions, 3 egress)

```bash
# Large download through each egress (US / MX / RU). No hang, full size:
curl -s -o /dev/null -w 'code=%{http_code} dl=%{size_download} t=%{time_total}\n' \
  https://<large-object-url>
```
Run an inbound-initiated (upload / service-through-tunnel) flow too where
applicable, to exercise the `iifname` defense direction.

### 3.6 QUIC / HTTP3 through each egress

```bash
# QUIC works because all inner payloads >= 1200 floor (see §8); UDP is not clamped:
curl --http3 -s -o /dev/null -w '%{http_version} %{http_code}\n' https://<quic-test-url>
```

### 3.7 DF path-MTU probe from a client

```bash
# From a wg-client, DF probe toward an RFC5737 target — confirms path MTU, no fragmentation needed:
ping -M do -s 1400 -c 3 203.0.113.1 || true   # expect "message too long" then PMTUD settles lower
tracepath -n 203.0.113.1
```

---

## 4. wg_tik operator handoff (RESIDUAL RISK)

The RouterOS client tunnel `wg_tik` (MTU 1280) is **not owned** by the wireguard
RouterOS module (Task 0 DQ5 — operator-provisioned). **By design, the module
clamps only the tunnel it owns (`wg-hub-ros`) and manages no foreign / operator
-managed interfaces** — there is **no** declarative module option for `wg_tik`.
Clamping it is therefore a pure operator handoff: apply the bidirectional clamp
by hand on the RouterOS device.

**Manual RouterOS CLI** — the only way to clamp `wg_tik`:

```
/ip firewall mangle add chain=forward action=change-mss new-mss=clamp-to-pmtu passthrough=yes protocol=tcp tcp-flags=syn out-interface=wg_tik comment=garuda-wg_tik-out
/ip firewall mangle add chain=forward action=change-mss new-mss=clamp-to-pmtu passthrough=yes protocol=tcp tcp-flags=syn in-interface=wg_tik comment=garuda-wg_tik-in
```

> **If the operator does not apply this snippet, `wg_tik` clients fall back to
> PMTUD/ICMP only — RESIDUAL RISK.** This is a conscious decision: the module
> does not manage interfaces it does not own. Record the decision (clamped by
> hand vs deferred) in the sub-project completeness report (AC5).

---

## 5. MTU alignment disruption note

The MTU-lowering wave (after clamps are verified):
- `wg-usa` / `wg-mexico` hub side `1370 → 1330`
- `wg-hub-ros` RouterOS side `1420 → 1370`

Applying a lower MTU causes a **brief PMTUD churn** on each side as in-flight
segments re-discover the path MTU, but **does not drop sessions**: WireGuard MTU
is per-side independent, and the clamps (already deployed) absorb the resizing.
Apply this wave **only after** §3 verification passes for the clamps.

---

## 6. Per-chain MSS optional tuning (spec §9 — OFF by default)

The default is a single fixed MSS **1240** on ipt-server for both chains
(simplicity + safety). Chain A's true bottleneck is `wg-hub-ros` 1370 ⇒ MSS
1330, so the fixed 1240 **over-clamps Chain A by ~90 bytes ≈ ~6.8% TCP
throughput** on that chain. An operator who wants that back can opt into a
per-chain split on ipt-server, keyed by client source subnet:

```
table inet ipt_server_mss {
    chain mss_clamp {
        type filter hook forward priority mangle; policy accept;
        # Chain A (RouterOS LAN clients) — bottleneck wg-hub-ros 1370
        ip saddr 192.168.88.0/24 tcp flags syn tcp option maxseg size set 1330
        ip daddr 192.168.88.0/24 tcp flags syn tcp option maxseg size set 1330
        # Chain B (Firezone clients) — bottleneck wg-firezone 1280
        ip saddr 10.0.24.0/24 tcp flags syn tcp option maxseg size set 1240
        ip daddr 10.0.24.0/24 tcp flags syn tcp option maxseg size set 1240
    }
}
```

**Tradeoff:** +~6.8% Chain-A throughput vs more rules + per-stand subnet
knowledge + the single safe fixed value being lost. **Default stays 1240.**
(The Chain-B return clamp is still `firezone` `oifname wg-firezone`, unaffected.)

---

## 7. Rollback

Per-layer off-switches (pick the smallest action that unblocks):

| Layer | Off-switch |
|---|---|
| ipt-server | `--set mtuPolicy.mssClampEnabled=false` |
| border-router | `--set mtuPolicy.mssClampEnabled=false` |
| firezone | `--set mtuPolicy.mssClampEnabled=false` (removes iifname fixed-MSS rule; oifname route-PMTU clamp remains) |
| wireguard postup | `--set mtuPolicy.mssClampEnabled=false` disables the `iifname` fixed-MSS rule; the `oifname` route-PMTU clamp is always present |
| RouterOS `wg_tik` | delete the manually-added mangle rules (`/ip firewall mangle remove [find comment~"garuda-wg_tik"]`) |
| MTU alignment | revert `mtuPolicy.effectiveMtu` in the wireguard chart and `var.mtu_policy.effective_mtu` in the RouterOS module to the prior value |

**Full revert:** downgrade the chart/module via the stand pin (point the pin
back to the pre-clamp chart/module version and `terragrunt apply`). This reverts
all layers atomically for that node.

---

## 8. QUIC math (corrected)

An earlier audit note claimed QUIC was at risk via a "double-WG nesting"
(1192 < 1200). **That is wrong — there is no such nesting in this topology.**
The WireGuard interface MTU limits the **inner** packet; the encapsulated outer
packet (inner + 60 WG overhead) travels over flannel (1450) / the 1500 underlay
without fragmentation. WG overhead is applied **once**, to the outer packet — it
is not subtracted a second time from the inner payload.

Corrected inner QUIC UDP payload (= WG MTU − 28 for IPv4 IP+UDP):

| Path / WG MTU | Inner UDP payload | ≥ 1200 floor? |
|---|---|---|
| `wg-firezone` 1280 | 1280 − 28 = **1252** | ✓ |
| `wg-usa` / `wg-mexico` 1330 (post-align) | 1330 − 28 = **1302** | ✓ |
| `wg-hub-ros` 1370 | 1370 − 28 = **1342** | ✓ |

All paths clear the RFC 9000 1200-byte floor post-alignment. QUIC **works**;
it is UDP and is never MSS-clamped. The TCP MSS 1240 is a TCP value and is NOT
used as QUIC evidence — the QUIC levers are a consistent MTU + transiting ICMP
PTB (§3.4), both of which hold. A `wg-firezone` MTU increase is **not** needed
for QUIC.

---

## 9. Final live gate

Per AGENTS.md, the final live gate is the companion-environment playbook:

```bash
ansible-playbook test-config/vpn2/smoke/z2g.yml
```

Public docs point to `examples/mini-site/smoke` once the in-repo `z2g.yml`
exists. The stand pin bump (`prod`, `mini-site`, `vpn2`) is the follow-up
sub-project where AC15 live verification runs.
