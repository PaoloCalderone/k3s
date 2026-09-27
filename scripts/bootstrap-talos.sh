#!/bin/bash
# ============================================================
# bootstrap-talos.sh — Bootstrap del cluster K3s 3 CP + 3 Worker
# Network: 192.168.9.0/24 (VLAN dedicata)
# Mappatura nodi:
#   pve1 → k8s-cp1 (192.168.9.11) + k8s-w1 (192.168.9.11)
#   pve2 → k8s-cp2 (192.168.9.21) + k8s-w2 (192.168.9.22)
#   pve3 → k8s-cp3 (192.168.9.31) + k8s-w3 (192.168.9.32)
#   HA VIP: 192.168.9.99 (Load Balancer)
# =========================================

set -euo pipefail

# ============================================================
# Configurazione — MODIFICA QUESTI VALORI
# Network: 192.168.9.0/24 (VLAN dedicata)
# =========================================

# IP del VIP (Load Balancer) — usato per bootstrap e kubeconfig
HA_VIP="${HA_VIP:-192.168.9.99}"

# Path alla directory Talos configs (relative allo script)
TALOS_DIR="$(cd "$(dirname "$0")/../infrastructure/talos" && pwd)"

# Output directory per il kubeconfig
OUTPUT_DIR="$(pwd)"

# IP dei nodi del cluster
CP_IPS=("192.168.9.11" "192.168.9.21" "192.168.9.31")
WORKER_IPS=("192.168.9.12" "192.168.9.22" "192.168.9.32")
ALL_IPS=("${CP_IPS[@]}" "${WORKER_IPS[@]}")

# Nodi (per bootstrap — usa il VIP, non un singolo nodo)
CP_NAMES=("k8s-cp1" "k8s-cp2" "k8s-cp3")
WORKER_NAMES=("k8s-w1" "k8s-w2" "k8s-w3")

# ============================================================
# Utility
# ============================================================

info()  { echo -e "\e[32m[INFO]\e[0m  $*"; }
warn()  { echo -e "\e[33m[WARN]\e[0m  $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*" >&2; exit 1; }

# ============================================================
# Verifica prerequisiti
# ============================================================

info "Verifica prerequisiti..."

command -v talosctl  || error "talosctl non trovato. Installa: brew install talosctl"
command -v kubectl   || error "kubectl non trovato. Installa: brew install kubectl"

info "talosctl trovata."
info "kubectl trovata."

# ============================================================
# Passo 1: Bootstrap del cluster con il VIP (Load Balancer)
# ============================================================

info ""
info "============================================"
info "  Passo 1: Bootstrap del cluster K3s (HA)"
info "  Network: 192.168.9.0/24"
info "  VIP Load Balancer: $HA_VIP (su 3 nodi CP)"
info "  Nodi CP: ${CP_IPS[*]}"
info "  Nodi Worker: ${WORKER_IPS[*]}"
info "============================================"
info ""

# Bootstrap (avvia etcd e Kubernetes API server sul primo nodo raggiungibile)
# Il VIP (HAProxy) gestisce il routing verso i nodi CP
talosctl bootstrap --nodes "$HA_VIP" || error "Bootstrap fallito. Verifica che HAProxy e almeno 1 nodo CP siano disponibili."

info ""
info "Bootstrap completato. etcd e API server sono attivi sul nodo raggiungibile."
info ""

# ============================================================
# Passo 2: Estrai il Kubeconfig
# ============================================================

info ""
info "============================================"
info "  Passo 2: Estrazione del Kubeconfig"
info "============================================"
info ""

# Crea un directory temporanea per il kubeconfig
kubeconfig_dir="${OUTPUT_DIR}/kubeconfig"
mkdir -p "$kubeconfig_dir"

# Talos genera il kubeconfig direttamente (la API server risponde all'endpoint VIP)
talosctl kubeconfig --output "$kubeconfig_dir/kubeconfig" --nodes "$HA_VIP"

if [ ! -f "$kubeconfig_dir/kubeconfig" ]; then
  error "Kubeconfig non generato. Verifica che il cluster sia bootstrap."
fi

export KUBECONFIG="$kubeconfig_dir/kubeconfig"

info ""
info "Kubeconfig salvato in: $kubeconfig_dir/kubeconfig"
info ""
info "Verifica il cluster con:"
echo "  KUBECONFIG=$kubeconfig_dir/kubeconfig kubectl get nodes"

# ============================================================
# Passo 3: Applica la configurazione Talos (K3s) a tutti i nodi
# ============================================================

info ""
info "============================================"
info "  Passo 3: Applicazione configurazione Talos (K3s)"
info "  Nodi: 3 CP + 3 Worker = 6 nodi totali"
info "  Network: 192.168.9.0/24"
info "============================================"
info ""

# --- Applica config dei nodi Control Plane ---
info "Applico configs dei Control Plane (3 nodi)..."

talosctl apply-config --nodes "${CP_IPS[0]}" --insecure \
  --file "$TALOS_DIR/node1-controlplane.yaml"

talosctl apply-config --nodes "${CP_IPS[1]}" --insecure \
  --file "$TALOS_DIR/node2-controlplane.yaml"

talosctl apply-config --nodes "${CP_IPS[2]}" --insecure \
  --file "$TALOS_DIR/node3-controlplane.yaml"

info "Configs Control Plane applicati."

# --- Applica configs dei Worker ---
info "Applico configs dei Worker (3 nodi)..."

for i in 0 1 2; do
  worker_ip="${WORKER_IPS[$i]}"
  worker_name="${WORKER_NAMES[$i]}"

  # Controlla se il nodo è stato creato (timeout: 30s)
  if timeout 30 bash -c "echo > /dev/tcp/$worker_ip/50000" 2>/dev/null; then
    info "Applico config del Worker ($worker_name, IP: $worker_ip)..."

    case "$worker_name" in
      "k8s-w1")
        talosctl apply-config --nodes "$worker_ip" --insecure \
          --file "$TALOS_DIR/node2-worker.yaml"
        ;;
      "k8s-w2")
        talosctl apply-config --nodes "$worker_ip" --insecure \
          --file "$TALOS_DIR/node3-worker.yaml"
        ;;
      "k8s-w3")
        talosctl apply-config --nodes "$worker_ip" --insecure \
          --file "$TALOS_DIR/node4-worker.yaml"  # 3rd Worker
        ;;
    esac
  else
    warn "Nodo $worker_name ($worker_ip) non ancora raggiungibile (saltato). Procedi quando creato."
  fi
done

info "Configs Worker applicati."

# ============================================================
# Passo 4: Verifica del cluster
# ============================================================

info ""
info "============================================"
info "  Passo 4: Verifica del cluster (3 CP + 3 Worker)"
info "============================================"
info ""

info "Nodi del cluster:"
kubectl get nodes

info ""
info "Pods del sistema:"
kubectl get pods -A | grep -E "NAMESPACE|kube-system|k3s|coredns"

# ============================================================
# Passo 5: Verifica HA etcd cluster
# ============================================================

info ""
info "============================================"
info "  Passo 5: Verifica HA etcd (3 nodi)"
info "============================================"
info ""

# Verifica che etcd abbia 3 membri (3 CP)
info "Membri etcd:"
talosctl get etcdmember -A || warn "etcdmember non disponibile (cluster non ancora completo)."

# ============================================================
# Fatto!
# ============================================================

info ""
info "============================================"
info "  Cluster K3s bootstrap con successo! (3 CP + 3 Worker)"
info "  Network: 192.168.9.0/24"
info "  HA VIP: $HA_VIP"
info "  Control Plane: ${CP_IPS[*]}"
info "  Worker: ${WORKER_IPS[*]}"
info "============================================"
info ""
info "Prossimi passi:"
echo "  1. Installa Flux: flux bootstrap github --owner <user> --repository <repo> --path ./flux"
echo "  2. Deploy le applicazioni dalla directory flux/apps/"
echo "  3. Abilita Renovate per gli aggiornamenti automatici"
echo ""
info "Kubeconfig disponibile in: $kubeconfig_dir/kubeconfig"
echo ""
