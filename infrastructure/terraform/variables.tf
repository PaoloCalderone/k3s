# ============================================================
# Variabili del Cluster K3s + Talos su Proxmox — 3 CP + 3 Worker (HA)
# ============================================================

# ==========================================
# Nome del Cluster
# ==========================================
variable "cluster_name" {
  description = "Nome logico del cluster"
  type        = string
  default     = "k3s-homelab"
}

# ==========================================
# Proxmox API
# ==========================================
variable "proxmox_api_endpoint" {
  description = "URL dell'API Proxmox (es. https://192.168.1.x:8006/api2/json)"
  type        = string
  default     = ""
}

# ==========================================
# Proxmox Storage (dischi VM del cluster)
# ==========================================
variable "proxmox_storage" {
  description = "Nome dello storage Proxmox per i dischi delle VM (es. local-lvm, pve, cephfs)"
  type        = string
  default     = "local-lvm"
}

# ==========================================
# Proxmox Network Bridge
# ==========================================
variable "proxmox_network_bridge" {
  description = "Bridge di rete Proxmox (vmbr9)"
  type        = string
  default     = "vmbr9"
}

variable "proxmox_vlan_id" {
  description = "VLAN tag da applicare alla NIC delle VM; null se vmbr9 è una rete untagged/access"
  type        = number
  default     = null
}

variable "talos_template_vm_id" {
  description = "VMID del template Talos preesistente su Proxmox"
  type        = number
  default     = 9000
}

variable "talos_template_node" {
  description = "Nodo Proxmox sul quale creare il template Talos"
  type        = string
  default     = "pve1"
}

variable "proxmox_iso_storage" {
  description = "Datastore file-based usato per scaricare l'immagine Talos (di solito local)"
  type        = string
  default     = "local"
}

# ==========================================
# Cloud-init Storage
# ==========================================
variable "proxmox_cloudinit_storage" {
  description = "Storage per cloud-init (di solito il default del node)"
  type        = string
  default     = "local-lvm"
}

# ==========================================
# Control Plane — 3 Nodi (HA)
# ==========================================
variable "control_plane" {
  description = "Configurazione dei nodi control plane (3 per HA — quorum etcd)"
  type = object({
    count                = number
    cpus                 = number
    memory_mb            = number
    disk_gb              = number
    ip_start             = string
    ip_addresses         = list(string)
    subnet_mask          = string
    gateway              = string
    dns_servers          = list(string)
    name_prefix          = string
    target_nodes         = list(string) # 3 nodi Proxmox fisici
    ha_vip               = string       # IP virtuale del load balancer (VIP)
    haproxy_vm_id        = number       # VMID della VM HAProxy su Proxmox
    control_plane_vm_ids = list(number) # VMID espliciti dei tre control-plane
  })
  default = {
    count                = 3
    cpus                 = 4
    memory_mb            = 4096
    disk_gb              = 40
    ip_start             = "192.168.9.11" # mantenuto per compatibilità
    ip_addresses         = ["192.168.9.11", "192.168.9.21", "192.168.9.31"]
    subnet_mask          = "255.255.255.0"
    gateway              = "192.168.9.1"
    dns_servers          = ["192.168.9.1"]
    name_prefix          = "k8s-cp"
    target_nodes         = ["pve1", "pve2", "pve3"]
    ha_vip               = "192.168.9.99"
    haproxy_vm_id        = 9099
    control_plane_vm_ids = [9011, 9021, 9031]
  }
}

# ==========================================
# Workers — 3 Nodi
# ==========================================
variable "workers" {
  description = "Configurazione dei nodi worker (array di oggetti)"
  type = list(object({
    index       = number
    vm_id       = number
    cpus        = number
    memory_mb   = number
    disk_gb     = number
    ip_address  = string
    subnet_mask = string
    gateway     = string
    dns_servers = list(string)
    name        = string
    target_node = string # Nodo Proxmox fisico su cui creare la VM
  }))
  default = [
    {
      index       = 0
      vm_id       = 9012
      cpus        = 4
      memory_mb   = 4096
      disk_gb     = 40
      ip_address  = "192.168.9.12"
      subnet_mask = "255.255.255.0"
      gateway     = "192.168.9.1"
      dns_servers = ["192.168.9.1"]
      name        = "k8s-w1"
      target_node = "pve1" # Distribuito su nodo fisico diverso dal CP
    },
    {
      index       = 1
      vm_id       = 9022
      cpus        = 4
      memory_mb   = 4096
      disk_gb     = 40
      ip_address  = "192.168.9.22"
      subnet_mask = "255.255.255.0"
      gateway     = "192.168.9.1"
      dns_servers = ["192.168.9.1"]
      name        = "k8s-w2"
      target_node = "pve2"
    },
    {
      index       = 2
      vm_id       = 9032
      cpus        = 4
      memory_mb   = 4096
      disk_gb     = 40
      ip_address  = "192.168.9.32"
      subnet_mask = "255.255.255.0"
      gateway     = "192.168.9.1"
      dns_servers = ["192.168.9.1"]
      name        = "k8s-w3"
      target_node = "pve3"
    }
  ]
}

# ==========================================
# K3s Configuration
# ==========================================
variable "k3s_token" {
  description = "Token segreto per il cluster K3s (per il join dei nodi)"
  type        = string
  default     = "" # Generato da talosctl gen o usato da bootstrap
}

variable "k3s_version" {
  description = "Versione di K3s da installare"
  type        = string
  default     = "v1.32.2+k3s1"
}

variable "k3s_disable" {
  description = "Lista di addon K3s da disabilitare"
  type        = list(string)
  default     = ["traefik", "servicelb"] # Usiamo Flux + MetalLB
}

variable "k3s_extra_args" {
  description = "Argomenti extra passati a K3s server/agent"
  type        = string
  default     = ""
}

# ==========================================
# Network del Cluster
# ==========================================
variable "pod_cidr" {
  description = "CIDR per i pod del cluster (per Flannel/Cilium)"
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "CIDR per i servizi del cluster"
  type        = string
  default     = "10.96.0.0/12"
}

variable "dns_service_ip" {
  description = "IP fisso del servizio CoreDNS"
  type        = string
  default     = "10.96.0.10"
}

# ==========================================
# MetalLB — IP pool per servizi LoadBalancer
# ==========================================
variable "metallb_ip_range_start" {
  description = "Inizio range IP per MetalLB"
  type        = string
  default     = "192.168.9.200"
}

variable "metallb_ip_range_end" {
  description = "Fine range IP per MetalLB"
  type        = string
  default     = "192.168.9.220"
}

# ==========================================
# TrueNAS NFS — Path del share NFS
# ==========================================
variable "truenas_nfs_server" {
  description = "IP del server NFS"
  type        = string
  default     = "192.168.9.9"
}

variable "truenas_nfs_path" {
  description = "Path NFS esportato su TrueNAS (es. /mnt/pool/kubernetes)"
  type        = string
  default     = "/mnt/pool/kubernetes"
}

variable "truenas_nfs_version" {
  description = "Versione NFS (4 o 3)"
  type        = string
  default     = "4.2"
}

variable "truenas_nfs_options" {
  description = "Opzioni di mount NFS"
  type        = string
  default     = "vers=4.2,rw,hard,intr,timeo=60,retrans=2"
}

# ==========================================
# Talos & Kubernetes Version
# ==========================================
variable "talos_version" {
  description = "Versione di Talos Linux"
  type        = string
  default     = "v1.9.3"
}

variable "kubernetes_version" {
  description = "Versione Kubernetes (usata dal image factory Talos)"
  type        = string
  default     = "1.32.2"
}
