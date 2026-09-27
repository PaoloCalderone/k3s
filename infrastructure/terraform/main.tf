# ============================================================
# Infrastruttura: 6 VM K3s (3 CP + 3 Worker) + HAProxy Load Balancer su Proxmox
# Mappatura Proxmox → VM Kubernetes:
#   pve1  → k8s-cp-1 (CP, 192.168.1.100) + k8s-w3 (Worker, 192.168.1.112)
#   pve2  → k8s-cp-2 (CP, 192.168.1.101) + k8s-w1 (Worker, 192.168.1.110)
#   pve3  → k8s-cp-3 (CP, 192.168.1.102) + k8s-w2 (Worker, 192.168.1.111)
#   LB    → haproxy-lb    (Load Balancer VIP: 192.168.1.99)
# ============================================================

# ============================================================
# 1. Download della ISO di Talos dalla Image Factory
# ============================================================

data "http" "talos_version" {
  url = "https://factory.talos.dev/version"
}

# Scarica l'ISO QEMU di Talos dal factory (con embedded K3s config)
resource "null_resource" "download_talos_iso" {
  triggers = {
    talos_version    = var.talos_version
    kubernetes_version = var.kubernetes_version
  }

  provisioner "local-exec" {
    command = <<EOF
set -e
ISO_DIR="/tmp/talos-iso"
mkdir -p "$ISO_DIR"

ISO_FILE="$ISO_DIR/talos-qemu-${var.talos_version}.iso"

# Skip download if file exists and version hasn't changed
if [ -f "$ISO_FILE" ]; then
  echo "Talos ISO already exists, skipping download"
  exit 0
fi

echo "Downloading Talos ISO from Image Factory..."
FACTORY_URL="https://factory.talos.dev/splash/https://github.com/siderolabs/installer/releases/download/${var.talos_version}/talos-qemu-amd64.iso?kubernetes=${var.kubernetes_version}"
curl -fSL -o "$ISO_FILE" \
  -H "Accept: application/octet-stream" \
  "$FACTORY_URL" || \
curl -fSL -o "$ISO_FILE" \
  "https://github.com/siderolabs/talos/releases/download/${var.talos_version}/talos-qemu-amd64.iso"

echo "ISO downloaded to: $ISO_FILE"
EOF
  }
}

# ============================================================
# 2. Load Balancer — HAProxy VM su Proxmox
#    Gestisce il VIP (Virtual IP) che bilancia le connessioni
#    verso i 3 nodi Control Plane di Kubernetes.
# ============================================================

resource "proxmox_vm_qemu" "haproxy_lb" {
  name      = "haproxy-lb"
  target_node = var.control_plane.target_nodes[0]  # HAProxy gira su un nodo fisico

  # --- VM Basics ---
  clone = "talos-template"  # Template Proxmox preesistente
  agent = 0

  # --- CPU e Memoria ---
  cores   = 1
  cpu     = "host"
  memory  = 1024  # 1 GB basta per HAProxy

  # --- Disk (piccolo, HAProxy non serve storage) ---
  scsihw  = "virtio-scsi-single"

  disk {
    size       = 10  # 10 GB per HAProxy (solo OS)
    storage    = var.proxmox_storage
    iothread   = true
  }

  # --- Network ---
  network {
    bridge   = var.proxmox_network_bridge
    model    = "virtio"
    firewall = false
  }

  # --- Boot ---
  boot      = "c"  # Boot dal disco
  bootdisk  = ["scsi0"]

  # --- Cloud-init (disabilitato — HAProxy si configura dopo bootstrap) ---
  cloudinit = "none"

  # --- Serial Console ---
  serial0 {}

  # --- Start ---
  start_on_created = true

  # --- Tags ---
  tags = "k8s,${var.cluster_name},haproxy-lb"

  # --- Stabile su un nodo specifico ---
  onboot = true
}

# ============================================================
# 3. Nodi Control Plane — 3 VM (HA con etcd cluster)
# ============================================================

resource "proxmox_vm_qemu" "control_plane" {
  count       = var.control_plane.count
  name        = "${var.control_plane.name_prefix}-${count.index + 1}"
  target_node = var.control_plane.target_nodes[count.index]  # 1 CP per nodo fisico

  # --- Clone dal template ---
  clone = "talos-template"

  # --- VMID unici (200, 201, 202) ---
  vmid = 200 + count.index

  # --- CPU e Memoria ---
  cores   = var.control_plane.cpus
  cpu     = "host"
  memory  = var.control_plane.memory_mb

  # --- Disk ---
  scsihw = "virtio-scsi-single"

  disk {
    size       = var.control_plane.disk_gb
    storage    = var.proxmox_storage
    iothread   = true
    discard    = "on"
  }

  # --- Network ---
  network {
    bridge   = var.proxmox_network_bridge
    model    = "virtio"
    firewall = false
  }

  # --- Boot (prima CD-ROM Talos, poi disco) ---
  boot      = "d"
  bootdisk  = ["scsi0"]

  # --- CD-ROM con ISO di Talos (rimuovi dopo il bootstrap) ---
  cdrom {
    iso   = "local:iso/talos-qemu-${var.talos_version}.iso"
    media = "cdrom"
  }

  # --- Cloud-init (disabilitato) ---
  cloudinit = "none"

  # --- Serial Console ---
  serial0 {}

  # --- Start ---
  start_on_created = true

  # --- Tags ---
  tags = "k8s,${var.cluster_name},control-plane"

  onboot = true
}

# ============================================================
# 4. Nodi Worker — 3 VM (distribuiti sui nodi fisici)
# ============================================================

resource "proxmox_vm_qemu" "worker" {
  for_each  = { for w in var.workers : w.name => w }
  name        = each.value.name
  target_node = each.value.target_node  # 1 VM per nodo fisico Proxmox

  # --- Clone dal template ---
  clone = "talos-template"

  # --- VMID unici (300, 301, 302) ---
  vmid = 300 + each.value.index

  # --- CPU e Memoria ---
  cores   = each.value.cpus
  cpu     = "host"
  memory  = each.value.memory_mb

  # --- Disk ---
  scsihw = "virtio-scsi-single"

  disk {
    size       = each.value.disk_gb
    storage    = var.proxmox_storage
    iothread   = true
    discard    = "on"
  }

  # --- Network ---
  network {
    bridge   = var.proxmox_network_bridge
    model    = "virtio"
    firewall = false
  }

  # --- Boot ---
  boot      = "dc"  # Prima CD-ROM, poi disco
  bootdisk  = ["scsi0"]

  # --- CD-ROM con ISO (rimuovi dopo bootstrap) ---
  cdrom {
    iso   = "local:iso/talos-qemu-${var.talos_version}.iso"
    media = "cdrom"
  }

  # --- Cloud-init (disabilitato) ---
  cloudinit = "none"

  # --- Serial Console ---
  serial0 {}

  # --- Start ---
  start_on_created = true

  # --- Tags ---
  tags = "k8s,${var.cluster_name},worker"

  onboot = true
}

# ============================================================
# 5. IP statici per i nodi del cluster (utile per il bootstrap)
# ============================================================

locals {
  # IP di tutti i nodi Control Plane
  control_plane_ips = [
    for i in range(var.control_plane.count) :
    cidrhost(
      "${var.control_plane.ip_start}/${replace(var.control_plane.subnet_mask, ".", "/")}",
      i
    )
  ]

  # IP di tutti i nodi Worker
  worker_ips = {
    for w in var.workers : w.name => w.ip_address
  }

  # IP del Load Balancer (VIP)
  haproxy_vip = var.control_plane.ha_vip

  # Tutti gli IP del cluster (CP + Worker + LB)
  all_cluster_ips = concat(
    local.control_plane_ips,
    [var.truenas_nfs_server],  # TrueNAS
    [local.haproxy_vip],       # HAProxy VIP
    [for w in var.workers : w.ip_address]
  )

  # Array di tutti gli IP CP (usati per HAProxy upstream)
  cp_backend_ips = local.control_plane_ips

  # Array di tutti gli IP Worker (usati per MetalLB se serve)
  worker_backend_ips = [for w in var.workers : w.ip_address]
}

# ============================================================
# 6. Output — Informazioni utili dopo 'terraform apply'
# ============================================================

output "haproxy_vip" {
  description = "IP virtuale del Load Balancer (VIP) — usato per accedere all'API K8s"
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
   - CP: k8s-cp-1 (192.168.9.10), k8s-cp-2 (192.168.9.11), k8s-cp-3 (192.168.9.12)
   - Worker: k8s-w1 (192.168.9.10), k8s-w2 (192.168.9.20), k8s-w3 (192.168.9.30)
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
