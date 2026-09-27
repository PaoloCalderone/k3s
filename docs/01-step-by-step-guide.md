# 📖 Guida Passo-Passo: Cluster K3s + Talos Linux su Proxmox — 3 CP + 3 Worker (HA)

**Network: 192.168.9.0/24 (VLAN dedicata)**

Questa guida ti accompagna dalla macchina spenta al cluster operativo HA, gestito interamente da Git.

---

## ⚠️ CONCETTO FONDAMENTALE — Prima di iniziare

**Tutti i comandi di questa guida si eseguono DAL TUO MAC (o laptop), NON su Proxmox.**

Stai usando il modello **Infrastructure as Code**: il tuo computer è il "pannello di controllo" che configura il cluster remoto. Non installi nulla su Proxmox a mano — ci pensa Terraform.

```
IL TUO MAC (laptop)                     IL TUO CLUSTER REMOTO
│  brew install terraform│  ──REST API►│  Proxmox (3 nodi fisici)│
│  brew install talosctl │  ──gRPC──► │  ┌─────┐ ┌─────┐ ┌─────┐│
│  brew install kubectl  │  ──HTTPS──►│  │ CP1 │ │ CP2 │ │ CP3 ││
│  brew install flux     │  ──kubectl►│  │W1  │ │W2  │ │W3  ││
│  (Flux + Renovate)     │           │  │Talos│ │Talos│ │Talos││
                          ─────────▶  │  K3s  │ │K3s  │ │K3s  ││
                          ─────────▶  └─────┴─┴─────┴─┴─────┘
                                     Network: 192.168.9.0/24
                                     NAS: TrueNAS (NFS v4.2)
                                     LB:  HAProxy (VIP: 192.168.9.99)
                                     Backup: Proxmox Backup Server (PBS)
```

### 0.0 Configurazione Rete — VPN (obbligatoria)

Proxmox è nella tua rete locale. Per accedervi dal tuo Mac **fuori casa** (es. dal lavoro, da un altro edificio, o quando il laptop non è nella stessa rete) serve una VPN.

#### Opzione A — WireGuard su un nodo Proxmox (consigliata)

Installando WireGuard su uno dei 3 nodi fisici Proxmox:

```bash
# Sul nodo Proxmox (via SSH o console fisica):
apt update && apt install -y wireguard-tools

# Genera le chiavi
wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key

# Configura /etc/wireguard/wg0.conf
cat > /etc/wireguard/wg0.conf << 'EOF'
[Interface]
Address = 10.16.0.1/24
PrivateKey = <IL_TUO_PRIVATE_KEY>
ListenPort = 51820

[Peer]
# Il tuo laptop
PublicKey = <PUBBLICA_DEL_TUO_LAPTOP>
AllowedIPs = 10.16.0.2/32
EOF

chmod 600 /etc/wireguard/wg0.conf
systemctl enable --now wg-quick@wg0
```

Sul Mac:
```bash
brew install wireguard-tools
# Crea /etc/wireguard/tg0.conf con:
wg quick up /etc/wireguard/tg0.conf
```

Dopo: il tuo Mac avrà l'IP `10.16.0.2` e accederà a Proxmox a `10.16.0.1`.

#### Opzione B — SSH tunnel (più semplice, meno performante)

Se hai già accesso SSH a uno dei nodi Proxmox:

```bash
# Sul tuo Mac, crea un tunnel SSH:
ssh -L 8006:<IP-PROXMOX-NODE>:8006 -L 50000:<IP-PROXMOX-NODE>:50000 root@<NOME-NODE>

# Ora puoi puntare localhost al cluster:
# - UI Proxmox:       http://localhost:8006
# - Talos API:        localhost:50000
# - Kubernetes API:   localhost:6443
```

---

## FASE 0 — Preparazione Environment (30 minuti)

> ⚠️ **Esegui questi comandi sul TUO MAC/laptop**, NON sui nodi Proxmox.

### 0.1 Installa gli strumenti CLI

```bash
# --- Installa Homebrew (se non ce l'hai) ---
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# --- Installa Terraform (o OpenTofu) ---
brew install terraform
# Oppure: brew install opentofu

# --- Installa talosctl (strumento per Talos) ---
brew install talosctl

# --- Installa kubectl (strumento per Kubernetes) ---
brew install kubectl

# --- Installa Flux CLI (strumento per GitOps) ---
brew install fluxcd/tap/flux

# --- Installa yq (tool per YAML) ---
brew install yq

# --- Verifica installazione ---
terraform version      # o: tofu --version
talosctl version       # deve essere ~ allineato a k8s
kubectl version --client
flux version
```

### 0.2 Crea il repository GitHub

```bash
# 1. Crea un repo su github.com chiamato "k3s-talos-homelab"
#    - Privato o pubblico (scelta tua)
#    - NON inizializzare con README/.gitignore

# 2. Clone il repo nel posto che preferisci
git clone https://github.com/TUO-USERNAME/k3s-talos-homelab.git
cd k3s-talos-homelab
```

### 0.3 Configura l'account API su Proxmox

```bash
# 1. Apri il UI di Proxmox nel browser (vedi nota VPN sopra)
#    https://<TUA-IP-PROXMOX>:8006

# 2. Login con il tuo account (es. root@pam)

# 3. Vai in: Datacenter → Permissions → Users → Add
#    User ID: terraform
#    Password: <una password forte>

# 4. Crea il ruolo: Datacenter → Permissions → Roles → Add
#    Role ID: TerraformProv
#    Privileges: TUTTE le privileges (VM.Allocate, VM.Clone, ecc.)

# 5. Assegna il permesso dell'utente al Datacenter/Nodes
#    User ID: terraform
#    Role: TerraformProv
#    Path: /
#    Propagate: ✓ (spuntato)
```

---

## FASE 1 — Provisioning con Terraform (20 minuti)

### 1.0 Mappatura Nodi — CONFIGURAZIONE (Rete: 192.168.9.0/24)

Prima di lanciare Terraform, assicurati di aver mappato correttamente i tuoi nodi:

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│  Nodo Fisico Proxmox  │  VM K8s       │  IP            │  Ruolo K8s                  │
├───────────────────────┼───────────────┼────────────────┼───────────────────────────┤
│  pve1                 │  k8s-cp1     │  192.168.9.10  │  Control Plane 1          │
│  pve1                 │  k8s-w1       │  192.168.9.10  │  Worker 1                 │
│  pve2                 │  k8s-cp2     │  192.168.9.11  │  Control Plane 2          │
│  pve2                 │  k8s-w2       │  192.168.9.20  │  Worker 2                 │
│  pve3                 │  k8s-cp3     │  192.168.9.12  │  Control Plane 3          │
│  pve3                 │  k8s-w3       │  192.168.9.30  │  Worker 3                 │
│  (LB dedicato)        │  haproxy-lb   │  192.168.9.99   │  Load Balancer VIP        │
│  (NAS dedicato)       │  TrueNAS      │  192.168.9.9  │  NFS Server               │
└───────────────────────┴───────────────┴────────────────┴───────────────────────────┘
```

### 1.1 Copia e modifica terraform.tfvars

```bash
cd infrastructure/terraform

# Copia il template
cp terraform.tfvars.example terraform.tfvars

# Modifica i valori CON I TUOI DATI REALI (cerca <<< CAMBIA)
# In particolare:
#   - proxmox_api_endpoint: il tuo IP Proxmox
#   - target_nodes: i nomi REALI dei tuoi nodi Proxmox (es. "pve1", "pve2", "pve3")
#   - HA VIP: 192.168.9.99 (già configurato nell'example)
#   - truenas_nfs_server: 192.168.9.9 (già configurato nell'example)
```

### 1.2 Esegui Terraform

```bash
# Inizializza i provider
terraform init

# Verifica il piano (non fa cambiamenti)
terraform plan

# Applica (crea le 7 VM: 6 K8s + 1 HAProxy)
terraform apply
```

Se tutto va bene, vedrai:
```
Plan: 7 to add, 0 to change, 0 to destroy.
Do you want to perform these actions?
  [yes/no]: yes
...
Apply complete! Resources: 7 added, 0 changed, 0 destroyed.
```

---

## FASE 2 — Bootstrap del Cluster HA (45 minuti)

### 2.1 Download Talos ISO (fatto da Terraform)

Terraform scarica automaticamente la ISO di Talos dalla Image Factory.

### 2.2 Bootstrap con il VIP (NON un singolo nodo!)

```bash
cd ../../scripts/

# Esegui lo script di bootstrap (usa la VIP del Load Balancer!)
./bootstrap-talos.sh
```

Lo script fa automaticamente:
1. **Bootstrap del cluster** tramite il VIP (HAProxy bilancia verso 1 nodo CP)
2. **Estrazione del kubeconfig** dal VIP
3. **Applicazione della config Talos** a tutti e 6 i nodi
4. **Verifica del cluster** (kubectl get nodes)

### 2.3 Verifica il cluster

```bash
# Controlla i nodi (dovresti vedere 6 nodi)
kubectl get nodes

# Controlla etcd (dovresti vedere 3 membri — i 3 CP)
talosctl get etcdmember -A

# Controlla i pod di sistema
kubectl get pods -A -n kube-system
```

---

## FASE 3 — Installa Flux CD (20 minuti)

```bash
# Bootstrap di Flux contro il tuo repository GitHub
flux bootstrap github \
  --owner=TUO-USERNAME \
  --repository=k3s-talos-homelab \
  --branch=main \
  --path=./flux \
  --personal

# Verifica:
kubectl get pods -n flux-system
```

---

## FASE 4 — Backup con Proxmox Backup Server (PBS)

### 4.1 Installa/configura PBS sul tuo server

PBS può essere un server dedicato o una VM su Proxmox.

### 4.2 Configura il backup delle VM del cluster

```bash
# Collegati al PBS:
pbs plugin <PBS-HOST>

# Aggiungi il repository di backup:
pbs repository add k8s-backup <PATH-ON-PBS>

# Backup manuale di una VM:
pbs backup create --node <PBS-HOST> --vmid 9200 --type vm

# Backup di tutte le VM del cluster (script):
for vmid in 9200 9201 9202 9300 9301 9302; do
  pbs backup create --node <PBS-HOST> --vmid $vmid --type vm
done
```

### 4.3 Schedule automatizzata (opzionale)

```bash
# Configura un cronjob su PBS per backup automatici:
# /etc/pbs/pbs.conf
# Inizia con snapshot ogni 6 ore, retention 7 giorni
```

### 4.4 IMPORTANT — Backup PBS non va confuso con i dati del cluster!

- **Dati del cluster:** vivono sul TrueNAS (NFS)
- **Backup delle VM:** gestiti da PBS (snapshot a livello hypervisor)
- **I due sono indipendenti:** puoi perdere il cluster K8s e ricostruirlo da PBS
- **I dati del cluster** rimangono sul TrueNAS (backup esterni)

---

## FASE 5 — Configura Renovate (5 minuti)

### 5.1 Commit il file Renovate

```bash
# 1. Installa Renovate su GitHub:
#    https://github.com/apps/renovate

# 2. Abilita Fluxbot per schematics:
#    https://github.com/apps/fluxbot

# 3. Commit il file:
git add renovate.json5 infrastructure/renovate/fluxbot-rules.json5
git commit -m "feat: add renovate configuration for 3+3 HA cluster"
git push
```

### 5.2 Come funziona

1. **Ogni 4 ore** (default), Renovate controlla la tua repo
2. Trova tutte le dipendenze (Talos, K3s, Terraform, Flux, NFS CSI, immagini Docker)
3. **Crea PR automaticamente** con il changelog
4. Approvi la PR con un merge → **il tuo cluster si aggiorna da solo**

---

## FASE 6 — Deploy di Applicazioni con Flux (30 minuti)

### 6.1 Deploy un'app di esempio

```bash
# 1. Crea il manifest
git add flux/apps/example-deployment.yaml
git commit -m "feat: add example nginx deployment with NFS storage"
git push

# 2. Flux lo applicherà automaticamente
# 3. Verifica:
kubectl get pods -n example
kubectl get svc -n example
kubectl get pvc -n example  # PVC su NFS TrueNAS
```

---

## Checklist Finale

Segui questa checklist per verificare che tutto funzioni:

- [ ] Terraform ha creato 7 VM su Proxmox (6 K8s + 1 HAProxy)
- [ ] Talos Linux è installato su tutte le VM K8s
- [ ] Il cluster K3s è bootstrap (kubectl get nodes → 6 nodi Ready)
- [ ] Etcd ha 3 membri (talosctl get etcdmember -A)
- [ ] HAProxy VIP (192.168.9.99) funziona (kubectl get nodes via VIP)
- [ ] Flux CD è installato (`kubectl get pods -n flux-system`)
- [ ] Flux ha applicato le apps dalla tua repo (`flux sync`)
- [ ] Renovate è installato come GitHub App
- [ ] NFS CSI montato dal TrueNAS (kubectl get sc true-nas-nfs)
- [ ] PBS backup configurato per tutte le 6 VM

## Troubleshooting

### Problema: etcd non ha 3 membri

```bash
# Verifica che tutti i 3 CP siano raggiungibili:
talosctl health --nodes 192.168.9.10,192.168.9.11,192.168.9.12

# Controlla i log di etcd su un CP:
talosctl logs etcd --nodes 192.168.9.10

# Se un nodo non si une al cluster etcd, controlla la config:
talosctl get etcdmember -A
```

### Problema: HAProxy VIP non risponde

```bash
# Verifica che HAProxy sia in esecuzione:
# (via Proxmox UI, console della VM haproxy-lb)

# Controlla i log:
tail -f /var/log/haproxy.log

# Verifica che il VIP sia assegnato all'interfaccia:
ip addr show | grep 192.168.9.99

# Se il VIP non è assegnato, riavvia HAProxy:
systemctl restart haproxy
```

### Problema: NFS dal TrueNAS non monta

```bash
# Verifica il mount manuale da un nodo worker:
talosctl shell --nodes 192.168.9.10
mount -t nfs 192.168.9.9:/mnt/pool/kubernetes /mnt

# Controlla l'esport NFS sul TrueNAS (UI TrueNAS):
# Services → NFS → Export → verifica path e permessi

# Verifica la storage class:
kubectl get sc true-nas-nfs
```

---

## Risorse

- [Talos Linux Docs](https://www.talos.dev/)
- [Talos on Proxmox](https://www.talos.dev/docs/v1.9/platform-specific-installations/virtualized-platforms/proxmox)
- [K3s Docs](https://docs.k3s.io/)
- [Flux CD Docs](https://fluxcd.io/)
- [Renovate Docs](https://docs.renovatebot.com/)
- [NFS CSI Driver](https://github.com/kubernetes-csi/csi-driver-nfs)
- [MetalLB](https://metallb.io/)
- [Proxmox Backup Server](https://www.proxmox.com/en/proxmox-backup-server)
- [docs/network.md](../network.md) — Documentazione completa della rete (nuovo!)
