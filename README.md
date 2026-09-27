# K3s + Talos Linux su Proxmox — Cluster GitOps HA (Rete: 192.168.9.0/24)

Cluster Kubernetes ad **alta disponibilità** gestito interamente da codice. Zero interventi manuali.

## 📋 Panoramica Stack

| Layer | Tecnologia | Ruolo |
|-------|------------|-------|
| Hypervisor | Proxmox VE | 3 nodi fisici (pve1, pve2, pve3), 15 GB RAM ciascuno |
| OS | Talos Linux | Sistema operativo immutable per Kubernetes |
| Orchestrator | K3s | Kubernetes leggero (single binary) |
| HA Load Balancer | HAProxy (VM dedicata) | VIP (192.168.9.8) bilancia verso 3 CP |
| Storage | TrueNAS (NFS v4.2) | Storage persistente via NFS CSI |
| Backup | Proxmox Backup Server (PBS) | Backup a livello hypervisor (VM-level) |
| Infra IaC | Terraform + OpenTofu | Provisioning VM su Proxmox |
| Bootstrap | talosctl | Creazione e bootstrap cluster |
| GitOps | Flux CD | Deploy automatico applicazioni dal repo |
| Versioning | Renovate | Aggiornamenti automatici via PR |
| **Network** | **192.168.9.0/24** | **VLAN dedicata del cluster** |

## 🏗️ Architettura del Cluster

### Mappatura Nodi Proxmox → VM Kubernetes (6 VM + 1 LB)

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                         Proxmox VE (3 nodi fisici: pve1, pve2, pve3)                  │
│                                                                                      │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐                          │
│  │  Nodo pve1     │  │  Nodo pve2     │  │  Nodo pve3     │                          │
│  │  (15 GB RAM)   │  │  (15 GB RAM)   │  │  (15 GB RAM)   │                          │
│  │                │  │                │  │                │                          │
│  │ k8s-cp-1       │  │ k8s-cp-2       │  │ k8s-cp-3       │  ← Control Plane (3)     │
│  │ (4 GB RAM)     │  │ (4 GB RAM)     │  │ (4 GB RAM)     │  3 nodi etcd cluster     │
│  │ 192.168.9.10   │  │ 192.168.9.11   │  │ 192.168.9.12   │                          │
│  │                │  │                │  │                │                          │
│  │ k8s-w1         │  │ k8s-w2         │  │ k8s-w3         │  ← Worker (3)           │
│  │ (4 GB RAM)     │  │ (4 GB RAM)     │  │ (4 GB RAM)     │  3 nodi workload         │
│  │ 192.168.9.10*  │  │ 192.168.9.20   │  │ 192.168.9.30   │                          │
│  └────────────────┘  └────────────────┘  └────────────────┘                          │
│                                                                                      │
│  ┌────────────────┐                                                                  │
│  │ haproxy-lb     │  ← Load Balancer (VIP)                                           │
│  │ (1 GB RAM)     │  192.168.9.8:6443 (Kubernetes API)                               │
│  │                │  192.168.9.9 (Traefik HTTP/S)                                    │
│  │                │  Bilancia verso CP-1 + CP-2 + CP-3                               │
│  └────────────────┘                                                                  │
│                                                                                      │
│  ┌────────────────┐                                                                  │
│  │ TrueNAS        │  ← NAS Esterno (Storage)                                         │
│  │ (NFS Server)   │  192.168.9.50 — NFS v4.2                                         │
│  │ 10 GbE NIC     │  Connection → K8s via 2.5 GbE NICs                               │
│  └────────────────┘                                                                  │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

### Diagramma della Flusso Dati

```
│  GitHub Repository (monorepo)                           │
│  │ Terraform  │  │  Flux CD │  │  Renovate / bot  │    │
│  └─────┬──────┘  └────┬─────┘  └────────┬─────────┘    │
│        │               │                  │              │
│        ▼               ▼                  ▼              │
│  │  Proxmox VE (3 nodi fisici: pve1, pve2, pve3)   │    │
│  │  │ k8s-cp-1 │ │ k8s-cp-2 │ │ k8s-cp-3 │          │    │
│  │  │ Talos/K3s│ │Talos/K3s │ │Talos/K3s │           │    │
│  │  │ CP node  │ │ CP node  │ │ CP node  │           │    │
│  │  │ etcd     │ │ etcd     │ │ etcd     │  3-nodes  │    │
│  └──┬──────────┴─┬─────────┴─┬──────────┴───────────┘    │
│     │             │            │                          │
│  ┌──▼──────────┐  │         ┌──▼──────────┐              │
│  │ haproxy-lb  │  │         │ TrueNAS      │              │
│  │ (VIP LB)    │  │         │ (NFS Server) │              │
│  │ 192.168.9.8 │  │         │ NFS v4.2     │              │
│  └─────┬───────┘  │         └──────┬──────┘              │
│        │          │                │                     │
│  ┌─────▼──────────▼────────────────▼─────────────────┐  │
│  │              Kubernetes API Server                 │  │
│  │          (etcd cluster: 3 repliche HA)             │  │
│  └─────┬──────────┬────────────────┬────────────────┘  │
│        │          │                │                    │
│  ┌─────▼─────┐  ┌─▼────────┐  ┌──▼────────┐          │
│  │ k8s-w1    │  │k8s-w2    │  │ k8s-w3    │          │
│  │ (Worker)  │  │(Worker)  │  │(Worker)   │          │
│  └───────────┘  └──────────┘  └──────────┘          │
│                                                      │
│  Storage Layer:                                      │
│  ├── NFS CSI → TrueNAS (/mnt/pool/kubernetes)          │
│  ├── Proxmox Local → disco locale delle VM            │
│  └── Backup → Proxmox Backup Server (PBS)             │
└────────────────────────────────────────────────────────┘
```

## 📁 Struttura del Progetto

```
k3s/
├── README.md                              # Questo file
├── docs/                                  # Documentazione completa
│   ├── network.md                         # Documentazione di rete (nuovo!)
│   └── 01-step-by-step-guide.md          # Guida passo-passo completa
├── infrastructure/                        # Infrastruttura come Codice
│   ├── terraform/                         # Terraform per Proxmox VMs
│   │   ├── main.tf                       # Creazione 6 VM K3s + HAProxy (HA)
│   │   ├── variables.tf                  # Variabili configurabili (3+3)
│   │   ├── outputs.tf                    # Output (kubeconfig, token)
│   │   ├── providers.tf                  # Provider Proxmox + Talos
│   │   └── terraform.tfvars.example      # Template variabili da copiare
│   ├── talos/                             # Configurazione Talos per ogni nodo
│   │   ├── cluster-config.yaml           # Config Talos cluster (HA)
│   │   ├── node1-controlplane.yaml       # Machine config nodo CP-1 — pve1
│   │   ├── node2-controlplane.yaml       # Machine config nodo CP-2 — pve2
│   │   ├── node3-controlplane.yaml       # Machine config nodo CP-3 — pve3
│   │   ├── node2-worker.yaml             # Machine config Worker 1 — pve1
│   │   ├── node3-worker.yaml             # Machine config Worker 2 — pve2
│   │   └── node4-worker.yaml             # Machine config Worker 3 — pve3
│   └── renovate/                          # Config Renovate
│       ├── renovate.json5                # Regole di aggiornamento
│       └── fluxbot-rules.json5           # Regole Fluxbot schematics
├── flux/                                  # GitOps — Applicazioni
│   ├── kustomization.yaml                # Flux Kustomization root
│   ├── app-repository.yaml               # Flux Repository verso GitHub
│   ├── app-application.yaml              # Flux Application per apps
│   ├── nfs-csi.yaml                       # Storage NFS (TrueNAS)
│   ├── metallb.yaml                       # LoadBalancer (servizi esterni)
│   ├── coredns-patch.yaml                # Patch CoreDNS
│   └── apps/                              # Applicazioni
│       └── example-deployment.yaml        # Deployment di esempio (nginx)
└── scripts/                               # Utility script
    └── bootstrap-talos.sh                # Bootstrap automatico (6 nodi)
```

## 🚀 Quick Start

### Prerequisiti
1. Proxmox VE installato e operativo (3 nodi: pve1, pve2, pve3)
2. Account API Proxmox con privilegi (VM.Allocate, VM.Clone, VM.Config.CDROM, VM.Config.Cloudinit, VM.Config.Hardware, VM.Config.Network, VM.Monitor, VM.Read, AAAA.User.Admin)
3. `terraform` o `opentofu` installato (>= 1.7)
4. `talosctl` installato (versione allineata al K8s del cluster)
5. `kubectl` installato
6. `flux` CLI installato
7. Un repository GitHub privato/pubblico per il monorepo

### Primi Passi (una tantum)

Vedi `docs/01-step-by-step-guide.md` per la guida completa.

```bash
# 1. Clone del repo
git clone <tuo-repo>
cd k3s

# 2. Setup variabili Terraform
cp infrastructure/terraform/terraform.tfvars.example infrastructure/terraform/terraform.tfvars
# Modifica terraform.tfvars con i tuoi dati Proxmox

# 3. Provisioning cluster (6 VM + HAProxy)
cd infrastructure/terraform
terraform init
terraform plan
terraform apply

# 4. Bootstrap K3s (usa VIP, non un singolo nodo!)
cd ../../scripts/
./bootstrap-talos.sh

# 5. Installa Flux sul cluster
flux bootstrap github \
  --owner=<username> \
  --repository=<repo> \
  --branch=main \
  --path=./flux

# 6. Abilita Renovate (in repository settings)
```

## 📡 Riferimenti di Rete (nuovo schema 192.168.9.0/24)

| Indirizzo | Ruolo | Note |
|-----------|-------|------|
| `192.168.9.1` | Gateway / Router | Switch/router della rete fisica |
| `192.168.9.2` | DNS interno (CoreDNS) | Risolto da `/etc/resolv.conf` |
| `192.168.9.8` | HA VIP (Load Balancer) | Kubernetes API endpoint: `:6443` |
| `192.168.9.9` | MetalLB (servizio principale) | Traefik HTTP/S default |
| `192.168.9.10` | k8s-cp-1 | Control Plane 1 |
| `192.168.9.11` | k8s-cp-2 | Control Plane 2 |
| `192.168.9.12` | k8s-cp-3 | Control Plane 3 |
| `192.168.9.10` | k8s-w1 | Worker 1 |
| `192.168.9.20` | k8s-w2 | Worker 2 |
| `192.168.9.30` | k8s-w3 | Worker 3 |
| `192.168.9.50` | TrueNAS (NFS Server) | Storage persistente |
| `192.168.9.99` | Monitoraggio | Prometheus/Grafana |
| `192.168.9.200-220` | MetalLB pool | Servizi Type:LoadBalancer |
| `192.168.9.100-254` | DHCP range | Client LAN/WiFi/IoT |

Vedi `docs/network.md` per la documentazione completa della rete.

## 🔧 Decisioni Architetturali

### Perché 3 CP + 3 Worker (HA)?

| # Control Plane | HA? | Rischio |
|----------------|-----|---------|
| 1 | ❌ No (SPOF) | Unica macchina che tiene il cluster |
| **3** | ✅ **Sì** | **Resiste a 1 nodo down** (quorum 2/3) |
| 5 | ⚠️ Overkill | Stesso quorum di 3, doppio costo |

**3 CP garantiscono:**
- **Quorum etcd:** 3 nodi, quorum di 2 → 1 nodo down = cluster ancora operativo
- **API Server HA:** un nodo down → gli altri gestiscono le richieste
- **VIP Load Balancer:** HAProxy indirizza solo ai nodi UP

### Perché HAProxy come Load Balancer?

- **Externalità al cluster:** se il cluster K8s cade, HAProxy (in una VM separata su Proxmox) continua a funzionare
- **Zero SPOF:** 3 nodi CP + VIP → nessun nodo singolo può far cadere tutto
- **VM dedicabile a Proxmox:** può anche gestire servizi fuori dal cluster

### Perché TrueNAS (NFS) invece di Longhorn?

| Storage | HA? | Backup | Flexibilità |
|---------|-----|--------|-------------|
| **NFS CSI (TrueNAS)** | ✅ Se NAS è HA | ✅ PBS a livello hypervisor | RWX, backup esterno |
| Longhorn | ⚠️ Parziale (3 repliche locali) | ❌ Nessuno (dipende dai nodi K8s) | Solo su dischi locali |

**Con NFS dal TrueNAS:**
- I dati vivono sul NAS, non sui dischi locali delle VM
- Proxmox Backup Server (PBS) fa backup a livello hypervisor (ogni VM è un backup)
- Il cluster K8s può essere ricreato senza perdere dati
- Performance su rete 10 GbE dal NAS → 2.5 GbE ai nodi

### Backup con Proxmox Backup Server (PBS)

```
┌─────────────────────────────────────────────────────────┐
│  Proxmox Backup Server (esterno)                        │
│  ─────────────────────────────────────────────────────  │
│  Backup a livello hypervisor (non dentro K8s):           │
│  • Snapshot VM K8s (ogni VM: CP + Worker)               │
│  • Schedule automatizzata (cron)                        │
│  • Retention policy (7 giorni, 4 settimane, 3 mesi)      │
│  • Restore point-in-time per ogni VM                   │
└─────────────────────────────────────────────────────────┘
```

**Perché PBS invece di backup interno a K8s:**
- Non consuma risorse del cluster (backup a livello hypervisor)
- Ogni VM è un backup completo (snapshots)
- Non dipende dallo stato del cluster K8s
- Restore di una singola VM senza toccare il cluster

## 📚 Riferimenti

- [Talos Linux Docs](https://www.talos.dev/)
- [Talos on Proxmox](https://www.talos.dev/docs/v1.9/platform-specific-installations/virtualized-platforms/proxmox)
- [Talos Terraform Provider](https://registry.terraform.io/providers/siderolabs/talos/latest)
- [Proxmox Terraform Provider](https://registry.terraform.io/providers/bpg/proxmox/latest)
- [K3s Docs](https://docs.k3s.io/)
- [Flux CD](https://fluxcd.io/)
- [Renovate](https://docs.renovatebot.com/)
- [NFS CSI Driver](https://github.com/kubernetes-csi/csi-driver-nfs)
- [MetalLB](https://metallb.io/)
- [Proxmox Backup Server](https://www.proxmox.com/en/proxmox-backup-server)
- [docs/network.md](docs/network.md) — Documentazione completa della rete
