# History — Cluster K3s + Talos Linux su Proxmox — 3 CP + 3 Worker (HA)

Data di creazione: 2025-09-20
Ultima modifica: 2025 — 3 CP + 3 Worker HA con NFS CSI + HAProxy + PBS + rete 192.168.9.0/24

## Aggiornamento: da 1 CP + 2 Worker a 3 CP + 3 Worker (HA)

### Motivazione

Il cluster originale era configurato con **1 Control Plane + 2 Worker**. Questo aveva un **singolo punto di fallimento (SPOF)**:

- Se il nodo CP muore → etcd si ferma → API server down → cluster morto

### Nuova Architettura — 3 CP + 3 Worker

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│  Proxmox VE (3 nodi fisici: pve1, pve2, pve3 — 15 GB RAM ciascuno)                   │
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

## Aggiornamento: Ristrutturazione rete (192.168.1.0/24 → 192.168.9.0/24)

### Motivazione

Il cluster era configurato sulla rete `192.168.1.0/24` con indirizzi混乱. Si è scelto di passare a una rete dedicata (`192.168.9.0/24`) con una logica di indirizzamento chiara:

- `192.168.9.1` — `192.168.9.99`: Indirizzi statici riservati
- `192.168.9.100` — `192.168.9.254`: DHCP (device LAN/WiFi)
- `.10` — `.12`: Nodi Control Plane
- `.10`, `.20`, `.30`: Nodi Worker
- `.8`, `.9`: HA VIP + MetalLB (servizi esposti)
- `.200` — `.220`: MetalLB pool (servizi Type:LoadBalancer)

Vedi `docs/network.md` per la documentazione completa della rete.
