# Istruzioni configurazione UDM Pro — Technitium DNS

## Riepilogo

Tecinitium DNS sarà esposto su IP MetalLB: **192.168.9.53**

Devi configurare il router UDM Pro per:
1. Risolvere i nomi `*.unifi.localdomain` puntando a Traefik
2. Distribuire Technitium come DNS server a tutti i client via DHCP

---

## Fase 1: Riservare l'IP Technitium nel DHCP

### Obiettivo
Assicurare che 192.168.9.53 non venga assegnato a un dispositivo fisico.

### Azione sul router
1. Accedi al **UniFi Network Controller** (https://<udm-ip>:8443)
2. Vai su **Settings** → **Networks**
3. Seleziona la rete **UDM-Pro LAN** (o la rete dei dispositivi)
4. Scorri fino a **LAN** settings
5. Verifica che il **DHCP Range** non includa 192.168.9.53
   - Esempio: se il range è `192.168.9.100-192.168.9.200`, 53 è già fuori range ✅
   - Se il range include .53, restringilo (es. `192.168.9.54-192.168.9.200`)

### Alternativa: Static DHCP reservation (opzionale)
Se vuoi essere sicuro che .53 non sia usato:
1. Settings → Network → LAN
2. **Static DHCP** → Add
3. Assegna 192.168.9.53 a un MAC fittizio (non usato da nessun dispositivo)
4. Questo blocca l'IP senza assegnarlo a un device reale

---

## Fase 2: Configurare DNS server per i client (DHCP Option 6)

### Obiettivo
Far sì che tutti i dispositivi della rete ricevano Technitium (192.168.9.53) come DNS server.

### Metodo A — UniFi Controller (GUI)

1. Accedi al **UniFi Network Controller**
2. **Settings** → **Networks** → Seleziona la tua LAN
3. Scorri alla sezione **LAN**
4. Trova il campo **DNS Server 1** (o **DNS 1**)
5. Inserisci: `192.168.9.53`
6. (Opzionale) **DNS Server 2**: lascia vuoto o metti `8.8.8.8`
7. Clicca **Save**
8. Riavvia i client (o fai un `dhclient -r && dhclient` per refresh DHCP)

### Metodo B — Via SSH sul router (avanzato)

Se la GUI non permette di modificare il DNS:

1. SSH sul router:
   ```bash
   ssh ubnt@<udm-pro-ip>
   # Password: quella di acceso al router
   ```

2. Entra in ungressh:
   ```bash
   sudo enter_ubnt
   ```

3. Modifica la configurazione DHCP:
   ```bash
   #BACKUP
   cp /etc/udm-pro/dnsmasq.d/01-home.conf /etc/udm-pro/dnsmasq.d/01-home.conf.bak
   
   # MODIFICA
   vi /etc/udm-pro/dnsmasq.d/01-home.conf
   ```

4. Aggiungi queste righe al file:
   ```
   # DNS server per la rete locale
   dhcp-option=6,192.168.9.53
   ```

5. Riavvia dnsmasq:
   ```bash
   /etc/init.d/S50dnsmasq restart
   ```

6. Verifica:
   ```bash
   grep -r "dhcp-option=6" /etc/udm-pro/dnsmasq.d/
   ```

---

## Fase 3: Configurare DNS personalizzato su UDM Pro (opzionale)

Tecinitium deve risolvere `*.unifi.localdomain`. Questo si fa in due modi:

### Metodo A — Configura Technitium per risolvere wildcard

Accedi alla **Web UI di Technitium** (quando il pod è avviato):
```
http://192.168.9.53:80
```

1. Login (utente: `admin`, password: quella che imposti tu)
2. Vai su **Tools** → **DNS Console**
3. Nella sezione **Zone Management**, clicca **Add New Zone**
4. Nome Zona: `unifi.localdomain`
5. Tipo: **Primary**
6. Nel DNS editor, aggiungi un record:
   - Type: `A`
   - Name: `@` (o `*` per wildcard)
   - IP: `192.168.9.200` (IP MetalLB di Traefik)
   - TTL: `300`

### Metodo B — Configurare DNS sul router

Se il router supporta DNS personalizzato:

1. SSH sul router (come sopra)
2. Aggiungi un record DNS nel dnsmasq:
   ```bash
   echo "address=/unifi.localdomain/192.168.9.200" >> /etc/udm-pro/dnsmasq.d/01-home.conf
   /etc/init.d/S50dnsmasq restart
   ```

**Nota**: Il Metodo A (Technitium) è preferito perché è centralizzato nel cluster.

---

## Fase 4: Verifica

Dopo aver configurato il router, verifica da un client (laptop/telefono):

### Su Linux/Mac
```bash
# Verifica che il DNS sia Technitium
nmcli dev show | grep DNS
# Dovresti vedere: DNS [1]: 192.168.9.53

# Verifica la risoluzione DNS
dig @192.168.9.53 grafana.unifi.localdomain
dig @192.168.9.53 prometheus.unifi.localdomain
dig @192.168.9.53 homepage.unifi.localdomain
```

### Su Windows
```powershell
# Verifica DNS
ipconfig /all | findstr "DNS"

# Verifica risoluzione
nslookup grafana.unifi.localdomain 192.168.9.53
```

### Su Android/iOS
- Controlla le impostazioni WiFi → dettagli rete → DNS server
- Dovrebbe apparire 192.168.9.53

---

## Riassunto rapida

| Step | Azione | Dove |
|------|--------|------|
| 1 | Verificare che .53 sia fuori DHCP range | UniFi Controller |
| 2 | Impostare DNS 1 = 192.168.9.53 | UniFi Controller (GUI) o SSH (advanced) |
| 3 | Configurare wildcard DNS in Technitium | Dopo che Technitium è operativo |
| 4 | Verificare la risoluzione | Da un client della rete |

---

## Troubleshooting

### I client non ricevono il nuovo DNS
- Su Android/iOS: Disconnetti e riconnetti al WiFi
- Su Windows: `ipconfig /release && ipconfig /renew`
- Su Mac: Disconnetti WiFi → riconnetti

### Technitium non risponde
- Verifica che il pod sia Running:
  ```bash
  kubectl get pods -n dns
  kubectl get svc -n dns
  ```
- Verifica che l'IP sia assegnato:
  ```bash
  kubectl get svc/technitium-dns -n dns -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
  ```

### DNS funziona ma non risolve unifi.localdomain
- Controlla la zona in Technitium Web UI
- Assicurati che il record wildcard punti a 192.168.9.200 (Traefik)
