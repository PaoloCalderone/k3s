# Changelog — Homepage Dashboard

Data: 2025-09-30

## 🆕 File creati

### `flux/dashboard/` (nuova directory)

| File | Ruolo |
|------|-------|
| `kustomization.yaml` | Elenco risorse da deployare |
| `release.yaml` | Flux HelmRelease → Homepage v0.10.11 (Helm chart `homepage` repo `gethomepage`) |
| `homepage-config.yaml` | ConfigMap `homepage-config` con settings (theme, widgets, categories) |
| `ingressroute.yaml` | Traefik IngressRoute → `dashboard.unifi.localdomain` (TLS) |
| `test-service.yaml` | Servizio di test: nginx con pagina HTML custom, esposto su `test.unifi.localdomain` |

### `clusters/homelab/`

| File | Ruolo |
|------|-------|
| `dashboard.yaml` | Flux Kustomization che attiva il deployment di `flux/dashboard/` |

### `docs/`

| File | Ruolo |
|------|-------|
| `dashboard.md` | Documentazione completa: come aggiungere servizi, esempi pratici, widget, test |
| `homepage-annotations.md` | Reference annotations `gethomepage.dev/` con esempi |

### `scripts/`

| File | Ruolo |
|------|-------|
| `validate-dashboard.sh` | Script di validazione che controlla stato pod, servizi, DNS, TLS |

---

## 🔧 File modificati

### `clusters/homelab/kustomization.yaml`
- Aggiunta `dashboard.yaml` alla lista dei resources

### `flux/monitoring/ingressroutes.yaml`
- Aggiunte annotations `gethomepage.dev/` a tutte e 3 le rotte esistenti:
  - Grafana → `gethomepage.dev/name: "Grafana"`, group: "Monitoring", icon: "grafana"
  - Prometheus → `gethomepage.dev/name: "Prometheus"`, group: "Monitoring", icon: "prometheus"
  - Alertmanager → `gethomepage.dev/name: "Alertmanager"`, group: "Monitoring", icon: "alert"

---

## 📊 Risultato atteso

Accedendo a `https://dashboard.unifi.localdomain` si vedrà:

### Gruppo: Monitoring
- **Grafana** → grafana.unifi.localdomain (widget: Grafana)
- **Prometheus** → prometheus.unifi.localdomain (widget: Prometheus)
- **Alertmanager** → alertmanager.unifi.localdomain (widget: Alertmanager)

### Gruppo: Infrastruttura
- **Test** → test.unifi.localdomain (servizio di test)

### Widget cluster
- Stato nodi k3s (CPU, memoria)

---

## 🚀 Deploy

Dopo aver fatto il push delle modifiche sul repo Git:

```bash
# Flux dovrebbe deployare automaticamente in ~10 minuti
# Puoi triggerare Flux con:
flux reconcile kustomization dashboard -n flux-system

# Oppure attendi l'interval: 10m
```

## 🧪 Validazione

```bash
# Script di validazione
bash scripts/validate-dashboard.sh

# Verifica manuale
kubectl get pods -n default -l app.kubernetes.io/name=homepage
kubectl get pods -n test
curl -k https://dashboard.unifi.localdomain
```

## ⚠️ Note

- Homepage legge annotations su **tutte** le IngressRoute del cluster (anche di altri namespace)
- `test.unifi.localdomain` è inteso solo per testing: puoi rimuoverlo cancellando `flux/dashboard/test-service.yaml`
- Il servizio Homepage usa RBAC per leggere risorse del cluster automaticamente
- Tutti i servizi esistenti con `gethomepage.dev/enabled: "true"` appaiono automaticamente
