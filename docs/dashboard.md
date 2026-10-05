# Homepage Dashboard — Guida all'uso

Dashboard Homepage esposta su `dashboard.unifi.localdomain` scopre automaticamente tutti i servizi del cluster k3s esposti tramite Traefik.

## ⚡ Come funziona

Homepage legge le annotations `gethomepage.dev/` dalle tue Traefik IngressRoute e crea automaticamente una card per ogni servizio. Quando crei un nuovo servizio, basta aggiungere le annotations e far push sul Git repo — Flux aggiorna Homepage, e la nuova card appare senza riavvii.

---

## 📋 Per aggiungere un nuovo servizio

### 1. Crea o aggiorna l'IngressRoute con le annotations

```yaml
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: casa-assistent
  namespace: flux-system          # o il namespace del tuo servizio
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/name: "Casa Assistent"
    gethomepage.dev/description: "Domotica e automazioni"
    gethomepage.dev/group: "Infrastruttura"
    gethomepage.dev/icon: "home-assistant"
    gethomepage.dev/widget.type: "home-assistant"
spec:
  entryPoints:
    - websecure
  tls:
    secretName: unifi-localdomain-tls
  routes:
    - match: Host(`casa.unifi.localdomain`)
      kind: Rule
      services:
        - name: casa-assistent-service
          port: 8123
```

### 2. Annotations obbligatorie

| Annotation | Obbligatorio? | Descrizione |
|------------|---------------|-------------|
| `gethomepage.dev/enabled` | **SÌ** | `"true"` per abilitare la scoperta automatica |

### 3. Annotations consigliate

| Annotation | Descrizione |
|------------|-------------|
| `gethomepage.dev/name` | Nome visualizzato sulla card |
| `gethomepage.dev/description` | Sottotitolo sotto il nome |
| `gethomepage.dev/group` | Categoria in cui raggruppare il servizio |
| `gethomepage.dev/icon` | Icona da Font Awesome / Heroicons / Material Symbols |

### 4. Widgets live (opzionali)

Alcuni servizi mostrano dati live invece dell'immagine statica:

| Widget | Descrizione |
|--------|-------------|
| `grafana` | Snapshot dashboard Grafana |
| `prometheus` | Metriche e allarmi Prometheus |
| `alertmanager` | Stato allarmi Alertmanager |
| `home-assistant` | Dispositivi Casa Assistent |
| `docker` | Container in esecuzione |
| `kubernetes` | Stato del cluster k3s |

### 5. Icone disponibili

Homepage supporta icone da **Font Awesome 6**, **Heroicons**, **Lucide** e **Material Symbols**.

Esempi:
```
grafana, prometheus, alert, docker, kubernetes, nginx,
home-assistant, sonarr, radarr, overseerr, plex, qbittorrent,
linux, cloud, database, server, shield, code
```

Lista completa: <https://gethomepage.dev/latest/config-items/icons>

---

## 📦 Esempi pratici

### Esempio 1 — Casa Assistent

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: casa-assistent
  namespace: flux-system
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/name: "Casa Assistent"
    gethomepage.dev/description: "Domotica e automazioni"
    gethomepage.dev/group: "Infrastruttura"
    gethomepage.dev/icon: "home-assistant"
    gethomepage.dev/widget.type: "home-assistant"
spec:
  entryPoints:
    - websecure
  tls:
    secretName: unifi-localdomain-tls
  routes:
    - match: Host(`casa.unifi.localdomain`)
      kind: Rule
      services:
        - name: casa-assistent
          port: 8123
```

### Esempio 2 — Navidrome (musica)

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: navidrome
  namespace: flux-system
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/name: "Navidrome"
    gethomepage.dev/description: "Server musica"
    gethomepage.dev/group: "Infrastruttura"
    gethomepage.dev/icon: "music"
    gethomepage.dev/widget.type: "navidrome"
spec:
  entryPoints:
    - websecure
  tls:
    secretName: unifi-localdomain-tls
  routes:
    - match: Host(`navidrome.unifi.localdomain`)
      kind: Rule
      services:
        - name: navidrome
          port: 4533
```

### Esempio 3 — Storage NFS

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: nfs-storage
  namespace: flux-system
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/name: "NFS Storage"
    gethomepage.dev/description: "Archiviazione rete"
    gethomepage.dev/group: "Storage"
    gethomepage.dev/icon: "database"
spec:
  entryPoints:
    - websecure
  tls:
    secretName: unifi-localdomain-tls
  routes:
    - match: Host(`storage.unifi.localdomain`)
      kind: Rule
      services:
        - name: nfs-storage
          port: 8080
```

---

## ⚠️ Cosa NON fare

- **Non annotare la rotta di Homepage stessa** con `gethomepage.dev/enabled: "true"`. Homepage riconosce `dashboard.unifi.localdomain` come il dashboard stesso e lo nasconde dalle card. Se lo annoti, la dashboard mostrerà sé stessa come una delle sue stesse card.

  ```yaml
  # ✅ CORRETTO — pagina vuota per la propria rotta
  name: homepage
  namespace: flux-system

  # ❌ SBAGLIATO — mostra sé stessa come card
  name: homepage
  annotations:
    gethomepage.dev/enabled: "true"
  ```

---

## 🔧 Servizi già configurati

Attualmente scoperti automaticamente tramite le annotations sulle IngressRoute esistenti:

| Servizio | URL | Gruppo | Icona | Widget |
|----------|-----|--------|-------|--------|
| Grafana | `grafana.unifi.localdomain` | Monitoring | `grafana` | ✅ Grafana |
| Prometheus | `prometheus.unifi.localdomain` | Monitoring | `prometheus` | ✅ Prometheus |
| Alertmanager | `alertmanager.unifi.localdomain` | Monitoring | `alert` | ✅ Alertmanager |

## 🧪 Servizio di test

È stato creato un servizio di test per verificare il funzionamento:

| Servizio | URL | Gruppo | Icona |
|----------|-----|--------|-------|
| **Test** | `test.unifi.localdomain` | Infrastruttura | `flask` |

Il servizio di test è un nginx con una pagina HTML custom che conferma che la scoperta automatica di Homepage funziona correttamente. Quando accedi a `https://dashboard.unifi.localdomain`, dovresti vedere una card "Test" nel gruppo "Infrastruttura" che punta a `test.unifi.localdomain`.

---

## 🧪 Testare la configurazione

### Passo 1 — Verifica deployment

```bash
# Controlla che il pod Homepage sia in Running
kubectl get pods -n default -l app.kubernetes.io/name=homepage

# Controlla le risorse Traefik scoperte
kubectl get ingressroutes -A | grep -A3 gethomepage
```

### Passo 2 — Testa il servizio di test

```bash
# Verifica che il test-service sia deployato
kubectl get pods -n test

# Accedi al servizio di test direttamente
curl -k https://test.unifi.localdomain 2>/dev/null | head -20

# Verifica che la card "Test" appaia sulla dashboard
# Apri https://dashboard.unifi.localdomain
```

### Passo 3 — Verifica la scoperta automatica

```bash
# Tutte le IngressRoute con annotations Homepage
kubectl get ingressroutes -A -o yaml | grep -B2 -A10 "gethomepage.dev"

# Controlla i log di Homepage per errori di scoperta
kubectl logs -n default -l app.kubernetes.io/name=homepage --tail=100
```

### Passo 4 — Rimuovi il servizio di test (opzionale)

Quando vuoi togliere il servizio di test dalla dashboard:

```bash
# Rimuovi il test-service dal kustomization
cd /path/to/k3s
# Edita flux/dashboard/kustomization.yaml e commenta test-service.yaml
# Fai push sul Git repo

# OPPURE rimuovi direttamente:
kubectl delete -f flux/dashboard/test-service.yaml
```

---

## 📁 File di riferimento

| File | Descrizione |
|------|-------------|
| `flux/dashboard/release.yaml` | HelmRelease per il deployment di Homepage |
| `flux/dashboard/homepage-config.yaml` | ConfigMap con impostazioni statiche |
| `flux/dashboard/ingressroute.yaml` | Traefik IngressRoute per dashboard.unifi.localdomain |
| `flux/dashboard/kustomization.yaml` | Kustomization per Flux |
| `clusters/homelab/dashboard.yaml` | Flux Kustomization che attiva il deployment |

## 🔗 Risorse utili

- Homepage docs: <https://gethomepage.dev>
- Icone: <https://gethomepage.dev/latest/config-items/icons>
- Widgets: <https://gethomepage.dev/latest/widgets/>
