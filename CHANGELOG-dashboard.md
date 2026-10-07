# Changelog — Homepage Dashboard

Date: 2025-09-30

## 🆕 Files Created

### `flux/dashboard/` (new directory)

| File | Role |
|------|------|
| `kustomization.yaml` | List of resources to deploy |
| `release.yaml` | Flux HelmRelease → Homepage v0.10.11 (Helm chart `homepage` from repo `gethomepage`) |
| `homepage-config.yaml` | ConfigMap `homepage-config` with settings (theme, widgets, categories) |
| `ingressroute.yaml` | Traefik IngressRoute → `dashboard.unifi.localdomain` (TLS) |
| `test-service.yaml` | Test service: nginx with custom HTML page, exposed on `test.unifi.localdomain` |

### `clusters/homelab/`

| File | Role |
|------|------|
| `dashboard.yaml` | Flux Kustomization that triggers deployment of `flux/dashboard/` |

### `docs/`

| File | Role |
|------|------|
| `dashboard.md` | Complete documentation: how to add services, practical examples, widgets, testing |
| `homepage-annotations.md` | Reference for `gethomepage.dev/` annotations with examples |

### `scripts/`

| File | Role |
|------|------|
| `validate-dashboard.sh` | Validation script that checks pod status, services, DNS, TLS |

---

## 🔧 Files Modified

### `clusters/homelab/kustomization.yaml`
- Added `dashboard.yaml` to the resources list

### `flux/monitoring/ingressroutes.yaml`
- Added `gethomepage.dev/` annotations to all 3 existing routes:
  - Grafana → `gethomepage.dev/name: "Grafana"`, group: "Monitoring", icon: "grafana"
  - Prometheus → `gethomepage.dev/name: "Prometheus"`, group: "Monitoring", icon: "prometheus"
  - Alertmanager → `gethomepage.dev/name: "Alertmanager"`, group: "Monitoring", icon: "alert"

---

## 📊 Expected Result

Accessing `https://dashboard.unifi.localdomain` will show:

### Group: Monitoring
- **Grafana** → grafana.unifi.localdomain (widget: Grafana)
- **Prometheus** → prometheus.unifi.localdomain (widget: Prometheus)
- **Alertmanager** → alertmanager.unifi.localdomain (widget: Alertmanager)

### Group: Infrastructure
- **Test** → test.unifi.localdomain (test service)

### Cluster widgets
- K3s node status (CPU, memory)

---

## 🚀 Deployment

After pushing the changes to the Git repo:

```bash
# Flux should deploy automatically in ~10 minutes
# You can trigger Flux with:
flux reconcile kustomization dashboard -n flux-system

# Or wait for the sync interval: 10m
```

## 🧪 Validation

```bash
# Validation script
bash scripts/validate-dashboard.sh

# Manual verification
kubectl get pods -n default -l app.kubernetes.io/name=homepage
kubectl get pods -n test
curl -k https://dashboard.unifi.localdomain
```

## ⚠️ Notes

- Homepage reads annotations from **all** IngressRoutes in the cluster (including other namespaces)
- `test.unifi.localdomain` is for testing only: you can remove it by deleting `flux/dashboard/test-service.yaml`
- The Homepage service uses RBAC to automatically read cluster resources
- All existing services with `gethomepage.dev/enabled: "true"` appear automatically
