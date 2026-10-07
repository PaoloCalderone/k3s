# Homepage — Annotations for Traefik IngressRoute

Homepage (gethomepage/homepage) automatically discovers services from the k3s cluster
by reading annotations on Traefik IngressRoute resources.

## How annotations work

When you create a new IngressRoute for a service, add these annotations:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-service
  namespace: my-namespace
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/name: "Display Name"
    gethomepage.dev/description: "What it does"
    gethomepage.dev/group: "Category"
    gethomepage.dev/icon: "icon-name"
    gethomepage.dev/widget.type: "widget-type"
spec:
  # ... rest of the Traefik configuration
```

## Available annotations

| Annotation | Required? | Example |
|------------|-----------|---------|
| `gethomepage.dev/enabled` | ✅ | `"true"` |
| `gethomepage.dev/name` | ⚠️ | `"Home Assistant"` |
| `gethomepage.dev/description` | ⚠️ | `"Smart home hub"` |
| `gethomepage.dev/group` | ⚠️ | `"Infrastructure"` |
| `gethomepage.dev/icon` | ⚠️ | `"home-assistant"` |
| `gethomepage.dev/widget.type` | ❌ | `"home-assistant"` |

## Available icons

Homepage supports icons from **Font Awesome 6**, **Heroicons**, **Lucide** and **Material Symbols**.

Examples:
- `grafana`, `prometheus`, `alert`, `home-assistant`
- `docker`, `kubernetes`, `nginx`
- `sonarr`, `radarr`, `overseerr`

Full list: https://gethomepage.dev/latest/config-items/icons

## Supported widgets

| Widget | Description |
|--------|-------------|
| `grafana` | Grafana dashboards with snapshots |
| `prometheus` | Prometheus metrics and queries |
| `alertmanager` | Alarm status |
| `home-assistant` | HA devices |
| `docker` | Running containers |
| `kubernetes` | Cluster pod/node status |

## When NOT to add annotations

- **The dashboard itself**: Do not add annotations to the Homepage route, otherwise the dashboard will show itself as a card.
  ```yaml
  # ⚠️ Do not annotate the Homepage route
  name: homepage
  namespace: flux-system
  ```

## Complete example — new service

```yaml
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: home-assistant
  namespace: flux-system
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/name: "Home Assistant"
    gethomepage.dev/description: "Automation and IoT"
    gethomepage.dev/group: "Infrastructure"
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

## Flux sync

After pushing to the Git repo, Flux automatically updates the configuration
and Homepage reads the new annotations from the discovered IngressRoutes.

No need to restart or reconfigure Homepage.
