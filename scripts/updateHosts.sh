#!/bin/bash
set -euo pipefail
HOSTS_FILE="/etc/hosts"
MARKER="# K3s homelab HTTPS"
TRAEFIK_IP="192.168.9.200"
SERVICES="alertmanager.unifi.localdomain grafana.unifi.localdomain homepage.unifi.localdomain prometheus.unifi.localdomain traefik.unifi.localdomain "
NEW_LINE="${TRAEFIK_IP}  ${SERVICES}"

# Backup
cp "$HOSTS_FILE" "${HOSTS_FILE}.bak.$(date +%Y%m%d_%H%M%S)"

# Rimuovi vecchie righe k3s
grep -v "unifi\.localdomain" "$HOSTS_FILE" > "${HOSTS_FILE}.tmp"
mv "${HOSTS_FILE}.tmp" "$HOSTS_FILE"

# Trova linea commento
LINE_NUM=$(grep -n "$MARKER" "$HOSTS_FILE" | tail -1 | cut -d: -f1)

if [ -n "$LINE_NUM" ]; then
  awk -v marker="$MARKER" -v newlines="$NEW_LINE" '
    $0 ~ "^" marker {
      print $0
      print newlines
      print newlines
      next
    }
    { print }
  ' "$HOSTS_FILE" > "${HOSTS_FILE}.tmp"
  mv "${HOSTS_FILE}.tmp" "$HOSTS_FILE"
  echo "✅ hosts modificato: righe $((LINE_NUM + 1)) e $((LINE_NUM + 2))"
else
  echo "" >> "$HOSTS_FILE"
  echo "$MARKER" >> "$HOSTS_FILE"
  echo "$NEW_LINE" >> "$HOSTS_FILE"
  echo "✅ hosts modificato: nuova sezione aggiunta"
fi

echo ""
for svc in $SERVICES; do
  echo "   • https://${svc}"
done
