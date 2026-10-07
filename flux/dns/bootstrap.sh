#!/bin/sh
# Bootstrap script for Technitium DNS
# Creates the DNS zones needed for the k3s homelab

set -e

echo "=== Technitium DNS Bootstrap ==="
echo "Waiting for Technitium to be ready..."

# Wait for the DNS server to be ready
MAX_RETRIES=30
RETRY=0
while [ $RETRY -lt $MAX_RETRIES ]; do
  if curl -s http://localhost:5380/api/user/login -d "user=admin&pass=&totp=&includeInfo=true" | grep -q '"status":"ok"'; then
    echo "Technitium DNS is ready!"
    break
  fi
  RETRY=$((RETRY + 1))
  sleep 2
done

if [ $RETRY -ge $MAX_RETRIES ]; then
  echo "ERROR: Technitium DNS did not start within the timeout"
  exit 1
fi

# Login and get token
TOKEN=$(curl -s -X POST http://localhost:5380/api/user/login \
  -d "user=admin&pass=&totp=&includeInfo=true" | \
  grep -oE '"token":"[^"]*"' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
  echo "ERROR: Could not obtain authentication token"
  exit 1
fi

echo "Token obtained successfully"

# Crea la zona forwarder per cluster.local → CoreDNS
echo "Creating cluster.local zone (Forwarder → 10.43.0.10)..."
RESULT=$(curl -s -X POST \
  "http://localhost:5380/api/zones/create?zone=cluster.local&type=Forwarder&catalog=&protocol=UDP&forwarder=10.43.0.10&dnssecValidation=false&node=this-server" \
  -H "Authorization: Bearer $TOKEN")

if echo "$RESULT" | grep -q '"status":"ok"'; then
  echo "  ✓ cluster.local zone created"
else
  echo "  ! $RESULT"
fi

# Crea la zona primaria per unifi.localdomain
echo "Creating unifi.localdomain zone (Primary)..."
RESULT=$(curl -s -X POST \
  "http://localhost:5380/api/zones/create?zone=unifi.localdomain&type=Primary&catalog=&node=this-server" \
  -H "Authorization: Bearer $TOKEN")

if echo "$RESULT" | grep -q '"status":"ok"'; then
  echo "  ✓ unifi.localdomain zone created"
else
  echo "  ! $RESULT"
fi

# Aggiunge record wildcard *.unifi.localdomain → 192.168.9.200
echo "Adding wildcard record *.unifi.localdomain → 192.168.9.200..."
RESULT=$(curl -s -X POST \
  "http://localhost:5380/api/zones/records/add?node=this-server" \
  -d "zone=unifi.localdomain&domain=*.unifi.localdomain&type=A&ttl=60&overwrite=true&comments=&expiryTtl=0&ipAddress=192.168.9.200&ptr=false&createPtrZone=false&updateSvcbHints=false" \
  -H "Authorization: Bearer $TOKEN")

if echo "$RESULT" | grep -q '"status":"ok"'; then
  echo "  ✓ Wildcard record added"
else
  echo "  ! $RESULT"
fi

echo "=== Bootstrap complete ==="
