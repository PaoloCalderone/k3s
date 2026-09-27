# ============================================================
# Output — Cluster 3 CP + 3 Worker (HA) su Proxmox
# ============================================================

output "haproxy_vip" {
  description = "IP virtuale del Load Balancer (VIP)"
  value       = local.haproxy_vip
}

output "control_plane_ips" {
  description = "IP dei nodi control plane (singoli)"
  value       = local.control_plane_ips
}

output "control_plane_vm_names" {
  description = "Nomi delle VM control plane su Proxmox"
  value = {
    for i in range(var.control_plane.count) :
    "${var.control_plane.name_prefix}-${i + 1}" => proxmox_vm_qemu.control_plane[i].name
  }
}

output "worker_ips" {
  description = "IP dei nodi worker"
  value = {
    for w in var.workers :
    w.name => w.ip_address
  }
}

output "worker_vm_names" {
  description = "Nomi delle VM worker su Proxmox"
  value = {
    for name, vm in proxmox_vm_qemu.worker : name => vm.name
  }
}

output "truenas_nfs_server" {
  description = "IP del TrueNAS (server NFS)"
  value       = var.truenas_nfs_server
}

output "truenas_nfs_path" {
  description = "Path NFS esportato su TrueNAS"
  value       = var.truenas_nfs_path
}

output "all_cluster_ips" {
  description = "Tutti gli IP del cluster (CP + Worker + LB + TrueNAS)"
  value = concat(
    local.control_plane_ips,
    [var.truenas_nfs_server],
    [local.haproxy_vip],
    [for w in var.workers : w.ip_address]
  )
}

output "next_steps" {
  description = "Prossimi passi dopo terraform apply"
  value = <<-EOT
====================================================
Cluster 3 CP + 3 Worker — Prossimi Passi
====================================================

1. Verifica VM create su Proxmox UI:
   - CP: k8s-cp-1 (192.168.1.100), k8s-cp-2 (192.168.1.101), k8s-cp-3 (192.168.1.102)
   - Worker: k8s-w1 (192.168.1.110), k8s-w2 (192.168.1.111), k8s-w3 (192.168.1.112)
   - LB: haproxy-lb (VIP: ${local.haproxy_vip})

2. Bootstrap con il VIP (non un singolo CP!):
   talosctl bootstrap --nodes ${local.haproxy_vip}

3. Esporta kubeconfig:
   talosctl kubeconfig . --nodes ${local.haproxy_vip}

4. Applica le configs machine di ogni nodo:
   talosctl apply-config --nodes <CP-IP> --file infrastructure/talos/node1-controlplane.yaml
   talosctl apply-config --nodes <WORKER-IP> --file infrastructure/talos/node2-worker.yaml
   ...

5. Installa Flux:
   flux bootstrap github --owner <user> --repository <repo> --branch main --path ./flux

6. Verifica:
   kubectl get nodes
   kubectl get pods -A -n kube-system

VIP del Load Balancer: ${local.haproxy_vip}
IP Control Plane: ${join(", ", local.control_plane_ips)}
IP Worker: ${join(", ", [for w in var.workers : w.ip_address])}
EOT
}
