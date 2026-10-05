#!/bin/bash
# ============================================================
# validate-dashboard.sh — Verifica HomePages Dashboard su k3s
# Uso: bash scripts/validate-dashboard.sh
# ============================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass()  { echo -e "${GREEN}✅ $*${NC}"; }
fail()  { echo -e "${RED}❌ $*${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $*${NC}"; }

echo "═══════════════════════════════════════════════════════════"
echo "  🧪 Validazione Dashboard Homepage — K3S Cluster"
echo "═══════════════════════════════════════════════════════════"
echo ""

# 1. Verifica HomePages pod
echo "── 1. Pod Homepage ──────────────────────────────────────"
if kubectl get pods -n default -l app.kubernetes.io/name=homepage 2>/dev/null | grep -q Running; then
    pass "Pod Homepage è Running"
    kubectl get pods -n default -l app.kubernetes.io/name=homepage
else
    fail "Pod Homepage NON in Running (attendi Flux deployment)"
fi
echo ""

# 2. Verifica test-service
echo "── 2. Test Service ───────────────────────────────────────"
if kubectl get pods -n test 2>/dev/null | grep -q Running; then
    pass "Pod test-page è Running"
    kubectl get pods -n test
else
    warn "Pod test-page NON in Running (attendi Flux deployment)"
fi
echo ""

# 3. Verifica IngressRoute con annotations Homepage
echo "── 3. IngressRoute scoperte da Homepage ──────────────────"
FOUND=0
kubectl get ingressroutes -A -o yaml 2>/dev/null | grep -B3 "gethomepage.dev/enabled: \"true\"" 2>/dev/null | while read -r line; do
    FOUND=1
    echo "  $line"
done

if kubectl get ingressroutes -A 2>/dev/null | grep -q gethomepage; then
    pass "IngressRoute con annotations Homepage trovate"
    kubectl get ingressroutes -A | grep -A1 gethomepage
else
    fail "Nessuna IngressRoute con annotations Homepage trovata"
    echo "  Assicurati che le tue IngressRoute abbiano:"
    echo "    gethomepage.dev/enabled: \"true\""
fi
echo ""

# 4. Verifica via curl (locale)
echo "── 4. Test connessività servizi ──────────────────────────"

# Dashboard
if curl -skfo /dev/null --max-time 5 "https://dashboard.unifi.localdomain" 2>/dev/null; then
    pass "Dashboard (dashboard.unifi.localdomain) — raggiungibile"
else
    warn "Dashboard (dashboard.unifi.localdomain) — NON raggiungibile (DNS o TLS)"
fi

# Test
if curl -skfo /dev/null --max-time 5 "https://test.unifi.localdomain" 2>/dev/null; then
    pass "Test (test.unifi.localdomain) — raggiungibile"
else
    warn "Test (test.unifi.localdomain) — NON raggiungibile (DNS o TLS)"
fi

# Grafana
if curl -skfo /dev/null --max-time 5 "https://grafana.unifi.localdomain" 2>/dev/null; then
    pass "Grafana (grafana.unifi.localdomain) — raggiungibile"
else
    warn "Grafana (grafana.unifi.localdomain) — NON raggiungibile (DNS o TLS)"
fi

# Prometheus
if curl -skfo /dev/null --max-time 5 "https://prometheus.unifi.localdomain" 2>/dev/null; then
    pass "Prometheus (prometheus.unifi.localdomain) — raggiungibile"
else
    warn "Prometheus (prometheus.unifi.localdomain) — NON raggiungibile (DNS o TLS)"
fi

# Alertmanager
if curl -skfo /dev/null --max-time 5 "https://alertmanager.unifi.localdomain" 2>/dev/null; then
    pass "Alertmanager (alertmanager.unifi.localdomain) — raggiungibile"
else
    warn "Alertmanager (alertmanager.unifi.localdomain) — NON raggiungibile (DNS o TLS)"
fi
echo ""

# 5. Lista completa delle card che Homepage mostrerà
echo "── 5. Riepilogo card previste su Dashboard ───────────────"
kubectl get ingressroutes -A -o yaml 2>/dev/null | grep -E "(name:|gethomepage.dev/)" | while read -r line; do
    echo "  $line"
done | sort -u
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "  ✅ Validazione completata"
echo ""
echo "  Per accedere alla dashboard: https://dashboard.unifi.localdomain"
echo "  Per dettagli: docs/dashboard.md"
echo "═══════════════════════════════════════════════════════════"
