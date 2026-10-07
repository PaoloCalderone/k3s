# Canonical Network Plan

## Proxmox management

- pve1: `192.168.0.10`
- pve2: `192.168.0.20`
- pve3: `192.168.0.30`

## Kubernetes network on vmbr9

CIDR `192.168.9.0/24`, gateway `192.168.9.1`.

- Control plane: `192.168.9.11`, `.21`, `.31`
- Workers: `192.168.9.12`, `.22`, `.32`
- kube-vip API: `192.168.9.99`
- NFS: `192.168.9.9`
- MetalLB: `192.168.9.200-192.168.9.220`

The MetalLB pool must be reserved on the router and completely excluded from DHCP. The VIP `.99` and all node IPs must be static and outside the DHCP range.

`vmbr9` is configured as an access/untagged network in the current variables (`proxmox_vlan_id = null`). If the bridge requires tagging, explicitly set the VLAN ID consistent with the Proxmox and switch configuration.
