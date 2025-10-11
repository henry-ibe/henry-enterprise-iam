#!/bin/bash
# Status check script for Phase 60 Employee Portal

echo "=== Phase 60: Service Status ==="
echo ""

docker-compose ps

echo ""
echo "=== Health Checks ==="
echo ""

services=("traefik" "keycloak" "oauth2-proxy" "portal-router" "hr-dashboard" "it-dashboard" "sales-dashboard" "admin-dashboard")

for service in "${services[@]}"; do
    if docker-compose ps | grep -q "$service.*Up"; then
        echo "✅ $service"
    else
        echo "❌ $service"
    fi
done

echo ""
echo "=== Resource Usage ==="
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
