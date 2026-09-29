# Guida operativa: Ubuntu 24.04 e K3s HA

## 1. Preparazione

Verificare quorum Proxmox, bridge `vmbr9`, routing verso `192.168.9.0/24`, NFS `192.168.9.9` e riserva DHCP del pool MetalLB.

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/k3s_homelab -C k3s-homelab
chmod 600 ~/.ssh/k3s_homelab
chmod 644 ~/.ssh/k3s_homelab.pub
```

Il token Proxmox resta in `~/.config/k3s-proxmox.env`; non copiarlo nel repository.

## 2. Gate statici

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

Revisionare attentamente creazioni e distruzioni. Non procedere se VMID o IP risultano occupati.

## 3. Provisioning VM

```bash
cd infrastructure/terraform
terraform apply
```

Attendere che tutte le VM abbiano terminato cloud-init e siano raggiungibili via SSH. Terraform usa Ubuntu 24.04 cloud image, QEMU guest agent, static IP e chiave SSH.

## 4. Bootstrap K3s

```bash
cd ../..
./scripts/bootstrap-k3s.sh
export KUBECONFIG="$PWD/kubeconfig"
kubectl get nodes -o wide
kubectl get --raw='/readyz?verbose'
```

Sequenza automatizzata:

1. primo server con `cluster-init`;
2. secondo e terzo server aggiunti al cluster embedded-etcd;
3. DaemonSet kube-vip e attesa di `192.168.9.99:6443`;
4. tre agent collegati al VIP;
5. estrazione del kubeconfig e attesa dei nodi Ready.

## 5. Controlli HA

```bash
kubectl -n kube-system rollout status daemonset/kube-vip-ds
kubectl get nodes
kubectl get pods -A
curl -k https://192.168.9.99:6443/readyz
```

Spegnere un solo control plane alla volta e verificare che VIP e API rimangano disponibili. Ripetere per ciascun server. Il cluster embedded-etcd a tre membri tollera la perdita di un membro.

## 6. Flux

Conservare l'autenticazione GitHub fuori dalla cronologia shell. Eseguire `flux bootstrap github --owner=PaoloCalderone --repository=k3s --personal --branch=main --path=clusters/homelab --version=v2.7.5` (K3s 1.32 non è supportato da Flux 2.9). `clusters/homelab` attiva MetalLB e NFS CSI, ciascuno in due fasi; l'app esempio rimane disattivata. NFS CSI richiede `nfs-common` su tutti i nodi e l'export `192.168.9.9:/mnt/pool/kubernetes` raggiungibile dai nodi. La StorageClass `nfs-csi` non è default: selezionarla esplicitamente nel PVC (`storageClassName: nfs-csi`); `local-path` resta default.

Prima della riconciliazione:

```bash
kubectl kustomize flux >/tmp/flux-rendered.yaml
flux check --pre
```

La Kustomization `metallb-config` dipende dalla Kustomization `metallb`, che attende la HelmRelease Ready (e le CRD) prima di applicare IPAddressPool e L2Advertisement. Verificare che `192.168.9.200-220` sia escluso dal DHCP prima della riconciliazione.

## 7. Backup

- Configurare snapshot etcd K3s e copiarli fuori dalle VM.
- Configurare snapshot/replica del dataset NFS.
- Per database, creare dump applicativamente consistenti.
- Provare il ripristino, non limitarsi alla creazione dei backup.

## 8. Nessuna applicazione automatica

Terraform `apply`, bootstrap e Flux devono essere eseguiti separatamente e solo dopo la revisione dei rispettivi output. Questo impedisce a un singolo comando di distruggere e ricreare l'intero ambiente senza gate umano.
