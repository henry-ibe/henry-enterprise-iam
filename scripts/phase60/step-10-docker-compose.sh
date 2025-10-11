#!/bin/bash
# scripts/phase60/step-10-docker-compose.sh - Create Docker Compose configuration

set -e

PROJECT_ROOT="$(pwd)"
PHASE60_ROOT="$PROJECT_ROOT/phase60"
ENV_FILE="$PHASE60_ROOT/.env"

echo "=== Phase 60 Step 10: Docker Compose Configuration ==="
echo ""

# Check if .env exists
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Error: .env file not found"
    exit 1
fi

source "$ENV_FILE"

echo "📝 Creating Docker Compose file..."
echo ""

# Create docker-compose.yml
cat > "$PHASE60_ROOT/docker-compose.yml" << 'COMPOSE_EOF'
version: '3.8'

services:
  # ==================== BACKEND SERVICES ====================
  
  # PostgreSQL for Keycloak
  keycloak-db:
    image: postgres:15-alpine
    container_name: phase60-keycloak-db
    environment:
      POSTGRES_DB: keycloak
      POSTGRES_USER: keycloak
      POSTGRES_PASSWORD: ${KC_DB_PASSWORD}
    volumes:
      - keycloak-db-data:/var/lib/postgresql/data
    networks:
      - backend
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U keycloak"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  # Redis for OAuth2-Proxy session storage
  redis:
    image: redis:7-alpine
    container_name: phase60-redis
    command: redis-server --appendonly yes
    volumes:
      - redis-data:/data
    networks:
      - backend
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  # ==================== AUTHENTICATION ====================
  
  # Keycloak Identity Provider
  keycloak:
    image: quay.io/keycloak/keycloak:23.0
    container_name: phase60-keycloak
    command: start-dev --import-realm
    environment:
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://keycloak-db:5432/keycloak
      KC_DB_USERNAME: keycloak
      KC_DB_PASSWORD: ${KC_DB_PASSWORD}
      KEYCLOAK_ADMIN: ${KEYCLOAK_ADMIN}
      KEYCLOAK_ADMIN_PASSWORD: ${KEYCLOAK_ADMIN_PASSWORD}
      KC_HTTP_ENABLED: "true"
      KC_HOSTNAME_STRICT: "false"
      KC_PROXY: edge
      KC_HEALTH_ENABLED: "true"
    volumes:
      - ./keycloak/realm-export.json:/opt/keycloak/data/import/realm.json:ro
    networks:
      - frontend
      - backend
    depends_on:
      keycloak-db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health/ready"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    restart: unless-stopped

  # OAuth2-Proxy authentication gateway
  oauth2-proxy:
    image: quay.io/oauth2-proxy/oauth2-proxy:v7.5.1
    container_name: phase60-oauth2-proxy
    command:
      - --config=/etc/oauth2-proxy.cfg
    volumes:
      - ./oauth2-proxy/oauth2-proxy.cfg:/etc/oauth2-proxy.cfg:ro
    networks:
      - frontend
      - backend
    depends_on:
      - keycloak
      - redis
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:4180/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped

  # ==================== APPLICATION LAYER ====================
  
  # Portal Router - Smart role-based routing
  portal-router:
    build:
      context: ./portal-router
      dockerfile: Dockerfile
    container_name: phase60-portal-router
    networks:
      - frontend
    depends_on:
      - hr-dashboard
      - it-dashboard
      - sales-dashboard
      - admin-dashboard
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8500/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped

  # HR Dashboard
  hr-dashboard:
    build:
      context: ./dashboards/hr
      dockerfile: Dockerfile
    container_name: phase60-hr-dashboard
    networks:
      - frontend
    environment:
      - STREAMLIT_SERVER_ENABLE_XSRF_PROTECTION=true
      - STREAMLIT_SERVER_ENABLE_CORS=false
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8501/_stcore/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    restart: unless-stopped

  # IT Dashboard
  it-dashboard:
    build:
      context: ./dashboards/it
      dockerfile: Dockerfile
    container_name: phase60-it-dashboard
    networks:
      - frontend
    environment:
      - STREAMLIT_SERVER_ENABLE_XSRF_PROTECTION=true
      - STREAMLIT_SERVER_ENABLE_CORS=false
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8501/_stcore/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    restart: unless-stopped

  # Sales Dashboard
  sales-dashboard:
    build:
      context: ./dashboards/sales
      dockerfile: Dockerfile
    container_name: phase60-sales-dashboard
    networks:
      - frontend
    environment:
      - STREAMLIT_SERVER_ENABLE_XSRF_PROTECTION=true
      - STREAMLIT_SERVER_ENABLE_CORS=false
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8501/_stcore/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    restart: unless-stopped

  # Admin Dashboard
  admin-dashboard:
    build:
      context: ./dashboards/admin
      dockerfile: Dockerfile
    container_name: phase60-admin-dashboard
    networks:
      - frontend
    environment:
      - STREAMLIT_SERVER_ENABLE_XSRF_PROTECTION=true
      - STREAMLIT_SERVER_ENABLE_CORS=false
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8501/_stcore/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    restart: unless-stopped

  # ==================== FRONTEND ====================
  
  # Public Website
  public-site:
    image: nginx:alpine
    container_name: phase60-public-site
    volumes:
      - ./public-site:/usr/share/nginx/html:ro
      - ./public-site/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    networks:
      - frontend
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:80"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped

  # ==================== REVERSE PROXY ====================
  
  # Traefik Reverse Proxy
  traefik:
    image: traefik:v2.10
    container_name: phase60-traefik
    command:
      - --api.dashboard=true
      - --api.insecure=true
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --providers.docker.network=phase60_frontend
      - --providers.file.filename=/etc/traefik/dynamic-config.yml
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --log.level=INFO
      - --accesslog=true
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"  # Traefik dashboard
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik/traefik.yml:/etc/traefik/traefik.yml:ro
      - ./traefik/dynamic-config.yml:/etc/traefik/dynamic-config.yml:ro
      - traefik-logs:/var/log/traefik
    networks:
      - frontend
    labels:
      - "traefik.enable=true"
      # Dashboard
      - "traefik.http.routers.dashboard.rule=Host(`traefik.${DOMAIN}`) && (PathPrefix(`/api`) || PathPrefix(`/dashboard`))"
      - "traefik.http.routers.dashboard.entrypoints=web"
      - "traefik.http.routers.dashboard.service=api@internal"
    healthcheck:
      test: ["CMD", "traefik", "healthcheck", "--ping"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped

  # ==================== MONITORING (OPTIONAL) ====================
  
  # Prometheus
  prometheus:
    image: prom/prometheus:latest
    container_name: phase60-prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    networks:
      - backend
      - frontend
    ports:
      - "9090:9090"
    restart: unless-stopped

networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge

volumes:
  keycloak-db-data:
  redis-data:
  traefik-logs:
  prometheus-data:
COMPOSE_EOF

echo "✅ Created: docker-compose.yml"
echo ""

# Create .dockerignore
cat > "$PHASE60_ROOT/.dockerignore" << 'EOF'
.env
.env.*
*.log
__pycache__/
*.pyc
.git/
.gitignore
*.md
docker-compose.yml
EOF

echo "✅ Created: .dockerignore"
echo ""

# Create monitoring/prometheus.yml
cat > "$PHASE60_ROOT/monitoring/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF

echo "✅ Created: monitoring/prometheus.yml"
echo ""

# Create startup script
cat > "$PHASE60_ROOT/start.sh" << 'EOF'
#!/bin/bash
# Start script for Phase 60 Employee Portal

set -e

echo "=== Phase 60: Starting Employee Portal ==="
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found"
    echo "Please run the setup scripts first"
    exit 1
fi

# Load environment
source .env

echo "📋 Configuration:"
echo "  Domain: $DOMAIN"
echo "  Portal: $PORTAL_DOMAIN"
echo ""

# Build images
echo "🔨 Building Docker images..."
docker-compose build --parallel

echo ""
echo "🚀 Starting services..."
docker-compose up -d

echo ""
echo "⏳ Waiting for services to be healthy..."
sleep 10

# Check service health
echo ""
echo "📊 Service Status:"
docker-compose ps

echo ""
echo "✅ Phase 60 Employee Portal Started!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Access Points:"
echo "  • Public Site:    http://$DOMAIN"
echo "  • Employee Portal: http://$PORTAL_DOMAIN"
echo "  • Keycloak Admin: http://$DOMAIN:8080/auth/admin"
echo "  • Traefik Dashboard: http://traefik.$DOMAIN:8080"
echo "  • Prometheus:     http://localhost:9090"
echo ""
echo "Test Users:"
echo "  • alice.hr / HRPass123!"
echo "  • bob.it / ITPass123!"
echo "  • carol.sales / SalesPass123!"
echo "  • admin / AdminPass123!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "View logs: docker-compose logs -f [service-name]"
echo "Stop all: docker-compose down"
EOF

chmod +x "$PHASE60_ROOT/start.sh"
echo "✅ Created: start.sh (executable)"
echo ""

# Create stop script
cat > "$PHASE60_ROOT/stop.sh" << 'EOF'
#!/bin/bash
# Stop script for Phase 60 Employee Portal

echo "=== Phase 60: Stopping Employee Portal ==="
echo ""

docker-compose down

echo ""
echo "✅ All services stopped"
echo ""
echo "To remove volumes (WARNING: deletes all data):"
echo "  docker-compose down -v"
EOF

chmod +x "$PHASE60_ROOT/stop.sh"
echo "✅ Created: stop.sh (executable)"
echo ""

# Create status script
cat > "$PHASE60_ROOT/status.sh" << 'EOF'
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
EOF

chmod +x "$PHASE60_ROOT/status.sh"
echo "✅ Created: status.sh (executable)"
echo ""

# Create README for phase60 directory
cat > "$PHASE60_ROOT/README.md" << EOF
# Phase 60: OIDC-Protected Employee Portal

Production-grade employee portal with role-based access control using Keycloak OIDC authentication.

## Architecture

\`\`\`
Browser → Traefik → OAuth2-Proxy → Portal Router → Role-Based Dashboard
                         ↓
                    Keycloak (OIDC)
\`\`\`

## Quick Start

\`\`\`bash
# Start all services
./start.sh

# Check status
./status.sh

# View logs
docker-compose logs -f [service-name]

# Stop all services
./stop.sh
\`\`\`

## Access Points

- **Public Site**: http://${DOMAIN}
- **Employee Portal**: http://${PORTAL_DOMAIN}
- **Keycloak Admin**: http://${DOMAIN}:8080/auth/admin
  - Username: \`${KEYCLOAK_ADMIN}\`
  - Password: \`${KEYCLOAK_ADMIN_PASSWORD}\`
- **Traefik Dashboard**: http://traefik.${DOMAIN}:8080
- **Prometheus**: http://localhost:9090

## Test Users

| Username | Password | Role | Dashboard |
|----------|----------|------|-----------|
| alice.hr | HRPass123! | hr | HR Portal |
| bob.it | ITPass123! | it_support | IT Portal |
| carol.sales | SalesPass123! | sales | Sales Portal |
| admin | AdminPass123! | admin | Admin Portal (all access) |

## Services

1. **traefik** - Reverse proxy and load balancer
2. **keycloak** - Identity provider (OIDC)
3. **keycloak-db** - PostgreSQL for Keycloak
4. **oauth2-proxy** - Authentication gateway
5. **redis** - Session storage
6. **portal-router** - Smart role-based routing
7. **hr-dashboard** - HR management portal
8. **it-dashboard** - IT support portal
9. **sales-dashboard** - Sales CRM portal
10. **admin-dashboard** - System administration
11. **public-site** - Public landing page
12. **prometheus** - Metrics collection

## Troubleshooting

### Check logs for a specific service
\`\`\`bash
docker-compose logs -f keycloak
docker-compose logs -f oauth2-proxy
docker-compose logs -f portal-router
\`\`\`

### Restart a service
\`\`\`bash
docker-compose restart [service-name]
\`\`\`

### Rebuild a service
\`\`\`bash
docker-compose build [service-name]
docker-compose up -d [service-name]
\`\`\`

### Access container shell
\`\`\`bash
docker-compose exec [service-name] sh
\`\`\`

## Directory Structure

\`\`\`
phase60/
├── docker-compose.yml     # Main orchestration file
├── .env                   # Environment variables (DO NOT COMMIT)
├── start.sh              # Startup script
├── stop.sh               # Shutdown script
├── status.sh             # Status check script
├── traefik/              # Traefik configuration
├── keycloak/             # Keycloak realm configuration
├── oauth2-proxy/         # OAuth2-Proxy configuration
├── portal-router/        # Smart routing application
├── dashboards/           # Role-based dashboards
│   ├── hr/
│   ├── it/
│   ├── sales/
│   └── admin/
├── public-site/          # Public landing page
└── monitoring/           # Prometheus configuration
\`\`\`

## Security Notes

- The \`.env\` file contains sensitive secrets - never commit to git
- Test users have simple passwords for development only
- In production, enforce strong password policies in Keycloak
- Enable MFA for admin users
- Use proper TLS certificates (not self-signed)

## Next Steps

1. Configure proper TLS certificates
2. Set up external database for production
3. Enable MFA in Keycloak
4. Configure backup strategy
5. Set up monitoring alerts
6. Implement log aggregation

## Documentation

- [Keycloak Docs](https://www.keycloak.org/documentation)
- [OAuth2-Proxy Docs](https://oauth2-proxy.github.io/oauth2-proxy/)
- [Traefik Docs](https://doc.traefik.io/traefik/)
- [Streamlit Docs](https://docs.streamlit.io/)
EOF

echo "✅ Created: README.md (complete documentation)"
echo ""

echo "📋 Created Files Summary:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ls -lh "$PHASE60_ROOT"/*.{yml,sh,md} 2>/dev/null || true
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "✅ Step 10 Complete: Docker Compose configuration ready!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 ALL SETUP STEPS COMPLETE! 🎉"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next: Start the entire stack!"
echo ""
echo "cd $PHASE60_ROOT"
echo "./start.sh"
echo ""
echo "Or manually:"
echo "cd $PHASE60_ROOT"
echo "docker-compose build"
echo "docker-compose up -d"
echo ""
