# Documentazione di Rete — Cluster K3s + Talos su Proxmox

## 1. Panoramica

| Parametro | Valore |
|-----------|--------|
| **Rete logica del cluster** | `192.168.9.0/24` |
| **VLAN dedicata** | VLAN separata (consigliata) |
| **Mask / Gateway** | `/24` (255.255.255.0) / `192.168.9.1` |
| **Range DHCP** | `192.168.9.100` — `192.168.9.254` |
| **Range riservato (statico)** | `192.168.9.1` — `192.168.9.99` |
| **Interfaccia di rete** | `eth0` (su ogni nodo Talos) |

## 2. Schema di Indirizzamento

Il cluster utilizza 6 nodi (3 Control Plane + 3 Worker) più un Load Balancer (HAProxy) e un NAS TrueNAS.

### 2.1 Infrastruttura di Base

| Indirizzo | Ruolo | Note |
|-----------|-------|------|
| `192.168.9.1` | Gateway / Router | Switch/router della rete fisica |
| `192.168.9.2` | DNS interno (CoreDNS) | Risolto da `/etc/resolv.conf` |
| `192.168.9.3` | Monitoraggio | Prometheus / Grafana / Node Exporter |

### 2.2 Nodi Control Plane (3 nodi)

| Indirizzo | Hostname | Ruolo | Proxmox Node |
|-----------|----------|-------|--------------|
| `192.168.9.10` | `k8s-cp-1` | etcd + API Server + Scheduler | `pve1` |
| `192.168.9.11` | `k8s-cp-2` | etcd + API Server + Scheduler | `pve2` |
| `192.168.9.12` | `k8s-cp-3` | etcd + API Server + Scheduler | `pve3` |

### 2.3 Nodi Worker (3 nodi)

| Indirizzo | Hostname | Ruolo | Proxmox Node |
|-----------|----------|-------|--------------|
| `192.168.9.10` | `k8s-w1` | Workload deployment | `pve1` |
| `192.168.9.20` | `k8s-w2` | Workload deployment | `pve2` |
| `192.168.9.30` | `k8s-w3` | Workload deployment | `pve3` |

### 2.4 Servizi del Cluster

| Indirizzo | Servizio | Note |
|-----------|----------|------|
| `192.168.9.20` | Traefik (Ingress Controller) | Servizio di routing HTTP/HTTPS |
| `192.168.9.30` | NFS CSI / Longhorn Manager | Storage persistente |
| `192.168.9.40` | Container Registry | Registrazione immagini Docker |
| `192.168.9.50` | NAS / TrueNAS | Server NFS (montato su tutti i nodi) |
| `192.168.9.88` | Servizi di controllo | Backup, NVR, o altri servizi sistems |

### 2.5 Control Plane HA — VIP

| Indirizzo | Ruolo | Gestito da |
|-----------|-------|------------|
| `192.168.9.8` | VIP etcd + API Server (HA) | kube-vip / HAProxy |
| `192.168.9.8:6443` | Kubernetes API Endpoint | Bilancia verso i 3 CP |

### 2.6 MetalLB — Servizi Esposti

| Indirizzo | Ruolo |
|-----------|-------|
| `192.168.9.9` | IP esposto principale (Traefik HTTP/S default) |
| `192.168.9.200` — `192.168.9.220` | Pool MetalLB (servizi Type:LoadBalancer) |

### 2.7 Range DHCP

| Range | Utilizzo |
|-------|----------|
| `192.168.9.100` — `192.168.9.254` | DHCP (client LAN, WiFi, IoT) |

## 3. Subnet Interne a K3s

Queste subnet sono gestite internamente da Kubernetes. Non corrispondono agli IP fisici dei nodi.

| Livello | Subnet | Descrizione |
|---------|--------|-------------|
| **Pod CIDR** | `10.244.0.0/16` | Indirizzi interni ai container (Flannel/Cilium) |
| **Service CIDR** | `10.96.0.0/12` | Indirizzi virtuali dei servizi (ClusterIP) |
| **DNS Service IP** | `10.96.0.10` | IP fisso del servizio CoreDNS (dentro Service CIDR) |
| **NodePort Range** | `30000` — `32767` | Porte esposte sui nodi |

## 4. Mappatura VM Proxmox

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

> **Nota:** `192.168.9.10` è usato sia da `k8s-cp-1` che da `k8s-w1` solo in questa nota esplicativa.
> In realtà, `k8s-w1` usa `192.168.9.10` (come definito nella tabella dei Worker).
> Se questo crea conflitti, valutare `192.168.9.4` per w1.

## 5. Logica di Assegnazione degli Indirizzi

| Zona | Range | Logica |
|------|-------|--------|
| **Infrastruttura** | `.1` — `.3` | Gateway, DNS, Monitoring (sempre fissi) |
| **Control Plane** | `.10` — `.12` | Nodi CP (uno per nodo fisico) |
| **Worker** | `.10`, `.20`, `.30` | Nodi Worker (uno per nodo fisico, multiplo di 10) |
| **Servizi** | `.20`, `.30`, `.40`, `.50`, `.88` | Servizi statici (multipli di 10, o end低調) |
| **HA VIP** | `.8`, `.9` | kube-vip / Load Balancer (extra-basso) |
| **MetalLB base** | `.9` | IP esposto principale |
| **MetalLB pool** | `.200` — `.220` | Servizi LoadBalancer (al di sopra del DHCP) |
| **DHCP** | `.100` — `.254` | Assegnazione automatica (non tocca range statico) |

## 6. Inter-VLAN Routing

Il cluster risiede su una VLAN dedicata (`192.168.9.0/24`). Per consentire la comunicazione con altri segmenti di rete (es. NAS su `192.168.0.0/24`), configurare il routing inter-VLAN sul gateway/router.

Regole firewall consigliate:

| Sorgente | Destinazione | Porta | Scopo |
|----------|--------------|-------|-------|
| VLAN K3S | NAS (`192.168.9.50`) | 2049 (NFS) | Montaggio storage |
| LAN principale | VLAN K3S (`.9`) | 80, 443 | Accesso servizi esposti |
| WAN | VLAN K3S (`.9`) | 80, 443 | Accesso servizi esposti (con firewall) |
| VLAN K3S | VLAN K3S (`.8:6443`) | 6443 | API K8s (interni) |

## 7. Compliance con k3s

| Parametro k3s | Valore | File di configurazione |
|---------------|--------|----------------------|
| `--cluster-cidr` | `10.244.0.0/16` | `cluster-config.yaml`, machine configs |
| `--service-cidr` | `10.96.0.0/12` | `cluster-config.yaml`, machine configs |
| `--cluster-dns` | `10.96.0.10` | `cluster-config.yaml`, machine configs |
| `--node-ip` | IP fisico del nodo (es. `192.168.9.10`) | Ogni machine config |
| `controlPlaneEndpoint` | `192.168.9.8:6443` | `cluster-config.yaml`, ogni machine config |
| MetalLB range | `192.168.9.9` + `.200-.220` | `flux/metallb.yaml` |

## 8. Checklist di Configurazione

- [ ] Gateway/router configurato con inter-VLAN routing tra `192.168.9.0/24` e LAN principale
- [ ] Firewall regola NFS dal cluster al NAS (`192.168.9.50:2049`)
- [ ] DHCP configurato su `192.168.9.100` — `192.168.9.254`
- [ ] IP statici riservati fuori dal DHCP (tutti gli indirizzi `.1` — `.99`)
- [ ] Interfacce di rete su Proxmox configurate con VLAN tag (se VLAN dedicata)
- [ ] SSH permettere accesso a tutti gli IP `.10`, `.11`, `.12`, `.10`, `.20`, `.30`
- [ ] Certificate SAN includono `192.168.9.8` (VIP) e `192.168.9.9` (MetalLB)
