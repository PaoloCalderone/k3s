# K3s HA Homelab on Proxmox

Cluster Kubernetes leggero e altamente disponibile su tre host Proxmox, provisionato con Terraform e configurato con K3s.

## Architettura

| VM | VMID | Proxmox | IP | Ruolo |
|---|---:|---|---|---|
| k8s-cp1 | 9011 | pve1 | 192.168.9.11 | K3s server / embedded etcd |
| k8s-w1 | 9012 | pve1 | 192.168.9.12 | K3s agent |
| k8s-cp2 | 9021 | pve2 | 192.168.9.21 | K3s server / embedded etcd |
| k8s-w2 | 9022 | pve2 | 192.168.9.22 | K3s agent |
| k8s-cp3 | 9031 | pve3 | 192.168.9.31 | K3s server / embedded etcd |
| k8s-w3 | 9032 | pve3 | 192.168.9.32 | K3s agent |

- API VIP kube-vip: `192.168.9.99:6443`
- NFS: `192.168.9.9:/mnt/pool/kubernetes`
- MetalLB: `192.168.9.200-192.168.9.220` (deve essere escluso dal DHCP)
- Bridge VM: `vmbr9`, rete `192.168.9.0/24`
- Management Proxmox: `192.168.0.10`, `.20`, `.30`

La precedente VMID `9099` non viene più usata: kube-vip rende l'endpoint API disponibile sui tre control plane senza una VM HAProxy singola.

## Prerequisiti

- Terraform, kubectl e Flux CLI
- API token Proxmox in `PROXMOX_VE_API_TOKEN`
- chiave SSH `~/.ssh/k3s_homelab.pub`
- connettività dal computer di amministrazione a `192.168.9.0/24`

## Provisioning

```bash
cd infrastructure/terraform
cp terraform.tfvars.example terraform.tfvars
source ~/.config/k3s-proxmox.env
terraform init
terraform fmt -check
terraform validate
terraform plan
# Applicare solo dopo aver revisionato il piano:
terraform apply
```

Terraform crea un template Ubuntu 24.04 cloud-init e sei VM. Non installa K3s e non inserisce token K3s nello state.

## Bootstrap K3s

```bash
cd ../..
./scripts/bootstrap-k3s.sh
export KUBECONFIG="$PWD/kubeconfig"
kubectl get nodes -o wide
```

Il token viene generato con permessi restrittivi in `~/.config/k3s-homelab/token`. Lo script inizializza il primo server, aggiunge gli altri server, installa kube-vip, quindi aggiunge gli agent.

## GitOps

Dopo la verifica del cluster:

```bash
flux check --pre
flux bootstrap github \
  --owner=PaoloCalderone \
  --repository=k3s \
  --personal \
  --branch=main \
  --path=clusters/homelab \
  --version=v2.7.5 \
  --personal
```

Non passare token GitHub sulla riga di comando. Usa l'autenticazione GitHub/Flux supportata. Il cluster K3s 1.32 richiede Flux 2.7.x (la CLI 2.9.x richiede Kubernetes 1.33+). `clusters/homelab` riconcilia prima la HelmRelease MetalLB e poi il pool IP, attendendo che l'HelmRelease sia Ready. NFS e l'app esempio non vengono attivati dal bootstrap.

## Validazione minima

```bash
terraform -chdir=infrastructure/terraform validate
bash -n scripts/bootstrap-k3s.sh
kubectl kustomize flux >/dev/null
KUBECONFIG=./kubeconfig kubectl wait --for=condition=Ready nodes --all --timeout=10m
KUBECONFIG=./kubeconfig kubectl get pods -A
```

## Sicurezza e backup

- SSH solo tramite chiave; nessuna password nel repository.
- Il token K3s e il kubeconfig sono ignorati da Git.
- Abilitare certificati attendibili per Proxmox e poi impostare `insecure = false` nel provider.
- Configurare snapshot etcd K3s e snapshot/replica dei dati NFS; le snapshot VM non sostituiscono questi backup.
