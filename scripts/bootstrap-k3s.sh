#!/usr/bin/env bash
set -Eeuo pipefail
trap 'rc=$?; printf "\033[31m[ERROR]\033[0m Riga %s (exit %s): %s\n" "$LINENO" "$rc" "$BASH_COMMAND" >&2' ERR

SSH_USER="${SSH_USER:-ubuntu}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/k3s_homelab}"
K3S_VERSION="${K3S_VERSION:-v1.32.2+k3s1}"
VIP="${VIP:-192.168.9.99}"
SUBNET="${SUBNET:-192.168.9.0/24}"
INTERFACE="${INTERFACE:-eth0}"
CP_IPS=(192.168.9.11 192.168.9.21 192.168.9.31)
WORKER_IPS=(192.168.9.12 192.168.9.22 192.168.9.32)
TOKEN_FILE="${TOKEN_FILE:-$HOME/.config/k3s-homelab/token}"
KUBECONFIG_OUT="${KUBECONFIG_OUT:-$PWD/kubeconfig}"
SSH_OPTS=(-i "$SSH_KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10)

log() { printf '\033[32m[INFO]\033[0m %s\n' "$*"; }
die() { printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
remote() { local ip="$1"; shift; ssh "${SSH_OPTS[@]}" "$SSH_USER@$ip" "$@"; }
wait_remote() {
  local ip="$1" command="$2" description="$3" timeout="${4:-300}" elapsed=0
  until remote "$ip" "$command" >/dev/null 2>&1; do
    (( elapsed >= timeout )) && die "Timeout: $description ($ip)"
    (( elapsed % 30 == 0 )) && printf '  ⏳ %s (%ds/%ds)\n' "$ip" "$elapsed" "$timeout"
    sleep 5; elapsed=$((elapsed + 5))
  done
}

for command in ssh scp kubectl openssl nc python3; do command -v "$command" >/dev/null || die "$command non disponibile"; done
mkdir -p "$(dirname "$TOKEN_FILE")"
chmod 700 "$(dirname "$TOKEN_FILE")"
if [[ ! -s "$TOKEN_FILE" ]]; then umask 077; openssl rand -hex 32 > "$TOKEN_FILE"; fi
chmod 600 "$TOKEN_FILE"
TOKEN="$(<"$TOKEN_FILE")"

for ip in "${CP_IPS[@]}" "${WORKER_IPS[@]}"; do
  log "Attendo SSH su $ip"
  wait_remote "$ip" true "SSH" 300
  remote "$ip" "sudo -n true" || die "sudo senza password non disponibile su $ip"
  cloud_rc=0
  cloud_output="$(remote "$ip" "sudo -n cloud-init status --wait" 2>&1)" || cloud_rc=$?
  printf '%s\n' "$cloud_output"
  [[ $cloud_rc -eq 0 || $cloud_rc -eq 2 ]] || die "cloud-init fallito su $ip"
  remote "$ip" "sudo -n install -d -m 0755 /etc/rancher/k3s && command -v curl >/dev/null && dpkg-query -W nfs-common >/dev/null 2>&1" || \
    remote "$ip" "sudo -n env DEBIAN_FRONTEND=noninteractive apt-get update && sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y curl nfs-common"
done

write_server_config() {
  local ip="$1" mode="$2" tmp
  tmp="$(mktemp)"
  cat > "$tmp" <<EOF
write-kubeconfig-mode: "0640"
token: "$TOKEN"
tls-san:
  - "$VIP"
cluster-cidr: "10.42.0.0/16"
service-cidr: "10.43.0.0/16"
cluster-dns: "10.43.0.10"
node-ip: "$ip"
flannel-iface: "$INTERFACE"
disable:
  - servicelb
secrets-encryption: true
EOF
  if [[ "$mode" == init ]]; then printf 'cluster-init: true\n' >> "$tmp"; else printf 'server: "https://%s:6443"\n' "${CP_IPS[0]}" >> "$tmp"; fi
  scp "${SSH_OPTS[@]}" "$tmp" "$SSH_USER@$ip:/tmp/k3s-config.yaml"
  rm -f "$tmp"
  remote "$ip" "sudo install -m 0600 /tmp/k3s-config.yaml /etc/rancher/k3s/config.yaml"
}

install_server() {
  local ip="$1" mode="$2"
  write_server_config "$ip" "$mode"
  if ! remote "$ip" "test -x /usr/local/bin/k3s && systemctl list-unit-files k3s.service >/dev/null 2>&1"; then
    remote "$ip" "curl -sfL https://get.k3s.io | sudo env INSTALL_K3S_VERSION='$K3S_VERSION' sh -s - server"
  else
    remote "$ip" "sudo systemctl daemon-reload && sudo systemctl enable --now k3s && sudo systemctl restart k3s"
  fi
  wait_remote "$ip" "sudo k3s kubectl get --raw=/readyz" "K3s server readyz" 600
}

log "Configuro cp1"
install_server "${CP_IPS[0]}" init
for ip in "${CP_IPS[@]:1}"; do log "Configuro server $ip"; install_server "$ip" join; done

log "Installo kube-vip"
remote "${CP_IPS[0]}" "sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml /usr/local/bin/k3s kubectl apply -f -" <<EOF
apiVersion: v1
kind: ServiceAccount
metadata: {name: kube-vip, namespace: kube-system}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: {name: system:kube-vip-role-binding}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: cluster-admin}
subjects:
- {kind: ServiceAccount, name: kube-vip, namespace: kube-system}
---
apiVersion: apps/v1
kind: DaemonSet
metadata: {name: kube-vip-ds, namespace: kube-system}
spec:
  selector: {matchLabels: {name: kube-vip-ds}}
  template:
    metadata: {labels: {name: kube-vip-ds}}
    spec:
      hostNetwork: true
      serviceAccountName: kube-vip
      nodeSelector: {node-role.kubernetes.io/control-plane: "true"}
      tolerations: [{operator: Exists}]
      containers:
      - name: kube-vip
        image: ghcr.io/kube-vip/kube-vip:v1.2.4
        args: [manager]
        env:
        - {name: address, value: "$VIP"}
        - {name: vip_arp, value: "true"}
        - {name: vip_interface, value: "$INTERFACE"}
        - {name: vip_leaderelection, value: "true"}
        - {name: cp_enable, value: "true"}
        - {name: cp_namespace, value: kube-system}
        securityContext: {capabilities: {add: [NET_ADMIN, NET_RAW]}}
EOF

elapsed=0
until nc -z -w 2 "$VIP" 6443 2>/dev/null; do
  (( elapsed >= 300 )) && { remote "${CP_IPS[0]}" "sudo k3s kubectl -n kube-system get pods -l name=kube-vip-ds -o wide; sudo k3s kubectl -n kube-system describe ds kube-vip-ds"; die "Timeout VIP $VIP:6443"; }
  sleep 5; elapsed=$((elapsed + 5))
done

for ip in "${WORKER_IPS[@]}"; do
  log "Configuro agent $ip"
  if remote "$ip" "systemctl list-unit-files k3s.service >/dev/null 2>&1"; then remote "$ip" "sudo /usr/local/bin/k3s-uninstall.sh" || true; fi
  remote "$ip" "sudo rm -f /etc/rancher/k3s/config.yaml" || true
  remote "$ip" "curl -sfL https://get.k3s.io | sudo env K3S_URL='https://$VIP:6443' K3S_TOKEN='$TOKEN' INSTALL_K3S_VERSION='$K3S_VERSION' INSTALL_K3S_EXEC='agent --node-ip=$ip --flannel-iface=$INTERFACE' sh -"
  wait_remote "$ip" "systemctl is-active --quiet k3s-agent" "k3s-agent attivo" 300
done

remote "${CP_IPS[0]}" "sudo cat /etc/rancher/k3s/k3s.yaml" > "$KUBECONFIG_OUT"
chmod 600 "$KUBECONFIG_OUT"
python3 - "$KUBECONFIG_OUT" "$VIP" <<'PY'
import sys
path, vip = sys.argv[1:]
with open(path) as f: data = f.read()
with open(path, 'w') as f: f.write(data.replace('127.0.0.1', vip))
PY
export KUBECONFIG="$KUBECONFIG_OUT"
kubectl wait --for=condition=Ready nodes --all --timeout=10m
kubectl get nodes -o wide
log "Cluster K3s operativo. Kubeconfig: $KUBECONFIG_OUT"
