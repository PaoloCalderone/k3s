# 📋 Change Summary — From 1 CP + 2 Workers to 3 CP + 3 Workers (HA)

## Summary of Changes

### Architecture

| Aspect | Before | After |
|--------|--------|-------|
| Control Plane Nodes | 1 | **3 (HA)** |
| Worker Nodes | 2 | **3** |
| Total K8s VMs | 3 | **6** |
| Total Proxmox VMs | 3 | **7** (6 K8s + 1 HAProxy) |
| Control Plane Endpoint | 192.168.1.100:6443 (single node) | **192.168.1.99:6443 (VIP)** |
| Load Balancer | none | **HAProxy (dedicated VM)** |
| Storage | Longhorn (local, replicated across K8s nodes) | **NFS CSI (TrueNAS, data on NAS)** |
| Backup | Longhorn backup (internal) | **Proxmox Backup Server (PBS, hypervisor)** |

---

## Modified Files

### Infrastructure Terraform (5 files)

| File | Description |
|------|-------------|
| `infrastructure/terraform/main.tf` | **Completely rewritten**: now creates 6 K8s VMs + 1 HAProxy (7 VMs total) |
| `infrastructure/terraform/variables.tf` | **Completely rewritten**: variables for 3 CP + 3 Workers + NFS TrueNAS + HA VIP |
| `infrastructure/terraform/outputs.tf` | **Completely rewritten**: output for 6 nodes + VIP + TrueNAS |
| `infrastructure/terraform/terraform.tfvars.example` | **Completely rewritten**: template with 3+3 config |

### Talos Machine Config (6 files)

| File | Role |
|------|------|
| `infrastructure/talos/cluster-config.yaml` | **Modified**: cluster with 3 CP, HA VIP, NFS storage notes |
| `infrastructure/talos/node1-controlplane.yaml` | **Modified**: CP-1 with additionalEtcdHosts + additionalKubeAPIHosts |
| `infrastructure/talos/node2-controlplane.yaml` | **New**: CP-2 with additionalEtcdHosts + additionalKubeAPIHosts |
| `infrastructure/talos/node3-controlplane.yaml` | **New**: CP-3 with additionalEtcdHosts + additionalKubeAPIHosts |
| `infrastructure/talos/node2-worker.yaml` | **Modified**: Worker 1 with HA VIP |
| `infrastructure/talos/node3-worker.yaml` | **Modified**: Worker 2 with HA VIP |
| `infrastructure/talos/node4-worker.yaml` | **New**: Worker 3 with HA VIP |

### Flux / GitOps (4 files)

| File | Description |
|------|-------------|
| `flux/kustomization.yaml` | **Modified**: replaces `longhorn.yaml` with `nfs-csi.yaml` |
| `flux/nfs-csi.yaml` | **New**: NFS CSI from TrueNAS (storage class true-nas-nfs + proxmox-local) |
| `flux/metallb.yaml` | **Modified**: kept, for LoadBalancer external services |
| `flux/coredns-patch.yaml` | **Modified**: 2 CoreDNS replicas for HA |
| `flux/apps/example-deployment.yaml` | **Modified**: uses true-nas-nfs storage class (PVC) |

### Scripts (1 file)

| File | Description |
|------|-------------|
| `scripts/bootstrap-talos.sh` | **Completely rewritten**: bootstrap 6 nodes via VIP |

### Documentation (3 files)

| File | Description |
|------|-------------|
| `README.md` | **Completely rewritten**: 3+3 HA diagrams, storage/backup explanations |
| `docs/01-step-by-step-guide.md` | **Completely rewritten**: guide with 3 CP + 3 Worker + HAProxy + PBS |
| `docs/02-migration-summary.md` | **New**: this file |
| `history.md` | **Completely rewritten**: tracking changes from 1+2 to 3+3 |

### Renovate (3 files)

| File | Description |
|------|-------------|
| `renovate.json5` | **Modified**: added NFS CSI rule |
| `infrastructure/renovate/renovate.json5` | **Modified**: added NFS CSI rule |
| `infrastructure/renovate/fluxbot-rules.json5` | **Modified**: added nfs-csi-upgrade rule |

---

## New Structures

### Storage Classes

| Storage Class | Provisioner | Use |
|---------------|-------------|-----|
| `true-nas-nfs` | nfs.csi.k8s.io | Persistent data on TrueNAS (RWX) |
| `proxmox-local` | local-path-provisioner | Temporary data on local disk (RWO) |

### Node IPs

| Node | IP | Role |
|------|----|------|
| k8s-cp1 | 192.168.1.100 | Control Plane 1 (etcd + API) |
| k8s-cp2 | 192.168.1.101 | Control Plane 2 (etcd + API) |
| k8s-cp3 | 192.168.1.102 | Control Plane 3 (etcd + API) |
| k8s-w1 | 192.168.1.110 | Worker 1 |
| k8s-w2 | 192.168.1.111 | Worker 2 |
| k8s-w3 | 192.168.1.112 | Worker 3 |
| haproxy-lb (VIP) | 192.168.1.99 | Load Balancer (K8s API) |
| TrueNAS | 192.168.1.50 | NAS (NFS v4.2) |

---

## What DID NOT Change

| Element | Status |
|---------|--------|
| MetalLB (LoadBalancer services) | Remains, to expose external K8s services |
| CoreDNS (patch) | Remains, 2 HA replicas |
| Flux CD (bootstrap) | Remains, Flux bootstrap GitHub |
| Renovate (updates) | Remains, automatic PRs |
| Fluxbot (schema updates) | Remains, monitors schemas |
| Proxmox Infrastructure | Remains, 3 physical nodes, same stack |
| Talos Linux (OS) | Remains, immutable OS |
| K3s (orchestrator) | Remains, lightweight Kubernetes |

---

## Important Notes

### 1. HAProxy VIP
The IP `192.168.1.99` must be:
- **FREE** on your network (not assigned by DHCP)
- **Reachable** from all cluster nodes
- **Backward-compatible** (if you change it, update all files)

### 2. TrueNAS NFS
The TrueNAS server must:
- Have **exported** an NFS share (e.g., `/mnt/pool/kubernetes`)
- Have **NFS v4.2 access** enabled
- Be **reachable** from all cluster nodes (2.5 GbE network)

### 3. Proxmox Backup Server (PBS)
The PBS must:
- Be **installed** (dedicated server or VM on Proxmox)
- Have a **repository** created for cluster VM backups
- Be configured with a **backup schedule** (optional but recommended)

### 4. PBS backup vs NFS data
Cluster data lives on TrueNAS (NFS), VM backup is handled by PBS.
These are two **independent** systems:
- If you lose the K8s cluster → you can recreate it and data is on TrueNAS
- If you lose TrueNAS → you can restore VMs from PBS (but PVC data is lost)
- **Recommended plan:** also backup TrueNAS (exports, pool snapshots)
