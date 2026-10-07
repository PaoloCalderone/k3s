#!/bin/bash
# updateLocalHosts.sh — Updates /etc/hosts with all k3s services
# Reads the IngressRoutes from the cluster and writes the local DNS records.
#
# Usage:
#   ./scripts/updateLocalHosts.sh  (generates updateHosts.sh)
#   sudo ./scripts/updateHosts.sh  (applies the changes)
#
# Optional variable: KUBECONFIG=/path/to/kubeconfig ./scripts/updateLocalHosts.sh

set -euo pipefail

# ---- Configurazione ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG="${KUBECONFIG:-/Users/paolo/Documents/Codex/k3s/kubeconfig}"
HOSTS_FILE="/etc/hosts"
MARKER="# K3s homelab HTTPS"
TRAEFIK_IP="192.168.9.200"

# ---- Fetch all services exposed via Traefik ----
JSON_DATA=$(kubectl --kubeconfig "$KUBECONFIG" get ingressroutes -A -o json 2>/dev/null)

if [ -z "$JSON_DATA" ]; then
  echo "No IngressRoutes found in the cluster."
  exit 1
fi

SERVICES=$(echo "$JSON_DATA" | python3 "${SCRIPT_DIR}/extractDomains.py")

if [ -z "$SERVICES" ]; then
  echo "No IngressRoutes found in the cluster."
  exit 1
fi

echo "Services found: $(echo "$SERVICES" | wc -w)"
echo "   ${SERVICES}"

# ---- Generate the update script for /etc/hosts ----
HOSTS_SCRIPT="${SCRIPT_DIR}/updateHosts.sh"

# Use an unquoted heredoc to expand $SERVICES with the actual value
# Note: the markdown code block should use $$ for literal dollars in the docs
cat > "$HOSTS_SCRIPT" << EOF
#!/bin/bash
set -euo pipefail
HOSTS_FILE="/etc/hosts"
MARKER="$MARKER"
TRAEFIK_IP="$TRAEFIK_IP"
SERVICES="$SERVICES"
NEW_LINE="\${TRAEFIK_IP}  \${SERVICES}"

# Backup
cp "\$HOSTS_FILE" "\${HOSTS_FILE}.bak.\$(date +%Y%m%d_%H%M%S)"

# Remove old k3s lines
grep -v "unifi\\.localdomain" "\$HOSTS_FILE" > "\${HOSTS_FILE}.tmp"
mv "\${HOSTS_FILE}.tmp" "\$HOSTS_FILE"

# Find comment line
LINE_NUM=\$(grep -n "\$MARKER" "\$HOSTS_FILE" | tail -1 | cut -d: -f1)

if [ -n "\$LINE_NUM" ]; then
  awk -v marker="\$MARKER" -v newlines="\$NEW_LINE" '
    \$0 ~ "^" marker {
      print \$0
      print newlines
      print newlines
      next
    }
    { print }
  ' "\$HOSTS_FILE" > "\${HOSTS_FILE}.tmp"
  mv "\${HOSTS_FILE}.tmp" "\$HOSTS_FILE"
  echo "hosts modified: lines \$((LINE_NUM + 1)) and \$((LINE_NUM + 2))"
else
  echo "" >> "\$HOSTS_FILE"
  echo "\$MARKER" >> "\$HOSTS_FILE"
  echo "\$NEW_LINE" >> "\$HOSTS_FILE"
  echo "hosts modified: new section added"
fi

echo ""
for svc in \$SERVICES; do
  echo "   • https://\${svc}"
done
EOF

chmod +x "$HOSTS_SCRIPT"

echo ""
echo "Generated hosts script: $HOSTS_SCRIPT"
echo ""
echo "Run with:"
echo ""
echo "  sudo $HOSTS_SCRIPT"
echo ""
