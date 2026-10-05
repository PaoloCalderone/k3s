# 📋 Riepilogo Modifiche — Da 1 CP + 2 Worker a 3 CP + 3 Worker (HA)

## Riassunto delle modifiche

### Architettura

| Aspect | Prima | Dopo |
|--------|-------|------|
| Nodi Control Plane | 1 | **3 (HA)** |
| Nodi Worker | 2 | **3** |
| Total VM K8s | 3 | **6** |
| Total VM Proxmox | 3 | **7** (6 K8s + 1 HAProxy) |
| Control Plane Endpoint | 192.168.1.100:6443 (singolo nodo) | **192.168.1.99:6443 (VIP)** |
| Load Balancer | nessuno | **HAProxy (VM dedicata)** |
| Storage | Longhorn (locale, replica tra nodi K8s) | **NFS CSI (TrueNAS, dati su NAS)** |
| Backup | Longhorn backup (interno) | **Proxmox Backup Server (PBS, hypervisor)** |

---

## File modificati

### Infrastructure Terraform (5 file)

| File | Descrizione |
|------|-------------|
| `infrastructure/terraform/main.tf` | **Completamente riscritto**: ora crea 6 VM K8s + 1 HAProxy (7 VM totali) |
| `infrastructure/terraform/variables.tf` | **Completamente riscritto**: variables per 3 CP + 3 Worker + NFS TrueNAS + HA VIP |
| `infrastructure/terraform/outputs.tf` | **Completamente riscritto**: output per 6 nodi + VIP + TrueNAS |
| `infrastructure/terraform/terraform.tfvars.example` | **Completamente riscritto**: template con 3+3 config |

### Talos Machine Config (6 file)

| File | Ruolo |
|------|-------|
| `infrastructure/talos/cluster-config.yaml` | **Modificato**: cluster con 3 CP, HA VIP, storage NFS note |
| `infrastructure/talos/node1-controlplane.yaml` | **Modificato**: CP-1 con additionalEtcdHosts + additionalKubeAPIHosts |
| `infrastructure/talos/node2-controlplane.yaml` | **Nuovo**: CP-2 con additionalEtcdHosts + additionalKubeAPIHosts |
| `infrastructure/talos/node3-controlplane.yaml` | **Nuovo**: CP-3 con additionalEtcdHosts + additionalKubeAPIHosts |
| `infrastructure/talos/node2-worker.yaml` | **Modificato**: Worker 1 con HA VIP |
| `infrastructure/talos/node3-worker.yaml` | **Modificato**: Worker 2 con HA VIP |
| `infrastructure/talos/node4-worker.yaml` | **Nuovo**: Worker 3 con HA VIP |

### Flux / GitOps (4 file)

| File | Descrizione |
|------|-------------|
| `flux/kustomization.yaml` | **Modificato**: sostituisce `longhorn.yaml` con `nfs-csi.yaml` |
| `flux/nfs-csi.yaml` | **Nuovo**: NFS CSI dal TrueNAS (storage class true-nas-nfs + proxmox-local) |
| `flux/metallb.yaml` | **Modificato**: keep, per LoadBalancer servizi esterni |
| `flux/coredns-patch.yaml` | **Modificato**: 2 repliche CoreDNS per HA |
| `flux/apps/example-deployment.yaml` | **Modificato**: usa storage class true-nas-nfs (PVC) |

### Scripts (1 file)

| File | Descrizione |
|------|-------------|
| `scripts/bootstrap-talos.sh` | **Completamente riscritto**: bootstrap 6 nodi tramite VIP |

### Documentazione (3 file)

| File | Descrizione |
|------|-------------|
| `README.md` | **Completamente riscritto**: diagrami 3+3 HA, spiegazioni storage/backup |
| `docs/01-step-by-step-guide.md` | **Completamente riscritto**: guida con 3 CP + 3 Worker + HAProxy + PBS |
| `docs/02-migration-summary.md` | **Nuovo**: questo file |
| `history.md` | **Completamente riscritto**: tracciamento modifiche da 1+2 a 3+3 |

### Renovate (3 file)

| File | Descrizione |
|------|-------------|
| `renovate.json5` | **Modificato**: aggiunta regola NFS CSI |
| `infrastructure/renovate/renovate.json5` | **Modificato**: aggiunta regola NFS CSI |
| `infrastructure/renovate/fluxbot-rules.json5` | **Modificato**: aggiunta regola nfs-csi-upgrade |

---

## Nuove strutture

### Storage Classes

| Storage Class | Provisioner | Uso |
|---------------|-------------|-----|
| `true-nas-nfs` | nfs.csi.k8s.io | Dati persistenti su TrueNAS (RWX) |
| `proxmox-local` | local-path-provisioner | Dati temporanei su disco locale (RWO) |

### Node IPs

| Nodo | IP | Ruolo |
|------|----|-------|
| k8s-cp1 | 192.168.1.100 | Control Plane 1 (etcd + API) |
| k8s-cp2 | 192.168.1.101 | Control Plane 2 (etcd + API) |
| k8s-cp3 | 192.168.1.102 | Control Plane 3 (etcd + API) |
| k8s-w1 | 192.168.1.110 | Worker 1 |
| k8s-w2 | 192.168.1.111 | Worker 2 |
| k8s-w3 | 192.168.1.112 | Worker 3 |
| haproxy-lb (VIP) | 192.168.1.99 | Load Balancer (API K8s) |
| TrueNAS | 192.168.1.50 | NAS (NFS v4.2) |

---

## Cosa NON è cambiato

| Elemento | Stato |
|----------|-------|
| MetalLB (LoadBalancer servizi) | Rimane, per esporre servizi K8S esterni |
| CoreDNS (patch) | Rimane, 2 repliche HA |
| Flux CD (bootstrap) | Rimane, Flux bootstrap GitHub |
| Renovate (aggiornamenti) | Rimane, PR automatiche |
| Fluxbot (schema updates) | Rimane, monitora schemi |
| Proxmox Infrastructure | Rimane, 3 nodi fisici, stack uguale |
| Talos Linux (OS) | Rimane, immutable OS |
| K3s (orchestrator) | Rimane, lightweight Kubernetes |

---

## Note importanti

### 1. HAProxy VIP
L'IP `192.168.1.99` deve essere:
- **LIBERO** nella tua rete (non assegnato da DHCP)
- **Raggiungibile** da tutti i nodi del cluster
- **Retrocompatibile** (se cambi, aggiorna tutti i file)

### 2. TrueNAS NFS
Il server TrueNAS deve:
- Avere **esportato** un share NFS (es. `/mnt/pool/kubernetes`)
- Avere **accessi NFS v4.2** abilitati
- Essere **raggiungibile** da tutti i nodi del cluster (rete 2.5 GbE)

### 3. Proxmox Backup Server (PBS)
Il PBS deve:
- Essere **installato** (server dedicato o VM su Proxmox)
- Avere un **repository** creato per i backup delle VM del cluster
- Essere configurato con una **schedule di backup** (opzionale ma consigliato)

### 4. backup PBS vs dati NFS
I dati del cluster vivono sul TrueNAS (NFS), il backup delle VM è gestito da PBS.
Sono due sistemi **indipendenti**:
- Se perdi il cluster K8s → puoi ricrearlo e i dati sono sul TrueNAS
- Se perdi il TrueNAS → puoi restore le VM dal PBS (ma i dati PVC sono persi)
- **Piano consigliato:** backup anche del TrueNAS (export, snapshot del pool)
