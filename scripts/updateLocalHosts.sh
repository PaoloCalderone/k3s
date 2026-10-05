#!/bin/bash
# updateLocalHosts.sh — Aggiorna /etc/hosts con tutti i servizi k3s
# Legge le IngressRoute dal cluster e scrive i record DNS locali.
#
# Uso:
#   ./scripts/updateLocalHosts.sh  (genera updateHosts.sh)
#   sudo ./scripts/updateHosts.sh  (applica le modifiche)
#
# Variabile opzionale: KUBECONFIG=/percorso/kubeconfig ./scripts/updateLocalHosts.sh

set -euo pipefail

# ---- Configurazione ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG="${KUBECONFIG:-/Users/paolo/Documents/Codex/k3s/kubeconfig}"
HOSTS_FILE="/etc/hosts"
MARKER="# K3s homelab HTTPS"
TRAEFIK_IP="192.168.9.200"

# ---- Recupera tutti i servizi esposti tramite Traefik ----
JSON_DATA=$(kubectl --kubeconfig "$KUBECONFIG" get ingressroutes -A -o json 2>/dev/null)

if [ -z "$JSON_DATA" ]; then
  echo "⚠️  Nessuna IngressRoute trovata nel cluster."
  exit 1
fi

SERVICES=$(echo "$JSON_DATA" | python3 "${SCRIPT_DIR}/extractDomains.py")

if [ -z "$SERVICES" ]; then
  echo "⚠️  Nessuna IngressRoute trovata nel cluster."
  exit 1
fi

echo "📡 Servizi trovati: $(echo "$SERVICES" | wc -w)"
echo "   ${SERVICES}"

# ---- Genera lo script di update per /etc/hosts ----
HOSTS_SCRIPT="${SCRIPT_DIR}/updateHosts.sh"

# Usa un heredoc non-quoted per espandere $SERVICES con il valore effettivo
# Nota: il markdown code block dovrebbe usare $$ per i dollari letterali inเอกสาร
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

# Rimuovi vecchie righe k3s
grep -v "unifi\\.localdomain" "\$HOSTS_FILE" > "\${HOSTS_FILE}.tmp"
mv "\${HOSTS_FILE}.tmp" "\$HOSTS_FILE"

# Trova linea commento
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
  echo "✅ hosts modificato: righe \$((LINE_NUM + 1)) e \$((LINE_NUM + 2))"
else
  echo "" >> "\$HOSTS_FILE"
  echo "\$MARKER" >> "\$HOSTS_FILE"
  echo "\$NEW_LINE" >> "\$HOSTS_FILE"
  echo "✅ hosts modificato: nuova sezione aggiunta"
fi

echo ""
for svc in \$SERVICES; do
  echo "   • https://\${svc}"
done
EOF

chmod +x "$HOSTS_SCRIPT"

echo ""
echo "💾 Script hosts generato: $HOSTS_SCRIPT"
echo ""
echo "⚠️  Esegui con:"
echo ""
echo "  sudo $HOSTS_SCRIPT"
echo ""
