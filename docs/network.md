# Piano di rete canonico

## Proxmox management

- pve1: `192.168.0.10`
- pve2: `192.168.0.20`
- pve3: `192.168.0.30`

## Rete Kubernetes su vmbr9

CIDR `192.168.9.0/24`, gateway `192.168.9.1`.

- Control plane: `192.168.9.11`, `.21`, `.31`
- Worker: `192.168.9.12`, `.22`, `.32`
- kube-vip API: `192.168.9.99`
- NFS: `192.168.9.9`
- MetalLB: `192.168.9.200-192.168.9.220`

Il pool MetalLB deve essere riservato sul router e completamente escluso dal DHCP. Il VIP `.99` e tutti gli IP dei nodi devono essere statici e fuori dal DHCP.

`vmbr9` è configurato come rete access/untagged nelle variabili correnti (`proxmox_vlan_id = null`). Se il bridge richiede tagging, impostare esplicitamente il VLAN ID coerente con la configurazione Proxmox e dello switch.
