# ============================================================
# Providers: Proxmox + Talos per il cluster su VM
# ============================================================

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
      version = "~> 3.0.0"
    }
  }
}

# ============================================================
# Provider Proxmox (bpg/proxmox)
# ============================================================

provider "proxmox" {
  # Configura con i dati del tuo server Proxmox
  # Consigliato: usa variabili d'ambiente per non salvare credenziali nel codice
  #   export PROXMOX_API_ENDPOINT="https://192.168.1.x:8006/api2/json"
  #   export PROXMOX_API_TOKEN_ID="terraform"
  #   export PROXMOX_API_TOKEN_SECRET="la-tua-password"

  api_endpoint = var.proxmox_api_endpoint

  # Token-based authentication (consigliato su Proxmox VE 8+)
  # Se usi user/password, commenta le righe qui sotto e decommenta username/password
  api_token_id    = "terraform"
  api_token_secret = "<LA-TUA-PROXMOX-API-TOKEN>"

  # [!] IN SICUREZZA: In produzione, usa un certificato TLS valido
  # In homelab, puoi disabilitare la verifica (NON FA'RE IN PRODUCTION)
  insecure_skip_tls_verify = true

  # Timeout per le chiamate API (predefinito 120s)
  pm_api_retry_max_count = 10
  pm_api_retry_min_delay_ms = 1000
}
