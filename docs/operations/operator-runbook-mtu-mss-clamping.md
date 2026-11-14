# Operator runbook — MTU / TCP-MSS clamping defense-in-depth

**Scope:** verify and (if needed) roll back the 3-layer bidirectional
TCP-MSS clamping + WireGuard MTU alignment across the garuda-tunnel data path.
The values come from one site-level `mtu_policy`; what it is, what it governs
and how to change it: [mini-site README](../../examples/mini-site/README.md#site-mtumss-policy-mtu_policy).

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
| **firezone sidecar** | `firezone` (`wg-firezone`) | chart-owned `mss-clamp` sidecar; load-bearing Chain-B return clamp. Details: [Firezone MSS clamp runbook](https://github.com/garuda-tunnel/firezone/blob/main/docs/operations/operator-runbook-mss-clamp.md) | both |
| **ipt-server central** | `ipt-server` (`backbone`) | `table inet ipt_server_mss`, fixed MSS (`fixed_mss`) on `iifname`+`oifname backbone` | **forward only** (return is asymmetric — bypasses ipt-server, see §1 note) |
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

**MTU alignment:** both sides of every garuda tunnel (wg pods and the RouterOS
`wg-hub-ros`) use the site `effective_mtu` (1330 for `site_mtu = 1330`).
`wg-firezone` is Firezone-managed at 1280 (`firezone_client_mtu`).

**Fixed MSS = `site_mtu - 40`** (1290 at 1330); Firezone caps it at
`firezone_client_mtu - 40` = 1240 (≥ QUIC's RFC 9000 1200-byte floor).

---

## 2. Changing the site MTU

Edit `local.mtu_policy` and apply; the pods roll (details in the
mini-site README linked above). The clamps are part of every component version, so lowering the MTU
needs no separate wave. Expect a **brief PMTUD churn** as in-flight segments
re-discover the path MTU; sessions are not dropped (WireGuard MTU is per-side
independent). Verify with §3 afterwards.

---

## 3. Verification (run after each apply that changes the policy)

Run on the stand kubeconfig (hub). Repeat the egress checks through **all three
egress** (RU border / USA / Mexico) and in **both** directions.

### 3.1 Clamp rules are firing (nft counters)

```bash
# ipt-server central forward clamp (dedicated inet table):
sudo kubectl -n garuda exec deploy/ipt-server -c ipt-server -- nft list table inet ipt_server_mss
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
# On an active TCP session through each egress (expect advmss at or below `fixed_mss`: 1290 at `site_mtu = 1330`, 1240 via Firezone):
ss -ti | grep -A1 ESTAB | grep -oE 'mss:[0-9]+|rcv_mss:[0-9]+|advmss:[0-9]+'
```

### 3.3 firezone sidecar

Verify the Chain-B return clamp and the readiness gate per the
[Firezone MSS clamp runbook](https://github.com/garuda-tunnel/firezone/blob/main/docs/operations/operator-runbook-mss-clamp.md).

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
# QUIC works because all inner payloads >= 1200 floor (see §6); UDP is not clamped:
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

## 5. Rollback

Per-layer off-switches (pick the smallest action that unblocks):

| Layer | Off-switch |
|---|---|
| ipt-server | `mtu_policy.mss_clamp_enabled = false` |
| border-router | `mtu_policy.mss_clamp_enabled = false` |
| firezone | See the [Firezone MSS clamp runbook](https://github.com/garuda-tunnel/firezone/blob/main/docs/operations/operator-runbook-mss-clamp.md) |
| wireguard postup | `mtu_policy.mss_clamp_enabled = false` disables the `iifname` fixed-MSS rule; the `oifname` route-PMTU clamp is always present |
| RouterOS `wg_tik` | delete the manually-added mangle rules (`/ip firewall mangle remove [find comment~"garuda-wg_tik"]`) |
| MTU alignment | revert `local.mtu_policy` to the prior value (one object feeds the wireguard, RouterOS and `border` NAD values) |

**Full revert:** downgrade the chart/module via the stand pin (point the pin
back to the pre-clamp chart/module version and `terragrunt apply`). This reverts
all layers atomically for that node.

---

## 6. QUIC math (corrected)

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
| garuda tunnels (`site_mtu` 1330, incl. `wg-hub-ros`) | 1330 − 28 = **1302** | ✓ |

All paths clear the RFC 9000 1200-byte floor. QUIC **works**;
it is UDP and is never MSS-clamped. The TCP MSS is a TCP value and is NOT
used as QUIC evidence — the QUIC levers are a consistent MTU + transiting ICMP
PTB (§3.4), both of which hold. A `wg-firezone` MTU increase is **not** needed
for QUIC.

---

## 7. Post-apply verification

After an apply, run `tofu plan -detailed-exitcode`; exit code 0 confirms there
is no drift. The only e2e suite is the local stand:
[`examples/local-stand/e2e/README.md`](../../examples/local-stand/e2e/README.md).
