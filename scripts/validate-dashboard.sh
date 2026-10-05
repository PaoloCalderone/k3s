#!/bin/bash
# validate-dashboard.sh — Verifica che Homepage e Technitium siano operativi
#
# Uso:
#   ./scripts/validate-dashboard.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

info() { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
error() { printf "${RED}[FAIL]${NC} %s\n" "$1"; ERRORS=$((ERRORS+1)); }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; WARNINGS=$((WARNINGS+1)); }

echo "═══════════════════════════════════════════"
echo "  Homepage + Technitium DNS Validation"
echo "═══════════════════════════════════════════"
echo ""

# STEP 1: Verificare namespace dns
echo "--- DNS Namespace ---"
if kubectl get namespace dns >/dev/null 2>&1; then
  info "Namespace dns esiste"
else
  error "Namespace dns non esiste"
fi

# STEP 2: Verificare deployment Technitium
echo ""
echo "--- Technitium DNS ---"
DNS_POD=$(kubectl get pods -n dns -l app=technitium-dns -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$DNS_POD" ]; then
  DNS_STATUS=$(kubectl get pod -n dns "$DNS_POD" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  if [ "$DNS_STATUS" = "Running" ]; then
    info "Technitium DNS pod è Running"
  else
    error "Technitium DNS pod è $DNS_STATUS"
  fi
else
  error "Technitium DNS pod non trovato"
fi

DNS_IP=$(kubectl get svc -n dns technitium-dns -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [ -n "$DNS_IP" ]; then
  info "Technitium DNS IP: $DNS_IP"
else
  warn "Technitium DNS IP non ancora assegnato (MetalLB in corso)"
fi

# STEP 3: Verificare namespace homepage
echo ""
echo "--- Homepage ---"
if kubectl get namespace flux-system >/dev/null 2>&1; then
  info "Namespace flux-system esiste"
else
  error "Namespace flux-system non esiste"
fi

# STEP 4: Verificare deployment Homepage
HP_POD=$(kubectl get pods -n flux-system -l app=homepage -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$HP_POD" ]; then
  HP_STATUS=$(kubectl get pod -n flux-system "$HP_POD" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  if [ "$HP_STATUS" = "Running" ]; then
    info "Homepage pod è Running"
  else
    error "Homepage pod è $HP_STATUS"
    HP_READY=$(kubectl get pod -n flux-system "$HP_POD" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "unknown")
    if [ "$HP_READY" != "True" ]; then
      echo "  Condizioni: $(kubectl get pod -n flux-system "$HP_POD" -o jsonpath='{range .status.conditions[*]}{.type}:{.status} {' 2>/dev/null; echo '}')"
    fi
  fi
else
  error "Homepage pod non trovato"
fi

# STEP 5: Verificare initContainer logs
echo ""
echo "--- InitContainer Logs ---"
if [ -n "$HP_POD" ]; then
  INIT_LOGS=$(kubectl logs -n flux-system "$HP_POD" -c init-config --tail=10 2>/dev/null || echo "No logs")
  if echo "$INIT_LOGS" | grep -q "apiKey"; then
    info "Grafana API key injection completato"
  elif echo "$INIT_LOGS" | grep -q "ERROR"; then
    error "Errore in initContainer: $(echo "$INIT_LOGS" | grep ERROR)"
  fi
  echo "  Ultimi log init: $(echo "$INIT_LOGS" | tail -2)"
fi

# STEP 6: Verificare Secret
echo ""
echo "--- Secrets ---"
if kubectl get secret -n flux-system homepage-secrets >/dev/null 2>&1; then
  info "Secret homepage-secrets esiste"
  KEY_EXISTS=$(kubectl get secret -n flux-system homepage-secrets -o jsonpath='{.data.grafana-apikey}' 2>/dev/null || echo "")
  if [ -n "$KEY_EXISTS" ]; then
    info "Grafana API key configurata"
  else
    error "Grafana API key non impostata nel secret"
  fi
else
  error "Secret homepage-secrets NON esiste"
  echo "  Per creare il secret:"
  echo "  kubectl create secret generic homepage-secrets \\"
  echo "    --namespace=flux-system \\"
  echo "    --from-literal=grafana-apikey='<tua-api-key>'"
fi

# STEP 7: Verificare servizi
echo ""
echo "--- Servizi Homepage ---"
for svc in grafana prometheus traefik homepage node-stats; do
  SVC_STATUS=$(kubectl get svc -n flux-system "$svc" 2>/dev/null && echo "OK" || echo "NOT FOUND")
  if [ "$SVC_STATUS" = "OK" ]; then
    info "Service $svc esiste"
  else
    warn "Service $svc non trovato (potrebbe essere in un altro namespace)"
  fi
done

# STEP 8: Verificare IngressRoutes
echo ""
echo "--- IngressRoutes Homepage ---"
INGRESS_COUNT=$(kubectl get ingressroutes -A -l gethomepage.dev/enabled=true 2>/dev/null | grep -c "Rule" || echo "0")
if [ "$INGRESS_COUNT" -gt 0 ]; then
  info "Trovate $INGRESS_COUNT IngressRoutes con annotations Homepage"
else
  warn "Nessuna IngressRoute con annotations Homepage trovata"
fi

# STEP 9: Verificare ConfigurMap
echo ""
echo "--- ConfigMaps ---"
for cm in homepage-config homepage-services homepage-init-scripts; do
  if kubectl get configmap -n flux-system "$cm" >/dev/null 2>&1; then
    info "ConfigMap $cm esiste"
  else
    error "ConfigMap $cm NON esiste"
  fi
done

# STEP 10: Verificare risoluzione DNS (se Technitium è operativo)
echo ""
echo "--- DNS Resolution Test ---"
if [ -n "$DNS_IP" ]; then
  for domain in grafana.unifi.localdomain prometheus.unifi.localdomain homepage.unifi.localdomain; do
    if nslookup "$domain" "$DNS_IP" >/dev/null 2>&1; then
      info "$domain → DNS resolves ✅"
    else
      warn "$domain → DNS non risponde ancora"
    fi
  done
else
  warn "DNS test skipped (Technitium IP non ancora assegnato)"
fi

# Riepilogo
echo ""
echo "═══════════════════════════════════════════"
if [ $ERRORS -eq 0 ]; then
  printf "${GREEN}✅ VALIDAZIONE COMPLETATA - Nessun errore${NC}\n"
  if [ $WARNINGS -gt 0 ]; then
    printf "${YELLOW}⚠️  %d warning(s)${NC}\n" $WARNINGS
  fi
else
  printf "${RED}❌ VALIDAZIONE FALLITA - %d errore(i), %d warning(s)${NC}\n" $ERRORS $WARNINGS
fi
echo "═══════════════════════════════════════════"

exit $ERRORS
