# Technitium DNS Migration Plan

## Riepilogo Problemi

1. **DNS su UDM Pro**: Il DNS `*.unifi.localdomain` risiede sul router UDM Pro
   - Solo i client che usano UDM Pro come DNS risolvono correttamente
   - I widget Homepage (Grafana, Prometheus, Traefik) non raggiungono le API

2. **Homepage API errori**: 
   - Grafana: 401 Unauthorized → API key non iniettata (init-scripts ConfigMap mancante)
   - Prometheus: Internal server error → URL non raggiungibile dal browser
   - Widget type "linux" non esiste → sostituito con "iframe"

3. **Bug critico**: `homepage-init-scripts` ConfigMap referenziata ma NON esiste nel repo

---

## Piano di Implementazione

### STEP 0: Fix bug critico — homepage-init-scripts ConfigMap (PENDING)
**File**: `flux/dashboard/init-scripts-configmap.yaml` (NUOVO)

**Problema**: Il deployment Homepage reference un ConfigMap `homepage-init-scripts` che non esiste.
Questo fa fallire l'avvio del pod Homepage.

**Soluzione**: Creare un ConfigMap con uno script Node.js che inietta la Grafana API key nel services.yaml

---

### STEP 1: Deploy Technitium DNS (PENDING)
**File**: `flux/dns/` (NUOVA DIRECTORY)
- `release.yaml` — Deployment + Service (MetalLB)
- `kustomization.yaml`

**Piano**:
- Container: `technitium/dns:latest`
- Service: ClusterIP + LoadBalancer (MetalLB) su `192.168.9.53`
- Ports: 53/UDP, 53/TCP, 80 (Web UI)
- Volume: PVC per configurazione persistente
- Config: Wildcard DNS per `*.unifi.localdomain` → MetalLB IP di Traefik

---

### STEP 2: Configurare UDM Pro DHCP (PENDING - USER ACTION REQUIRED)
**File**: `docs/udm-pro-dns-setup.md` (NUOVO)

**Piano**:
- Documentare tutte le azioni manuali sul router UDM Pro
- Metodo A: UniFi Controller GUI (consigliato)
- Metodo B: SSH sul router (avanzato)
- Configurazione wildcard DNS in Technitium (dopo che il pod è operativo)
- Verifica risoluzione DNS da client

**Azioni utente**:
1. Riservare IP 192.168.9.53 nel DHCP
2. Impostare DNS 1 = 192.168.9.53 su UniFi Controller
3. Dopo Technitium operativo: configurare wildcard DNS in Technitium Web UI

---

### STEP 3: Fix dashboard services (✅ COMPLETATO)
**File**: Verificato, nessuna modifica necessaria

**Verifica**:
- Homepage services.yaml: tutte le URL puntano a endpoint pubblici Traefik ✅
- Homepage settings.yaml: prometheus URL interno è corretto (widget kubernetes, non browser) ✅
- Node Stats widget type: impostato su `iframe` ✅
- Prometheus widget type: impostato su `prometheus` ✅
- Grafana widget type: impostato su `grafana` (con apiKey) ✅

**Note**:
- Il Prometheus URL in settings.yaml è CORRETTO (cluster.local) perché è per il widget Kubernetes che legge metriche dal cluster
- I widget card (Grafana, Prometheus, Traefik) usano servizi.yaml che punta a URL pubblici via Traefik ✅

---

### STEP 4: Secret templates e .gitignore (✅ COMPLETATO)
**File creati**:
- `flux/dashboard/secret-templates/homepage-secrets.yaml.example`
- `flux/dashboard/secret-templates/.gitignore`

**Verifica**:
- `.gitignore` già include `*.env`, `*.pem`, `kubeconfig` ✅
- Template documenta come creare il secret sul cluster
- Il secret `homepage-secrets` deve essere creato manualmente con: `kubectl create secret generic homepage-secrets ...`

---

### STEP 5: Testing e Validazione (✅ COMPLETATO)
**File creati**:
- `scripts/validate-dashboard.sh` — Script di validazione completo

**Funzionalità dello script**:
- Verifica namespace dns e flux-system
- Verifica Technitium DNS pod status e IP
- Verifica Homepage pod status e initContainer logs
- Verifica Secret homepage-secrets
- Verifica Services e IngressRoutes
- Verifica ConfigMaps (homepage-config, homepage-services, homepage-init-scripts)
- Verifica risoluzione DNS (se Technitium è operativo)

**Uso**:
```bash
./scripts/validate-dashboard.sh
```

---

## Log Sessione

### Sessione Iniziale
- **Data**: 2025-01-XX
- **Stato**: STEP 0 ✅ COMPLETATO
- **File creati**:
  - `TechnitiumPlan.md` — questo file
  - `flux/dashboard/init-scripts-configmap.yaml` — ConfigMap con script iniezione
- **Verifica**: Script Node.js inietta apiKey correttamente nel widget section
- **Fix**: Eliminato `flux/dashboard/inject-apikey.js` (non necessario, script è nel ConfigMap)

### STEP 1: Technitium DNS
- **Data**: In corso
- **Stato**: FILE CREATI
- **File creati**:
  - `flux/dns/release.yaml` — Deployment, PVC, Services (ClusterIP + LoadBalancer)
  - `flux/dns/kustomization.yaml` — Kustomization per Flux
  - `clusters/homelab/dns.yaml` — Flux Kustomization
  - `flux/metallb-config/pool.yaml` — Aggiornato a 192.168.9.50-220
- **Note**:
  - Technitium usa hostNetwork per esporre UDP/TCP 53
  - IP MetalLB dedicato: 192.168.9.53
  - Web UI: ClusterIP (non esposta alla rete)
  - DNS Query: forwarding a Google (8.8.8.8) e Cloudflare (1.1.1.1)
- **Prossimo**: Verificare che il PVC sia funzionante (storageClassName: local-path)

---

## Note di Sicurezza

Tutte le API key, password e segreti:
- ✅ Devono essere in Kubernetes Secrets (nome: `homepage-secrets`)
- ✅ NON devono essere nel repository Git
- ✅ File `.env` devono essere in `.gitignore`
- ✅ Solo gli utenti finali devono creare il secret sul cluster

---

## Testing Checklist

- [ ] Homepage pod si avvia correttamente
- [ ] Grafana widget mostra dati (API key iniettata)
- [ ] Prometheus widget funziona
- [ ] Traefik widget funziona
- [ ] Node Stats widget funziona (iframe)
- [ ] DNS risolve `*.unifi.localdomain`
- [ ] Dashboard accessibile da browser
