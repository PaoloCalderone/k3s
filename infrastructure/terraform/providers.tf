terraform {
  required_version = ">= 1.7.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.88.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_api_endpoint
  insecure = true
  # Authentication is supplied through PROXMOX_VE_API_TOKEN.
}
