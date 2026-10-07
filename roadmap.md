# K3s HA Homelab — Roadmap

> **Base URL (cluster API):** `https://192.168.9.99:6443`
> **Kubeconfig:** `kubeconfig` (project root)
> **Cluster VIP:** `192.168.9.99` (kube-vip v1.2.4)

---

## Current Status (Day 1)

| Component | Status | Details |
|-----------|--------|---------|
| **6 Nodes** | Running | 3 CP (CP1/CP2/CP3) + 3 workers (W1/W2/W3) |
| **k3s** | v1.32.2+k3s1 | All nodes Ready |
| **kube-vip** | v1.2.4 | HA VIP `192.168.9.99:6443` |
| **Traefik** | LoadBalancer | External IP `192.168.9.200` via MetalLB |
| **CoreDNS** | Running | DNS resolution |
| **Metrics Server** | Running | Pod resource metrics |
| **NFS CSI** | Working | PVC bound, pod mounted, read/write verified on `192.168.9.9:/mnt/main/kubernetes` |
| **Flannel** | Running | Pod networking (10.42.0.0/16) |
| **Flux** | v2.7.5 | GitOps bootstrap, 5 Kustomizations + 2 HelmReleases all Ready |

### Known fixes applied
- kube-vip upgraded from v0.8.9 → v1.2.4 (fixed env-var concatenation bug)
- `vip_address` → `address` (lowercase) + removed `vip_subnet`
- `bootstrap-k3s.sh` patched for future runs
- Flux v2.7.5 bootstrapped for K3s 1.32; MetalLB and NFS reconciled in CRD-safe order
- `192.168.9.200-220` confirmed excluded from DHCP

---

## Prioritized Backlog

### P0 — Completed

#### 1. MetalLB (external IPs for services)
Flux manages `flux/metallb/` (HelmRepository + HelmRelease) then `flux/metallb-config/` (IP pool + L2 advertisement). Traefik receives `192.168.9.200`.

```bash
kubectl --kubeconfig=kubeconfig -n kube-system get svc traefik
```

### P1 — Core homelab services

#### 2. Storage (NFS) — Working
Flux manages `flux/nfs-driver/` (CSI HelmRelease) and `flux/nfs-config/` (StorageClass). Writes verified: test PVC bound, pod mounted, file read/write successful on `192.168.9.9:/mnt/main/kubernetes`.

```bash
kubectl --kubeconfig=kubeconfig get storageclass
# Deploy a PVC with storageClassName: nfs-csi to use persistent shared storage.
```

#### 3. Monitoring stack — Working (2026-09-29)
- **Prometheus** — scrape all pods (10GB on nfs-csi, 14d retention)
- **Grafana** — dashboards (LoadBalancer `192.168.9.210:3000`, admin/homelab)
- **Alertmanager** — alerts (on nfs-csi, 2GB)
- **kube-state-metrics** — node/pod state
- **node-exporter** — per-node metrics (running on all 6 nodes)
- **Prometheus operator** — manages CRDs

```bash
# Grafana: http://192.168.9.210:3000 (admin / homelab)
# Prometheus: kubectl port-forward svc/monitoring-monitoring-kube-prometheus 9090 -n monitoring
# Alertmanager: kubectl port-forward svc/monitoring-monitoring-kube-alertmanager 9093 -n monitoring
```

### P2 — Nice to have

#### 4. HTTPS (certificates)
Auto-sign TLS certs for your services.

```bash
# cert-manager + cert-issuer (Let's Encrypt or internal CA)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
```

#### 5. Ingress controller hardening
- Custom Traefik middleware (rate limiting, auth)
- Basic auth on admin interfaces
- Redirect HTTP → HTTPS

#### 6. Backups
- etcd snapshots (control-plane nodes)
- Persistent volume backups (if using NFS)

```bash
# etcd backup script (run via cron on CP1)
sudo k3s kubectl -n kube-system exec -it $(sudo k3s kubectl -n kube-system get pods -l component=etcd -o name | head -1) -- \
  etcdctl snapshot save /backup/etcd-snapshot-$(date +%Y%m%d).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/ssl/etcd/ca.crt \
  --cert=/etc/kubernetes/ssl/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/ssl/etcd/healthcheck-client.key
```

---

## Project Structure

```
k3s/
├── clusters/homelab/           # Flux bootstrap and ordered reconciliations
├── flux/
│   ├── metallb/                # HelmRepository + HelmRelease
│   ├── metallb-config/         # IP pool and L2 advertisement
│   ├── nfs-driver/             # HelmRepository + HelmRelease
│   ├── nfs-config/             # Non-default nfs-csi StorageClass
│   └── apps/                   # Example app (not reconciled)
├── scripts/bootstrap-k3s.sh
├── infrastructure/terraform/
├── kubeconfig                  # Local, ignored by Git
└── roadmap.md
```

---

## Quick reference

```bash
# Cluster status
kubectl --kubeconfig=kubeconfig get nodes -o wide
kubectl --kubeconfig=kubeconfig get pods -A

# Traefik runs in kube-system
kubectl --kubeconfig=kubeconfig -n kube-system get svc traefik

# Flux reconciliation status
flux get kustomizations --kubeconfig=kubeconfig
flux get helmreleases --kubeconfig=kubeconfig

# Check if VIP is alive
nc -z 192.168.9.99 6443 && echo "OK" || echo "FAIL"
```
