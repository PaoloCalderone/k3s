# K3s HA Homelab on Proxmox

A lightweight, **highly-available Kubernetes** cluster across three Proxmox hosts — provisioned with Terraform, powered by K3s, and driven by GitOps with Flux.

## Architecture

| VM      | VMID | Host | IP            | Role                        |
|---------|------|------|---------------|------------------------------|
| k8s-cp1 | 9011 | pve1 | 192.168.9.11  | K3s server / embedded etcd   |
| k8s-w1  | 9012 | pve1 | 192.168.9.12  | K3s agent                    |
| k8s-cp2 | 9021 | pve2 | 192.168.9.21  | K3s server / embedded etcd   |
| k8s-w2  | 9022 | pve2 | 192.168.9.22  | K3s agent                    |
| k8s-cp3 | 9031 | pve3 | 192.168.9.31  | K3s server / embedded etcd   |
| k8s-w3  | 9032 | pve3 | 192.168.9.32  | K3s agent                    |

- **API VIP (kube-vip):** `192.168.9.99:6443`
- **NFS:** `192.168.9.9:/mnt/pool/kubernetes`
- **MetalLB pool:** `192.168.9.200–192.168.9.220` (keep it out of DHCP)
- **Bridge:** `vmbr9` on `192.168.9.0/24`
- **Proxmox management:** `192.168.0.10`, `.20`, `.30`

> The legacy `9099` VMID is gone: kube-vip exposes the API endpoint on all three control planes, so no single HAProxy VM is needed.

## Prerequisites

- Terraform, `kubectl`, and the Flux CLI
- Proxmox API token in `PROXMOX_VE_API_TOKEN`
- SSH key `~/.ssh/k3s_homelab.pub`
- Admin machine with access to `192.168.9.0/24`

```bash
cd infrastructure/terraform
cp terraform.tfvars.example terraform.tfvars
src ~/.config/k3s-proxmox.env
terraform fmt -check
terraform validate
# Apply only after reviewing the plan
```

Terraform provisions an Ubuntu 24.04 cloud-init template and six VMs. It does **not** install K3s or store K3s tokens in state.

## Bootstrap K3s

```bash
cd ../..
./scripts/bootstrap-k3s.sh
export KUBECONFIG="$PWD/kubeconfig"
kubectl get nodes -o wide
```

The token is generated with restrictive permissions in `~/.config/k3s-homelab/token`. The script initializes the first server, joins the others, installs kube-vip, then attaches the agents.

Once the cluster is verified:

```bash
flux check --pre
flux bootstrap github \
  --owner=PaoloCalderone \
  --repository=k3s \
  --personal \
  --branch=main \
  --path=clusters/homelab \
  --version=v2.7.5
```

Never pass a GitHub token on the command line — use Flux's supported GitHub auth. K3s 1.32 needs Flux 2.7.x (the 2.9.x CLI requires Kubernetes 1.33+). `clusters/homelab` reconciles MetalLB then its IP pool (HelmRelease Ready → config), and NFS CSI the same two-phase way; the sample app stays disabled. NFS needs `nfs-common` on every node. `nfs-csi` is **not** the default StorageClass — set `storageClassName: nfs-csi` on your PVCs; `local-path` stays the default.

## Minimal Validation

```bash
terraform -chdir=infrastructure/terraform validate
bash -n scripts/bootstrap-k3s.sh
kubectl kustomize flux >/dev/null
KUBECONFIG=./kubeconfig kubectl wait --for=condition=Ready nodes --all --timeout=10m
KUBECONFIG=./kubeconfig kubectl get pods -A
```

## Security & Backups

- SSH by key only — no passwords in the repo.
- K3s token and kubeconfig are git-ignored.
- Trust the Proxmox certificates, then set `insecure = false` in the provider.
- Enable K3s etcd snapshots and NFS data snapshots/replication — VM snapshots are **not** a substitute.
