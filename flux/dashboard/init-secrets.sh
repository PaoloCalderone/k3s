#!/bin/sh
mkdir -p /app/config
cp /app/config-template/settings.yaml /app/config/
cp /app/services-template/services.yaml /app/config/

if [ -f /app/secrets/grafana-apikey ]; then
  APIKEY=$(cat /app/secrets/grafana-apikey)
  echo "Found API key, injecting into services.yaml..."
  node -e '
    const fs = require("fs");
    const yaml = require("./node_modules/.pnpm/js-yaml@5.4.2/node_modules/js-yaml");
    const content = fs.readFileSync("/app/config/services.yaml", "utf8");
    const data = yaml.load(content);
    
    data.forEach(group => {
      Object.values(group).forEach(servicesArr => {
        servicesArr.forEach(svc => {
          const grafana = svc.Grafana || svc;
          if ((svc.name === "Grafana" || svc.Grafana) && grafana.widget && !grafana.widget.apiKeys) {
            grafana.widget.apiKeys = { default: process.env.GRAFANA_API_KEY };
          }
        });
      });
    });
    
    fs.writeFileSync("/app/config/services.yaml", yaml.dump(data, { defaultFlowStyle: false, sortKeys: false }));
    console.log("API key injected successfully");
  '
else
  echo "No API key found in /app/secrets/grafana-apikey"
fi
