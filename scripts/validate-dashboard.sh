#!/bin/bash
# validate-dashboard.sh — Verify that Homepage and Technitium are operational
#
# Usage:
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

# STEP 1: Verify dns namespace
echo "--- DNS Namespace ---"
if kubectl get namespace dns >/dev/null 2>&1; then
  info "Namespace dns exists"
else
  error "Namespace dns does not exist"
fi

# STEP 2: Verify Technitium deployment
echo ""
echo "--- Technitium DNS ---"
DNS_POD=$(kubectl get pods -n dns -l app=technitium-dns -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$DNS_POD" ]; then
  DNS_STATUS=$(kubectl get pod -n dns "$DNS_POD" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  if [ "$DNS_STATUS" = "Running" ]; then
    info "Technitium DNS pod is Running"
  else
    error "Technitium DNS pod is $DNS_STATUS"
  fi
else
  error "Technitium DNS pod not found"
fi

DNS_IP=$(kubectl get svc -n dns technitium-dns -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [ -n "$DNS_IP" ]; then
  info "Technitium DNS IP: $DNS_IP"
else
  warn "Technitium DNS IP not yet assigned (MetalLB in progress)"
fi

# STEP 3: Verify homepage namespace
echo ""
echo "--- Homepage ---"
if kubectl get namespace flux-system >/dev/null 2>&1; then
  info "Namespace flux-system exists"
else
  error "Namespace flux-system does not exist"
fi

# STEP 4: Verify Homepage deployment
HP_POD=$(kubectl get pods -n flux-system -l app=homepage -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$HP_POD" ]; then
  HP_STATUS=$(kubectl get pod -n flux-system "$HP_POD" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  if [ "$HP_STATUS" = "Running" ]; then
    info "Homepage pod is Running"
  else
    error "Homepage pod is $HP_STATUS"
    HP_READY=$(kubectl get pod -n flux-system "$HP_POD" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "unknown")
    if [ "$HP_READY" != "True" ]; then
      echo "  Conditions: $(kubectl get pod -n flux-system "$HP_POD" -o jsonpath='{range .status.conditions[*]}{.type}:{.status} {' 2>/dev/null; echo '}')"
    fi
  fi
else
  error "Homepage pod not found"
fi

# STEP 5: Verify initContainer logs
echo ""
echo "--- InitContainer Logs ---"
if [ -n "$HP_POD" ]; then
  INIT_LOGS=$(kubectl logs -n flux-system "$HP_POD" -c init-config --tail=10 2>/dev/null || echo "No logs")
  if echo "$INIT_LOGS" | grep -q "apiKey"; then
    info "Grafana API key injection completed"
  elif echo "$INIT_LOGS" | grep -q "ERROR"; then
    error "Error in initContainer: $(echo "$INIT_LOGS" | grep ERROR)"
  fi
  echo "  Last init logs: $(echo "$INIT_LOGS" | tail -2)"
fi

# STEP 6: Verify Secret
echo ""
echo "--- Secrets ---"
if kubectl get secret -n flux-system homepage-secrets >/dev/null 2>&1; then
  info "Secret homepage-secrets exists"
  KEY_EXISTS=$(kubectl get secret -n flux-system homepage-secrets -o jsonpath='{.data.grafana-apikey}' 2>/dev/null || echo "")
  if [ -n "$KEY_EXISTS" ]; then
    info "Grafana API key configured"
  else
    error "Grafana API key not set in the secret"
  fi
else
  error "Secret homepage-secrets does NOT exist"
  echo "  To create the secret:"
  echo "  kubectl create secret generic homepage-secrets \\"
  echo "    --namespace=flux-system \\"
  echo "    --from-literal=grafana-apikey='<your-api-key>'"
fi

# STEP 7: Verify services
echo ""
echo "--- Homepage Services ---"
for svc in grafana prometheus traefik homepage node-stats; do
  SVC_STATUS=$(kubectl get svc -n flux-system "$svc" 2>/dev/null && echo "OK" || echo "NOT FOUND")
  if [ "$SVC_STATUS" = "OK" ]; then
    info "Service $svc exists"
  else
    warn "Service $svc not found (may be in another namespace)"
  fi
done

# STEP 8: Verify IngressRoutes
echo ""
echo "--- IngressRoutes Homepage ---"
INGRESS_COUNT=$(kubectl get ingressroutes -A -l gethomepage.dev/enabled=true 2>/dev/null | grep -c "Rule" || echo "0")
if [ "$INGRESS_COUNT" -gt 0 ]; then
  info "Found $INGRESS_COUNT IngressRoutes with Homepage annotations"
else
  warn "No IngressRoute with Homepage annotations found"
fi

# STEP 9: Verify ConfigMaps
echo ""
echo "--- ConfigMaps ---"
for cm in homepage-config homepage-services homepage-init-scripts; do
  if kubectl get configmap -n flux-system "$cm" >/dev/null 2>&1; then
    info "ConfigMap $cm exists"
  else
    error "ConfigMap $cm does NOT exist"
  fi
done

# STEP 10: Verify DNS resolution (if Technitium is operational)
echo ""
echo "--- DNS Resolution Test ---"
if [ -n "$DNS_IP" ]; then
  for domain in grafana.unifi.localdomain prometheus.unifi.localdomain homepage.unifi.localdomain; do
    if nslookup "$domain" "$DNS_IP" >/dev/null 2>&1; then
      info "$domain → DNS resolves"
    else
      warn "$domain → DNS does not respond yet"
    fi
  done
else
  warn "DNS test skipped (Technitium IP not yet assigned)"
fi

# Summary
echo ""
echo "═══════════════════════════════════════════"
if [ $ERRORS -eq 0 ]; then
  printf "${GREEN}VALIDATION COMPLETED - No errors${NC}\n"
  if [ $WARNINGS -gt 0 ]; then
    printf "${YELLOW}%d warning(s)${NC}\n" $WARNINGS
  fi
else
  printf "${RED}VALIDATION FAILED - %d error(s), %d warning(s)${NC}\n" $ERRORS $WARNINGS
fi
echo "═══════════════════════════════════════════"

exit $ERRORS
