# Homepage — Annotations per Traefik IngressRoute

Homepage (gethomepage/homepage) scopre automaticamente i servizi dal cluster k3s
leggendo le annotations sulle risorse Traefik IngressRoute.

## Come funzionano le annotations

Quando crei una nuova IngressRoute per un servizio, aggiungi queste annotations:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: il-mio-servizio
  namespace: il-namespace
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/name: "Nome visualizzato"
    gethomepage.dev/description: "Cosa fa"
    gethomepage.dev/group: "Categoria"
    gethomepage.dev/icon: "nome-icona"
    gethomepage.dev/widget.type: "tipo-widget"
spec:
  # ... resto della configurazione Traefik
```

## Annotations disponibili

| Annotation | Obbligatorio? | Esempio |
|------------|---------------|---------|
| `gethomepage.dev/enabled` | ✅ | `"true"` |
| `gethomepage.dev/name` | ⚠️ | `"Casa Assistent"` |
| `gethomepage.dev/description` | ⚠️ | `"Smart home hub"` |
| `gethomepage.dev/group` | ⚠️ | `"Infrastruttura"` |
| `gethomepage.dev/icon` | ⚠️ | `"home-assistant"` |
| `gethomepage.dev/widget.type` | ❌ | `"home-assistant"` |

## Icone disponibili

Homepage supporta icone da **Font Awesome 6**, **Heroicons**, **Lucide** e **Material Symbols**.

Esempi:
- `grafana`, `prometheus`, `alert`, `home-assistant`
- `docker`, `kubernetes`, `nginx`
- `sonarr`, `radarr`, `overseerr`

Lista completa: https://gethomepage.dev/latest/config-items/icons

## Widget supportati

| Widget | Descrizione |
|--------|-------------|
| `grafana` | Dashboard grafana con snapshots |
| `prometheus` | Metriche e query Prometheus |
| `alertmanager` | Stato allarmi |
| `home-assistant` | Dispositivi HA |
| `docker` | Container in esecuzione |
| `kubernetes` | Stato pod/nodes cluster |

## Quando NON aggiungere le annotations

- **Dashboard stesso**: Non aggiungere annotations alla rotta di Homepage, altrimenti la dashboard mostra sé stessa come card.
  ```yaml
  # ⚠️ NON annotare la rotta di Homepage
  name: homepage
  namespace: flux-system
  ```

## Esempio completo — nuovo servizio

```yaml
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: home-assistant
  namespace: flux-system
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/name: "Casa Assistent"
    gethomepage.dev/description: "Automation e IoT"
    gethomepage.dev/group: "Infrastruttura"
    gethomepage.dev/icon: "home-assistant"
    gethomepage.dev/widget.type: "home-assistant"
spec:
  entryPoints:
    - websecure
  tls:
    secretName: unifi-localdomain-tls
  routes:
    - match: Host(`homeassistant.unifi.localdomain`)
      kind: Rule
      services:
        - name: ha-service
          port: 8123
```

## Pagamento Flux

Dopo aver fatto il push sul repo Git, Flux aggiorna automaticamente la configurazione
e Homepage legge le nuove annotations dalle IngressRoute scoperte.

Non serve riavviare o riconfigurare Homepage.
