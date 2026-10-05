locals {
  nodes = merge(
    { for node in var.control_planes : node.name => merge(node, { role = "server" }) },
    { for node in var.workers : node.name => merge(node, { role = "agent" }) }
  )
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_file)))
}

resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  node_name      = var.template_node
  datastore_id   = var.proxmox_iso_storage
  content_type   = "import"
  url            = var.ubuntu_image_url
  file_name      = "ubuntu-noble-server-cloudimg-amd64.qcow2"
  overwrite      = false
  upload_timeout = 900
}

resource "proxmox_virtual_environment_vm" "ubuntu_template" {
  name        = "ubuntu-2404-cloud-template"
  description = "Ubuntu 24.04 cloud image template managed by Terraform"
  node_name   = var.template_node
  vm_id       = var.template_vm_id
  template    = true
  started     = false
  on_boot     = false

  agent {
    enabled = true
    trim    = true
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
    import_from  = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    size         = 8
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge   = var.proxmox_network_bridge
    model    = "virtio"
    firewall = true
    vlan_id  = var.proxmox_vlan_id
  }

  initialization {
    datastore_id = var.proxmox_cloudinit_storage

    ip_config {
      ipv4 { address = "dhcp" }
    }

    user_account {
      username = var.ssh_username
      keys     = [local.ssh_public_key]
    }
  }

  operating_system { type = "l26" }
  serial_device {}
  boot_order = ["scsi0"]
  tags       = sort(["k3s", "template", "ubuntu"])
}

resource "proxmox_virtual_environment_vm" "node" {
  for_each = local.nodes

  name        = each.value.name
  description = "${var.cluster_name} ${each.value.role} managed by Terraform"
  node_name   = each.value.target_node
  vm_id       = each.value.vm_id
  on_boot     = true
  started     = true

  clone {
    vm_id     = proxmox_virtual_environment_vm.ubuntu_template.vm_id
    node_name = proxmox_virtual_environment_vm.ubuntu_template.node_name
    full      = true
    retries   = 3
  }

  agent {
    enabled = true
    trim    = true
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
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge   = var.proxmox_network_bridge
    model    = "virtio"
    firewall = true
    vlan_id  = var.proxmox_vlan_id
  }

  initialization {
    datastore_id = var.proxmox_cloudinit_storage

    dns { servers = var.dns_servers }

    ip_config {
      ipv4 {
        address = "${each.value.ip_address}/24"
        gateway = var.gateway
      }
    }

    user_account {
      username = var.ssh_username
      keys     = [local.ssh_public_key]
    }
  }

  operating_system { type = "l26" }
  serial_device {}
  boot_order      = ["scsi0"]
  stop_on_destroy = true
  tags            = sort(["k3s", var.cluster_name, each.value.role])
}
