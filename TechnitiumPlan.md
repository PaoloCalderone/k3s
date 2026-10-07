# Technitium DNS — Implementation Completed

## Summary

Technitium DNS is now operational in the k3s cluster at **192.168.9.53** and correctly resolves all required domains.

## Architecture

```
Network clients (192.168.9.x)
        ↓ DNS
Technitium DNS (192.168.9.53:53)
        ├── cluster.local → CoreDNS (10.43.0.10)
        ├── *.unifi.localdomain → 192.168.9.200 (Traefik)
        └── External → Google (8.8.8.8) / Cloudflare (1.1.1.1)
```

## Configured DNS Records

| Domain | Type | Result | Notes |
|--------|------|--------|-------|
| `*.cluster.local` | Forwarder → | CoreDNS (10.43.0.10) | Any k3s service |
| `*.unifi.localdomain` | A | 192.168.9.200 | Wildcard for all Unifi services |

## Files Created

| File | Description |
|------|-------------|
| `flux/dns/release.yaml` | Technitium DNS Deployment (ConfigMap, PVC, Services) |
| `flux/dns/kustomization.yaml` | Kustomization for Flux |
| `clusters/homelab/dns.yaml` | Flux Kustomization |
| `flux/metallb-config/pool.yaml` | MetalLB Pool 192.168.9.50-220 |

## Components

### Deployment
- **Container**: `technitium/dns-server:latest`
- **Storage**: PVC 1Gi (local-path) → `/opt/technitium/dns/config`
- **Ports**: 53/TCP, 53/UDP (DNS), 5380 (Web UI)
- **Config**: mounted from ConfigMap at `/bootstrap`

### Bootstrap Script
Runs on startup:
1. Wait 45s for Technitium initialization
2. API login (token with `admin` password)
3. Create `cluster.local` zone as Forwarder → 10.43.0.10
4. Create `unifi.localdomain` zone as Primary
5. Add wildcard record `*.unifi.localdomain` → 192.168.9.200

### Persistence
Zones are stored in the PVC and persist across restarts.

## Testing

### cluster.local (CoreDNS forwarding)
```
$ nslookup kubernetes.default.svc.cluster.local 192.168.9.53
Name: kubernetes.default.svc.cluster.local
Address: 10.43.0.1
```

### google.com (external DNS)
```
$ nslookup google.com 192.168.9.53
Non-authoritative answer:
Name: google.com
Address: 192.178.194.100
```

### grafana.unifi.localdomain (wildcard)
```
$ nslookup grafana.unifi.localdomain 192.168.9.53
Name: grafana.unifi.localdomain
Address: 192.168.9.200
```

### prometheus.unifi.localdomain (wildcard)
```
$ nslookup prometheus.unifi.localdomain 192.168.9.53
Name: prometheus.unifi.localdomain
Address: 192.168.9.200
```

### homepage.unifi.localdomain (wildcard)
```
$ nslookup homepage.unifi.localdomain 192.168.9.53
Name: homepage.unifi.localdomain
Address: 192.168.9.200
```

## Next Steps (Required Actions)

### 1. Configure DHCP on UDM Pro router
Access UniFi Controller → Settings → Network → LAN → DHCP
- Set **DNS Server 1** = `192.168.9.53`
- Reboot clients to obtain the new DNS

### 2. Web UI (optional)
Access: `http://<node-ip>:5380`
- Username: `admin`
- Password: `admin`
- Use to add/modify DNS zones via web interface

### 3. End-to-end verification
After configuring the router:
```bash
# From any network client
nslookup grafana.unifi.localdomain
nslookup kubernetes.default.svc.cluster.local
dig @192.168.9.53 prometheus.unifi.localdomain
```

## Troubleshooting

### DNS does not resolve
1. Verify Technitium pod: `kubectl get pods -n dns`
2. Verify zones: `kubectl exec -n dns deployment/technitium-dns -- curl http://localhost:5380/api/zones/list`
3. Restart: `kubectl rollout restart deployment/technitium-dns -n dns`

### PVC does not persist
- Verify PVC bound: `kubectl get pvc -n dns`
- Verify node affinity: `kubectl get pvc technitium-dns-config -n dns -o yaml | grep selected-node`

## Session Log

### Final Session
- **Date**: 2026-10-05
- **Status**: COMPLETED
- **Modified files**:
  - `flux/dns/release.yaml` — Complete deployment with bootstrap and persistence
  - `flux/dns/kustomization.yaml` — Corrected Flux Kustomization
  - `clusters/homelab/dns.yaml` — Flux Kustomization
- **Note**: The PVC must be mounted at `/opt/technitium/dns/config` (not `/etc/dns`) to ensure zone persistence
