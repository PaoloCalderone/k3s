# UDM Pro Configuration Instructions — Technitium DNS

## Summary

Technitium DNS will be exposed on MetalLB IP: **192.168.9.53**

You need to configure the UDM Pro router to:
1. Resolve `*.unifi.localdomain` names pointing to Traefik
2. Distribute Technitium as DNS server to all clients via DHCP

---

## Phase 1: Reserve the Technitium IP in DHCP

### Objective
Ensure 192.168.9.53 is not assigned to a physical device.

### Router Action
1. Access the **UniFi Network Controller** (https://<udm-ip>:8443)
2. Go to **Settings** → **Networks**
3. Select the **UDM-Pro LAN** network (or the device network)
4. Scroll down to **LAN** settings
5. Verify that the **DHCP Range** does not include 192.168.9.53
   - Example: if the range is `192.168.9.100-192.168.9.200`, 53 is already out of range ✅
   - If the range includes .53, narrow it (e.g., `192.168.9.54-192.168.9.200`)

### Alternative: Static DHCP reservation (optional)
If you want to be sure .53 is not used:
1. Settings → Network → LAN
2. **Static DHCP** → Add
3. Assign 192.168.9.53 to a fake MAC (not used by any device)
4. This blocks the IP without assigning it to a real device

---

## Phase 2: Configure DNS Server for Clients (DHCP Option 6)

### Objective
Make all devices on the network receive Technitium (192.168.9.53) as their DNS server.

### Method A — UniFi Controller (GUI)

1. Access the **UniFi Network Controller**
2. **Settings** → **Networks** → Select your LAN
3. Scroll to the **LAN** section
4. Find the **DNS Server 1** (or **DNS 1**) field
5. Enter: `192.168.9.53`
6. (Optional) **DNS Server 2**: leave empty or enter `8.8.8.8`
7. Click **Save**
8. Reboot clients (or run `dhclient -r && dhclient` to refresh DHCP)

### Method B — Via SSH on the router (advanced)

If the GUI does not allow DNS modification:

1. SSH to the router:
   ```bash
   ssh ubnt@<udm-pro-ip>
   # Password: your router login password
   ```

2. Enter ubnt shell:
   ```bash
   sudo enter_ubnt
   ```

3. Modify the DHCP configuration:
   ```bash
   #BACKUP
   cp /etc/udm-pro/dnsmasq.d/01-home.conf /etc/udm-pro/dnsmasq.d/01-home.conf.bak
   
   # MODIFY
   vi /etc/udm-pro/dnsmasq.d/01-home.conf
   ```

4. Add these lines to the file:
   ```
   # DNS server for the local network
   dhcp-option=6,192.168.9.53
   ```

5. Restart dnsmasq:
   ```bash
   /etc/init.d/S50dnsmasq restart
   ```

6. Verify:
   ```bash
   grep -r "dhcp-option=6" /etc/udm-pro/dnsmasq.d/
   ```

---

## Phase 3: Configure Custom DNS on UDM Pro (optional)

Technitium must resolve `*.unifi.localdomain`. This can be done in two ways:

### Method A — Configure Technitium to resolve wildcard

Access the **Technitium Web UI** (once the pod is running):
```
http://192.168.9.53:80
```

1. Login (user: `admin`, password: the one you set)
2. Go to **Tools** → **DNS Console**
3. In the **Zone Management** section, click **Add New Zone**
4. Zone Name: `unifi.localdomain`
5. Type: **Primary**
6. In the DNS editor, add a record:
   - Type: `A`
   - Name: `@` (or `*` for wildcard)
   - IP: `192.168.9.200` (MetalLB IP of Traefik)
   - TTL: `300`

### Method B — Configure DNS on the router

If the router supports custom DNS:

1. SSH to the router (as above)
2. Add a DNS record in dnsmasq:
   ```bash
   echo "address=/unifi.localdomain/192.168.9.200" >> /etc/udm-pro/dnsmasq.d/01-home.conf
   /etc/init.d/S50dnsmasq restart
   ```

**Note**: Method A (Technitium) is preferred because it is centralized in the cluster.

---

## Phase 4: Verification

After configuring the router, verify from a client (laptop/phone):

### On Linux/Mac
```bash
# Verify DNS is Technitium
nmcli dev show | grep DNS
# You should see: DNS [1]: 192.168.9.53

# Verify DNS resolution
dig @192.168.9.53 grafana.unifi.localdomain
dig @192.168.9.53 prometheus.unifi.localdomain
dig @192.168.9.53 homepage.unifi.localdomain
```

### On Windows
```powershell
# Verify DNS
ipconfig /all | findstr "DNS"

# Verify resolution
nslookup grafana.unifi.localdomain 192.168.9.53
```

### On Android/iOS
- Check WiFi settings → network details → DNS server
- It should show 192.168.9.53

---

## Quick Summary

| Step | Action | Where |
|------|--------|-------|
| 1 | Verify .53 is outside DHCP range | UniFi Controller |
| 2 | Set DNS 1 = 192.168.9.53 | UniFi Controller (GUI) or SSH (advanced) |
| 3 | Configure wildcard DNS in Technitium | After Technitium is operational |
| 4 | Verify resolution | From a network client |

---

## Troubleshooting

### Clients do not receive the new DNS
- On Android/iOS: Disconnect and reconnect to WiFi
- On Windows: `ipconfig /release && ipconfig /renew`
- On Mac: Disconnect WiFi → reconnect

### Technitium does not respond
- Verify the pod is Running:
  ```bash
  kubectl get pods -n dns
  kubectl get svc -n dns
  ```
- Verify the IP is assigned:
  ```bash
  kubectl get svc/technitium-dns -n dns -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
  ```

### DNS works but does not resolve unifi.localdomain
- Check the zone in Technitium Web UI
- Ensure the wildcard record points to 192.168.9.200 (Traefik)
