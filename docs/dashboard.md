# Homepage Dashboard — User Guide

The Homepage dashboard exposed on `dashboard.unifi.localdomain` automatically discovers all k3s cluster services exposed via Traefik.

## How It Works

Homepage reads the `gethomepage.dev/` annotations from your Traefik IngressRoutes and automatically creates a card for each service. When you create a new service, just add the annotations and push to the Git repo — Flux updates Homepage and the new card appears without restarts.

---

## How to Add a New Service

### 1. Create or update the IngressRoute with annotations

```yaml
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: home-assistant
  namespace: flux-system          # or the namespace of your service
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/name: "Home Assistant"
    gethomepage.dev/description: "Home automation"
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
        - name: home-assistant-service
          port: 8123
```

### 2. Required annotations

| Annotation | Required? | Description |
|------------|-----------|-------------|
| `gethomepage.dev/enabled` | **YES** | `"true"` to enable auto-discovery |

### 3. Recommended annotations

| Annotation | Description |
|------------|-------------|
| `gethomepage.dev/name` | Display name on the card |
| `gethomepage.dev/description` | Subtitle under the name |
| `gethomepage.dev/group` | Category to group the service |
| `gethomepage.dev/icon` | Icon from Font Awesome / Heroicons / Material Symbols |

### 4. Live widgets (optional)

Some services show live data instead of a static image:

| Widget | Description |
|--------|-------------|
| `grafana` | Grafana dashboard snapshot |
| `prometheus` | Prometheus metrics and alarms |
| `alertmanager` | Alertmanager alarm status |
| `home-assistant` | Home Assistant devices |
| `docker` | Running containers |
| `kubernetes` | K3s cluster status |

### 5. Available icons

Homepage supports icons from **Font Awesome 6**, **Heroicons**, **Lucide** and **Material Symbols**.

Examples:
```
grafana, prometheus, alert, docker, kubernetes, nginx,
home-assistant, sonarr, radarr, overseerr, plex, qbittorrent,
linux, cloud, database, server, shield, code
```

Full list: <https://gethomepage.dev/latest/config-items/icons>

---

## Practical Examples

### Example 1 — Home Assistant

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: home-assistant
  namespace: flux-system
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/name: "Home Assistant"
    gethomepage.dev/description: "Home automation"
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
        - name: home-assistant
          port: 8123
```

### Example 2 — Navidrome (music)

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: navidrome
  namespace: flux-system
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/name: "Navidrome"
    gethomepage.dev/description: "Music server"
    gethomepage.dev/group: "Infrastructure"
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

### Example 3 — NFS Storage

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: nfs-storage
  namespace: flux-system
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/name: "NFS Storage"
    gethomepage.dev/description: "Network storage"
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

## What NOT to do

- **Do not annotate the Homepage route itself** with `gethomepage.dev/enabled: "true"`. Homepage recognizes `dashboard.unifi.localdomain` as the dashboard itself and hides it from cards. If you annotate it, the dashboard will show itself as one of its own cards.

  ```yaml
  # CORRECT — empty page for its own route
  name: homepage
  namespace: flux-system

  # WRONG — shows itself as a card
  name: homepage
  annotations:
    gethomepage.dev/enabled: "true"
  ```

---

## Already Configured Services

Currently auto-discovered via annotations on existing IngressRoutes:

| Service | URL | Group | Icon | Widget |
|---------|-----|-------|------|--------|
| Grafana | `grafana.unifi.localdomain` | Monitoring | `grafana` | Grafana |
| Prometheus | `prometheus.unifi.localdomain` | Monitoring | `prometheus` | Prometheus |
| Alertmanager | `alertmanager.unifi.localdomain` | Monitoring | `alert` | Alertmanager |

## Test Service

A test service has been created to verify functionality:

| Service | URL | Group | Icon |
|---------|-----|-------|------|
| **Test** | `test.unifi.localdomain` | Infrastructure | `flask` |

The test service is an nginx with a custom HTML page that confirms Homepage auto-discovery is working correctly. When you access `https://dashboard.unifi.localdomain`, you should see a "Test" card in the "Infrastructure" group pointing to `test.unifi.localdomain`.

---

## Testing the Configuration

### Step 1 — Verify Deployment

```bash
# Check that the Homepage pod is Running
kubectl get pods -n default -l app.kubernetes.io/name=homepage

# Check Traefik resources discovered
kubectl get ingressroutes -A | grep -A3 gethomepage
```

### Step 2 — Test the Test Service

```bash
# Verify the test-service is deployed
kubectl get pods -n test

# Access the test service directly
curl -k https://test.unifi.localdomain 2>/dev/null | head -20

# Verify the "Test" card appears on the dashboard
# Open https://dashboard.unifi.localdomain
```

### Step 3 — Verify Auto-Discovery

```bash
# All IngressRoutes with Homepage annotations
kubectl get ingressroutes -A -o yaml | grep -B2 -A10 "gethomepage.dev"

# Check Homepage logs for discovery errors
kubectl logs -n default -l app.kubernetes.io/name=homepage --tail=100
```

### Step 4 — Remove the Test Service (optional)

When you want to remove the test service from the dashboard:

```bash
# Remove the test-service from the kustomization
cd /path/to/k3s
# Edit flux/dashboard/kustomization.yaml and comment out test-service.yaml
# Push to the Git repo

# OR remove directly:
kubectl delete -f flux/dashboard/test-service.yaml
```

---

## Reference Files

| File | Description |
|------|-------------|
| `flux/dashboard/release.yaml` | HelmRelease for Homepage deployment |
| `flux/dashboard/homepage-config.yaml` | ConfigMap with static settings |
| `flux/dashboard/ingressroute.yaml` | Traefik IngressRoute for dashboard.unifi.localdomain |
| `flux/dashboard/kustomization.yaml` | Kustomization for Flux |
| `clusters/homelab/dashboard.yaml` | Flux Kustomization that triggers deployment |

## Useful Resources

- Homepage docs: <https://gethomepage.dev>
- Icons: <https://gethomepage.dev/latest/config-items/icons>
- Widgets: <https://gethomepage.dev/latest/widgets/>
