# Infrastruttura Proxmox: 3 control-plane + 3 worker + 1 load balancer.
# Le VM sono cloni completi di un template Talos preesistente.

locals {
  talos_image_url = "https://github.com/siderolabs/talos/releases/download/${var.talos_version}/metal-amd64.raw.zst"

  control_plane_ips = var.control_plane.ip_addresses

  worker_ips = {
    for worker in var.workers : worker.name => worker.ip_address
  }

  haproxy_vip        = var.control_plane.ha_vip
  cp_backend_ips     = local.control_plane_ips
  worker_backend_ips = [for worker in var.workers : worker.ip_address]

  all_cluster_ips = concat(
    local.control_plane_ips,
    [for worker in var.workers : worker.ip_address],
    [local.haproxy_vip, var.truenas_nfs_server]
  )
}

resource "terraform_data" "download_talos_disk" {
  triggers_replace = [var.talos_version, local.talos_image_url]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      mkdir -p "${path.module}/.artifacts"
      curl -fL --retry 3 -o "${path.module}/.artifacts/talos-${var.talos_version}-amd64.raw.zst" "${local.talos_image_url}"
      zstd -d -f "${path.module}/.artifacts/talos-${var.talos_version}-amd64.raw.zst" -o "${path.module}/.artifacts/talos-${var.talos_version}-amd64.raw"
    EOT
  }
}

resource "proxmox_virtual_environment_file" "talos_disk" {
  depends_on = [terraform_data.download_talos_disk]

  node_name    = var.talos_template_node
  datastore_id = var.proxmox_iso_storage
  content_type = "import"

  source_file {
    path      = "${path.module}/.artifacts/talos-${var.talos_version}-amd64.raw"
    file_name = "talos-${var.talos_version}-amd64.raw"
  }
}

resource "proxmox_virtual_environment_vm" "talos_template" {
  name        = "talos-template"
  description = "Talos ${var.talos_version} base template managed by Terraform"
  node_name   = var.talos_template_node
  vm_id       = var.talos_template_vm_id

  agent {
    enabled = false
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = var.proxmox_storage
    interface    = "scsi0"
    import_from  = proxmox_virtual_environment_file.talos_disk.id
    size         = 8
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge   = var.proxmox_network_bridge
    model    = "virtio"
    firewall = false
    vlan_id  = var.proxmox_vlan_id
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  boot_order = ["scsi0"]
  started    = false
  on_boot    = false
  template   = true
  tags       = sort(["k8s", "talos", "template", var.cluster_name])
}

resource "proxmox_virtual_environment_vm" "haproxy_lb" {
  name      = "haproxy-lb"
  node_name = var.control_plane.target_nodes[0]
  vm_id     = var.control_plane.haproxy_vm_id

  clone {
    vm_id     = proxmox_virtual_environment_vm.talos_template.vm_id
    node_name = proxmox_virtual_environment_vm.talos_template.node_name
    full      = true
    retries   = 3
  }

  agent {
    enabled = false
  }

  cpu {
    cores = 1
    type  = "host"
  }

  memory {
    dedicated = 1024
  }

  disk {
    datastore_id = var.proxmox_storage
    interface    = "scsi0"
    size         = 10
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge   = var.proxmox_network_bridge
    model    = "virtio"
    firewall = false
    vlan_id  = var.proxmox_vlan_id
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  boot_order      = ["scsi0"]
  on_boot         = true
  started         = true
  stop_on_destroy = true
  tags            = sort(["haproxy-lb", "k8s", var.cluster_name])
}

resource "proxmox_virtual_environment_vm" "control_plane" {
  count = var.control_plane.count

  name      = "${var.control_plane.name_prefix}${count.index + 1}"
  node_name = var.control_plane.target_nodes[count.index]
  vm_id     = var.control_plane.control_plane_vm_ids[count.index]

  clone {
    vm_id     = proxmox_virtual_environment_vm.talos_template.vm_id
    node_name = proxmox_virtual_environment_vm.talos_template.node_name
    full      = true
    retries   = 3
  }

  agent {
    enabled = false
  }

  cpu {
    cores = var.control_plane.cpus
    type  = "host"
  }

  memory {
    dedicated = var.control_plane.memory_mb
  }

  disk {
    datastore_id = var.proxmox_storage
    interface    = "scsi0"
    size         = var.control_plane.disk_gb
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge   = var.proxmox_network_bridge
    model    = "virtio"
    firewall = false
    vlan_id  = var.proxmox_vlan_id
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  boot_order      = ["scsi0"]
  on_boot         = true
  started         = true
  stop_on_destroy = true
  tags            = sort(["control-plane", "k8s", var.cluster_name])
}

resource "proxmox_virtual_environment_vm" "worker" {
  for_each = { for worker in var.workers : worker.name => worker }

  name      = each.value.name
  node_name = each.value.target_node
  vm_id     = each.value.vm_id

  clone {
    vm_id     = proxmox_virtual_environment_vm.talos_template.vm_id
    node_name = proxmox_virtual_environment_vm.talos_template.node_name
    full      = true
    retries   = 3
  }

  agent {
    enabled = false
  }

  cpu {
    cores = each.value.cpus
    type  = "host"
  }

  memory {
    dedicated = each.value.memory_mb
  }

  disk {
    datastore_id = var.proxmox_storage
    interface    = "scsi0"
    size         = each.value.disk_gb
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge   = var.proxmox_network_bridge
    model    = "virtio"
    firewall = false
    vlan_id  = var.proxmox_vlan_id
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  boot_order      = ["scsi0"]
  on_boot         = true
  started         = true
  stop_on_destroy = true
  tags            = sort(["k8s", var.cluster_name, "worker"])
}

output "haproxy_vip" {
  description = "VIP usato per accedere all'API Kubernetes"
  value       = local.haproxy_vip
}

output "control_plane_ips" {
  value = local.control_plane_ips
}

output "control_plane_vm_names" {
  value = {
    for index, vm in proxmox_virtual_environment_vm.control_plane :
    "${var.control_plane.name_prefix}${index + 1}" => vm.name
  }
}

output "worker_ips" {
  value = local.worker_ips
}

output "worker_vm_names" {
  value = {
    for name, vm in proxmox_virtual_environment_vm.worker : name => vm.name
  }
}

output "truenas_nfs_server" {
  value = var.truenas_nfs_server
}

output "truenas_nfs_path" {
  value = var.truenas_nfs_path
}

output "all_cluster_ips" {
  value = local.all_cluster_ips
}

output "next_steps" {
  value = <<-EOT
    1. Applica le configurazioni Talos ai singoli IP dei nodi.
    2. Esegui il bootstrap etcd su un singolo control-plane, non sul VIP.
    3. Configura e avvia il load balancer verso i tre control-plane.
    4. Estrai il kubeconfig e verifica il cluster.
  EOT
}
