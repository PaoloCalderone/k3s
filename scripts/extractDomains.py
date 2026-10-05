#!/usr/bin/env python3
"""
extractDomains.py — Estrae i domini dalle IngressRoute Kubernetes.
Letto da updateLocalHosts.sh.

Uso: kubectl get ingressroutes -A -o json | python3 extractDomains.py
"""

import sys
import json
import re


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(1)

    domains = set()

    for item in data.get('items', []):
        spec = item.get('spec', {})
        routes = spec.get('routes', [])
        for route in routes:
            match = route.get('match', '')
            # Match: Host(`grafana.unifi.localdomain`)
            pattern = r"Host\([^`]*`([^`]+)`[^)]*\)"
            m = re.search(pattern, match)
            if m:
                host = m.group(1).strip()
                if host and '.unifi.localdomain' in host:
                    domains.add(host)

    for d in sorted(domains):
        print(d, end=' ')


if __name__ == '__main__':
    main()
