# Operational Guide: Ubuntu 24.04 and K3s HA

## 1. Preparation

Verify Proxmox quorum, `vmbr9` bridge, routing to `192.168.9.0/24`, NFS `192.168.9.9` and MetalLB pool DHCP reservation.

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/k3s_homelab -C k3s-homelab
chmod 600 ~/.ssh/k3s_homelab
chmod 644 ~/.ssh/k3s_homelab.pub
```

The Proxmox token stays in `~/.config/k3s-proxmox.env`; do not copy it to the repository.

## 2. Static Gateways

```bash
cd infrastructure/terraform
source ~/.config/k3s-proxmox.env
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
cd ../..
bash -n scripts/bootstrap-k3s.sh
kubectl kustomize flux >/dev/null
```

Carefully review creations and deletions. Do not proceed if VMIDs or IPs appear to be in use.

## 3. VM Provisioning

```bash
cd infrastructure/terraform
terraform apply
```

Wait for all VMs to finish cloud-init and be reachable via SSH. Terraform uses Ubuntu 24.04 cloud image, QEMU guest agent, static IP and SSH key.

## 4. K3s Bootstrap

```bash
cd ../..
./scripts/bootstrap-k3s.sh
export KUBECONFIG="$PWD/kubeconfig"
kubectl get nodes -o wide
kubectl get --raw='/readyz?verbose'
```

Automated sequence:

1. First server with `cluster-init`;
2. Second and third servers added to the embedded-etcd cluster;
3. kube-vip DaemonSet and wait for `192.168.9.99:6443`;
4. Three agents connected to the VIP;
5. kubeconfig extraction and wait for nodes Ready.

## 5. HA Checks

```bash
kubectl -n kube-system rollout status daemonset/kube-vip-ds
kubectl get nodes
kubectl get pods -A
curl -k https://192.168.9.99:6443/readyz
```

Power off one control plane at a time and verify that the VIP and API remain available. Repeat for each server. The three-member embedded-etcd cluster tolerates the loss of one member.

## 6. Flux

Keep GitHub authentication out of shell history. Run `flux bootstrap github --owner=PaoloCalderone --repository=k3s --personal --branch=main --path=clusters/homelab --version=v2.7.5` (K3s 1.32 is not supported by Flux 2.9). `clusters/homelab` activates MetalLB and NFS CSI, each in two phases; the example app remains disabled. NFS CSI requires `nfs-common` on all nodes and the export `192.168.9.9:/mnt/pool/kubernetes` reachable from the nodes. The `nfs-csi` StorageClass is not the default: select it explicitly in the PVC (`storageClassName: nfs-csi`); `local-path` remains default.

Before reconciliation:

```bash
kubectl kustomize flux >/tmp/flux-rendered.yaml
flux check --pre
```

The `metallb-config` Kustomization depends on the `metallb` Kustomization, which waits for the HelmRelease to be Ready (and CRDs) before applying IPAddressPool and L2Advertisement. Verify that `192.168.9.200-220` is excluded from DHCP before reconciliation.

## 7. Backup

- Configure K3s etcd snapshots and copy them off the VMs.
- Configure NFS dataset snapshots/replication.
- For databases, create application-consistent dumps.
- Test restoration, do not just create backups.

## 8. No Automatic Application

Terraform `apply`, bootstrap and Flux must be run separately and only after reviewing their respective outputs. This prevents a single command from destroying and recreating the entire environment without a human gate.
