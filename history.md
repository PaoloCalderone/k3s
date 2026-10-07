# History — K3s Cluster + Talos Linux on Proxmox — 3 CP + 3 Worker (HA)

Creation date: 2025-09-20
Last modified: 2025 — 3 CP + 3 Worker HA with NFS CSI + HAProxy + PBS + 192.168.9.0/24 network

## Update: from 1 CP + 2 Workers to 3 CP + 3 Workers (HA)

### Motivation

The original cluster was configured with **1 Control Plane + 2 Workers**. This had a **single point of failure (SPOF)**:

- If the CP node goes down → etcd stops → API server down → cluster is dead

### New Architecture — 3 CP + 3 Workers

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│  Proxmox VE (3 physical nodes: pve1, pve2, pve3 — 15 GB RAM each)                   │
│                                                                                      │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐                          │
│  │  Node pve1     │  │  Node pve2     │  │  Node pve3     │                          │
│  │  (15 GB RAM)   │  │  (15 GB RAM)   │  │  (15 GB RAM)   │                          │
│  │                │  │                │  │                │                          │
│  │ k8s-cp1       │  │ k8s-cp2       │  │ k8s-cp3       │  ← Control Plane (3)     │
│  │ (4 GB RAM)     │  │ (4 GB RAM)     │  │ (4 GB RAM)     │  3-node etcd cluster     │
│  │ 192.168.9.10   │  │ 192.168.9.11   │  │ 192.168.9.12   │                          │
│  │                │  │                │  │                │                          │
│  │ k8s-w1         │  │ k8s-w2         │  │ k8s-w3         │  ← Worker (3)           │
│  │ (4 GB RAM)     │  │ (4 GB RAM)     │  │ (4 GB RAM)     │  3 workload nodes        │
│  │ 192.168.9.10*  │  │ 192.168.9.20   │  │ 192.168.9.30   │                          │
│  └────────────────┘  └────────────────┘  └────────────────┘                          │
│                                                                                      │
│  ┌────────────────┐                                                                  │
│  │ haproxy-lb     │  ← Load Balancer (VIP)                                           │
│  │ (1 GB RAM)     │  192.168.9.99:6443 (Kubernetes API)                               │
│  │                │  192.168.9.9 (Traefik HTTP/S)                                    │
│  │                │  Load balances across CP-1 + CP-2 + CP-3                         │
│  └────────────────┘                                                                  │
│                                                                                      │
│  ┌────────────────┐                                                                  │
│  │ TrueNAS        │  ← External NAS (Storage)                                        │
│  │ (NFS Server)   │  192.168.9.9 — NFS v4.2                                         │
│  │ 10 GbE NIC     │  Connection → K8s via 2.5 GbE NICs                              │
│  └────────────────┘                                                                  │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

## Update: Network Restructuring (192.168.1.0/24 → 192.168.9.0/24)

### Motivation

The cluster was configured on the `192.168.1.0/24` network with confusing address assignments. We decided to move to a dedicated network (`192.168.9.0/24`) with clear addressing logic:

- `192.168.9.1` — `192.168.9.99`: Reserved static addresses
- `192.168.9.100` — `192.168.9.254`: DHCP (LAN/WiFi devices)
- `.10` — `.12`: Control Plane nodes
- `.10`, `.20`, `.30`: Worker nodes
- `.8`, `.9`: HA VIP + MetalLB (exposed services)
- `.200` — `.220`: MetalLB pool (Type:LoadBalancer services)

See `docs/network.md` for the complete network documentation.
