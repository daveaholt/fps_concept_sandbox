# 12 — Hosting the Dedicated Server (Azure)

**Decisions:** on-demand VM (start before a session, deallocate after) · region **Central US** (Iowa — near Chicago, decent middle for US-spread friends) · access gated by the embedded client key (10) with the VM firewall as a coarse outer layer. Implemented as the **MH milestone** (08) together with its prerequisite, the embedded-key auth handshake (10) — slot it any time after M6, before inviting friends.

## Shape

One small Ubuntu LTS VM running the headless Linux dedicated-server export as a systemd service.

| Piece | Choice | Why |
|---|---|---|
| VM size | `Standard_B2als_v2` (2 vCPU, 4 GiB) | ~$0.038/hr; burstable is fine — an 8-player 60 Hz Godot headless sim is light. If CPU-credit throttling ever shows in the tick timing log, step up to `D2as_v5` (dedicated cores) and eat ~2× the hourly rate. |
| OS | Ubuntu Server LTS (x86_64) | Boring and known-good with Godot exports. |
| Disk | 30 GB Standard SSD | Server build is ~100 MB; smallest disk is plenty. Disk bills even while the VM is deallocated (~$2/mo) — that's the "idle" cost. |
| Networking | NSG: game port UDP open (world, key-gated at app layer per 10); SSH 22 restricted to **your** IP | The embedded-key handshake handles strangers; the NSG keeps SSH private. Optionally tighten the game port to friends' IPs too during long always-up stretches. |
| Address | Dynamic public IP + **DNS name label** | Deallocating releases the IP, but the label (`yourname-fps.centralus.cloudapp.azure.com`) stays stable — friends keep one hostname forever, no static-IP fee. |
| Safety net | `az vm auto-shutdown` daily at ~4 AM | A forgotten VM costs a night, not a month. |

## Cost picture (pay-as-you-go, mid-2026 rates)

- Playing ~20 h/month: **≈ $0.75 compute + ~$2 disk ≈ $3/month.** Egress at 20 Hz snapshots × 8 players is a few GB — pennies.
- Left running 24/7 by mistake: ~$28/month — hence the auto-shutdown.
- Spot pricing exists but saves ~10 % here for eviction risk mid-firefight; not worth it.

## Server lifecycle (the whole ops story)

```bash
# once: create (portal or az cli), then per session:
az vm start      -g fps-sandbox -n fps-server        # ~1 min to boot
az vm deallocate -g fps-sandbox -n fps-server        # after the session — stops billing
```

The systemd unit keeps it hands-off in between:

```ini
# /etc/systemd/system/fps-server.service
[Unit]
Description=FPS sandbox dedicated server
After=network.target
[Service]
ExecStart=/opt/fps/server.x86_64 --headless -- --server --port 27015
Restart=on-failure
User=fps
[Install]
WantedBy=multi-user.target
```

`systemctl enable` it once → every `az vm start` boots straight into a running server. Crash = auto-restart. Logs: `journalctl -u fps-server -f`.

## Deploy loop

Export `Linux x86_64` dedicated-server preset (strip visuals per 10) → `scp` the binary + pack to `/opt/fps/` → `systemctl restart fps-server`. Three commands; script them as `deploy.sh` when it gets old. The `secrets/auth_key.txt` (10) ships inside the export on both ends — server and clients must be built from the same key or nobody gets in.

## What friends need

The client export, and one hostname: `yourname-fps.centralus.cloudapp.azure.com:27015`. No accounts, no port forwarding on their end (clients dial out). Their embedded key does the authenticating.

## Latency expectations

Central US from a US spread: roughly 20–40 ms Midwest, 40–70 ms coasts — comfortably inside the 100 ms design target, so the M2/M3 netcode gets a *gentler* real-world test than the latency shim provides. Keep using the shim for the hard cases; use Azure sessions to validate feel, not limits.

## Explicitly out of scope (until this stops being a sandbox)

Multi-region, matchmaking/lobbies, containers/ACI or PlayFab (the "real product" paths — revisit if a second concurrent server ever matters), DDoS posture beyond the NSG, TLS/packet encryption, server-side telemetry beyond journald.

## Open questions

- Does the B-series credit model ever throttle a long session? Log server tick duration (p95) each session; one bad reading answers it.
- ARM (`B2pls_v2`) is ~15 % cheaper and Godot exports ARM64 — worth trying once the x86 path is boringly stable, not before.
