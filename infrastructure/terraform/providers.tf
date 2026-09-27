terraform {
  required_version = ">= 1.7.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.88.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.7.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_api_endpoint
  insecure = true

  # Le credenziali non sono salvate nel repository.
  # Esporta prima di terraform plan/apply:
  #   export PROXMOX_VE_API_TOKEN='terraform@pam!terraform=TOKEN_SECRET'
  # In alternativa:
  #   export PROXMOX_VE_USERNAME='terraform@pam'
  #   export PROXMOX_VE_PASSWORD='PASSWORD'
}
