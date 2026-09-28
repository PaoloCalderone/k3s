variable "cluster_name" {
  type    = string
  default = "k3s-homelab"
}

variable "proxmox_api_endpoint" {
  type = string
}

variable "proxmox_storage" {
  type    = string
  default = "local-lvm"
}

variable "proxmox_iso_storage" {
  type    = string
  default = "local"
}

variable "proxmox_cloudinit_storage" {
  type    = string
  default = "local-lvm"
}

variable "proxmox_network_bridge" {
  type    = string
  default = "vmbr9"
}

variable "proxmox_vlan_id" {
  type    = number
  default = null
}

variable "template_node" {
  type    = string
  default = "pve1"
}

variable "template_vm_id" {
  type    = number
  default = 9000
}

variable "ubuntu_image_url" {
  type    = string
  default = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "ssh_public_key_file" {
  type = string
}

variable "ssh_username" {
  type    = string
  default = "ubuntu"
}

variable "gateway" {
  type    = string
  default = "192.168.9.1"
}

variable "dns_servers" {
  type    = list(string)
  default = ["192.168.9.1"]
}

variable "control_plane_vip" {
  type    = string
  default = "192.168.9.99"
}

variable "control_planes" {
  type = list(object({
    name        = string
    vm_id       = number
    ip_address  = string
    target_node = string
    cpus        = number
    memory_mb   = number
    disk_gb     = number
  }))
  default = [
    { name = "k8s-cp1", vm_id = 9011, ip_address = "192.168.9.11", target_node = "pve1", cpus = 4, memory_mb = 4096, disk_gb = 40 },
    { name = "k8s-cp2", vm_id = 9021, ip_address = "192.168.9.21", target_node = "pve2", cpus = 4, memory_mb = 4096, disk_gb = 40 },
    { name = "k8s-cp3", vm_id = 9031, ip_address = "192.168.9.31", target_node = "pve3", cpus = 4, memory_mb = 4096, disk_gb = 40 }
  ]
}

variable "workers" {
  type = list(object({
    name        = string
    vm_id       = number
    ip_address  = string
    target_node = string
    cpus        = number
    memory_mb   = number
    disk_gb     = number
  }))
  default = [
    { name = "k8s-w1", vm_id = 9012, ip_address = "192.168.9.12", target_node = "pve1", cpus = 4, memory_mb = 4096, disk_gb = 40 },
    { name = "k8s-w2", vm_id = 9022, ip_address = "192.168.9.22", target_node = "pve2", cpus = 4, memory_mb = 4096, disk_gb = 40 },
    { name = "k8s-w3", vm_id = 9032, ip_address = "192.168.9.32", target_node = "pve3", cpus = 4, memory_mb = 4096, disk_gb = 40 }
  ]
}

variable "k3s_version" {
  type    = string
  default = "v1.32.2+k3s1"
}

variable "pod_cidr" {
  type    = string
  default = "10.42.0.0/16"
}

variable "service_cidr" {
  type    = string
  default = "10.43.0.0/16"
}

variable "cluster_dns" {
  type    = string
  default = "10.43.0.10"
}

variable "nfs_server" {
  type    = string
  default = "192.168.9.9"
}

variable "nfs_path" {
  type    = string
  default = "/mnt/pool/kubernetes"
}

variable "metallb_range" {
  type    = string
  default = "192.168.9.200-192.168.9.220"
}
