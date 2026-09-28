# k3s-Talos Homelab — Roadmap

> **Base URL (cluster API):** `https://192.168.9.99:6443`
> **Kubeconfig:** `kubeconfig` (project root)
> **Cluster VIP:** `192.168.9.99` (kube-vip v1.2.4)

---

## ✅ Current Status (Day 1)

| Component | Status | Details |
|-----------|--------|---------|
| **6 Nodes** | ✅ Running | 3 CP (CP1/CP2/CP3) + 3 workers (W1/W2/W3) |
| **k3s** | ✅ v1.32.2+k3s1 | All nodes Ready |
| **kube-vip** | ✅ v1.2.4 | HA VIP `192.168.9.99:6443` |
| **Traefik** | ⚠️ Pending LB | Image running, but LoadBalancer IP not allocated (MetalLB missing) |
| **CoreDNS** | ✅ Running | DNS resolution |
| **Metrics Server** | ✅ Running | Pod resource metrics |
| **Flannel** | ✅ Running | Pod networking (10.42.0.0/16) |

### Known fixes applied
- kube-vip upgraded from v0.8.9 → v1.2.4 (fixed env-var concatenation bug)
- `vip_address` → `address` (lowercase) + removed `vip_subnet`
- `bootstrap-k3s.sh` patched for future runs

---

## 📋 Prioritized Backlog

### 🔴 P0 — Must have before deploying apps

#### 1. MetalLB (external IPs for services)
Allocates real IPs so Traefik and other LoadBalancers work.

```bash
kubectl apply -f flux/metallb.yaml
# Verify: Traefik should get an external IP (not <pending>)
kubectl -n traefik get svc
```

### 🟡 P1 — Core homelab services

#### 2. Storage (NFS)
Your `flux/nfs-csi.yaml` is ready. NFS gives you persistent, shared storage across nodes.

```bash
kubectl apply -f flux/nfs-csi.yaml
# Verify: storageclass created, can create PVCs
kubectl get storageclass
```

#### 3. Monitoring stack
- **Prometheus** — scrape all pods
- **Grafana** — dashboards
- **Alertmanager** — alerts
- **kube-state-metrics** — node/pod state

```bash
# Option A: Simple single-file deploy
kubectl apply -f https://raw.githubusercontent.com/vektorlab/k3s-install-script/master/manifests/monitoring.yaml

# Option B: Full Prometheus Operator (more flexible)
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundled-manifests/prometheus-operator.yaml
```

### 🟢 P2 — Nice to have

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

## 🏗️ Project Structure

```
k3s-talos-homelab/
├── scripts/
│   └── bootstrap-k3s.sh        # Cluster provisioning (fixed ✅)
├── flux/
│   ├── metallb.yaml            # [P0] External IP allocator
│   ├── nfs-csi.yaml            # [P1] Persistent storage
│   ├── kustomization.yaml      # Flux root
│   └── apps/                   # Your workloads go here
│       ├── example-deployment.yaml
│       └── kustomization.yaml
├── infrastructure/
│   └── terraform/              # Node provisioning (VMs/Proxmox)
├── kubeconfig                  # Saved cluster kubeconfig ✅
└── roadmap.md                  # This file
```

---

## 🔄 Quick reference

```bash
# Cluster status
kubectl --kubeconfig=kubeconfig get nodes -o wide
kubectl --kubeconfig=kubeconfig get pods -A

# Check Traefik (once MetalLB is deployed)
kubectl --kubeconfig=kubeconfig -n traefik get svc

# Check if VIP is alive
nc -z 192.168.9.99 6443 && echo "OK" || echo "FAIL"

# Fix bootstrap script for re-runs
# - kube-vip v1.2.4
# - address (lowercase) instead of vip_address
# - no vip_subnet
```
