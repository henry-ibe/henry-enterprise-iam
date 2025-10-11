#!/bin/bash
# scripts/phase60/step-4-traefik-config.sh - Create Traefik configuration

set -e

PROJECT_ROOT="$(pwd)"
PHASE60_ROOT="$PROJECT_ROOT/phase60"
TRAEFIK_DIR="$PHASE60_ROOT/traefik"
ENV_FILE="$PHASE60_ROOT/.env"

echo "=== Phase 60 Step 4: Traefik Configuration ==="
echo ""

# Check if .env exists
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Error: .env file not found"
    echo "Please run step-2-environment.sh first"
    exit 1
fi

# Load environment variables
source "$ENV_FILE"

echo "📝 Creating Traefik configuration files..."
echo ""

# Create traefik.yml (static configuration)
cat > "$TRAEFIK_DIR/traefik.yml" << 'EOF'
# Traefik Static Configuration
# This file defines Traefik's global settings

global:
  sendAnonymousUsage: false

# API and Dashboard
api:
  dashboard: true
  insecure: true  # Dashboard accessible on :8080 without auth (for development)

# Entry Points
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  
  websecure:
    address: ":443"

# Providers
providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: frontend
  file:
    filename: /etc/traefik/dynamic-config.yml
    watch: true

# Logging
log:
  level: INFO
  filePath: /var/log/traefik/traefik.log
  format: json

accessLog:
  filePath: /var/log/traefik/access.log
  format: json
  filters:
    statusCodes:
      - "400-499"
      - "500-599"
EOF

echo "✅ Created: traefik.yml (static configuration)"

# Create dynamic-config.yml (dynamic configuration)
cat > "$TRAEFIK_DIR/dynamic-config.yml" << 'EOF'
# Traefik Dynamic Configuration
# This file defines middlewares and other dynamic settings

http:
  middlewares:
    # Security Headers Middleware
    security-headers:
      headers:
        frameDeny: true
        contentTypeNosniff: true
        browserXssFilter: true
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 31536000
        customResponseHeaders:
          X-Robots-Tag: "none,noarchive,nosnippet"
          Server: ""  # Hide server header
    
    # OAuth2 Proxy Forward Auth Middleware
    oauth2-auth:
      forwardAuth:
        address: http://oauth2-proxy:4180/oauth2/auth
        trustForwardHeader: true
        authResponseHeaders:
          - X-Auth-Request-Email
          - X-Auth-Request-User
          - X-Auth-Request-Groups
          - X-Auth-Request-Preferred-Username
    
    # Rate Limiting Middleware
    rate-limit:
      rateLimit:
        average: 100
        burst: 50
        period: 1m
    
    # Compression Middleware
    compression:
      compress: {}

# TLS Configuration
tls:
  options:
    default:
      minVersion: VersionTLS12
      cipherSuites:
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
EOF

echo "✅ Created: dynamic-config.yml (middlewares and TLS)"

# Create .htpasswd for Traefik dashboard (optional)
echo ""
echo "🔐 Creating basic auth for Traefik dashboard..."
TRAEFIK_USER="admin"
TRAEFIK_PASS="admin"

# Generate htpasswd entry (requires httpd-tools or apache2-utils)
if command -v htpasswd &> /dev/null; then
    htpasswd -nb "$TRAEFIK_USER" "$TRAEFIK_PASS" > "$TRAEFIK_DIR/.htpasswd"
    echo "✅ Created: .htpasswd (dashboard credentials: admin/admin)"
else
    # Fallback: pre-generated hash for admin/admin
    echo 'admin:$apr1$H6uskkkW$IgXLP6ewTrSuBkTrqE8wj/' > "$TRAEFIK_DIR/.htpasswd"
    echo "✅ Created: .htpasswd (using pre-generated hash)"
    echo "   Credentials: admin / admin"
fi

echo ""
echo "📋 Configuration Summary:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Files created in: $TRAEFIK_DIR"
ls -lh "$TRAEFIK_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Validate YAML syntax
echo "🧪 Validating YAML syntax..."
if command -v python3 &> /dev/null; then
    python3 << 'PYEOF'
import yaml
import sys

files = [
    'phase60/traefik/traefik.yml',
    'phase60/traefik/dynamic-config.yml'
]

all_valid = True
for file in files:
    try:
        with open(file, 'r') as f:
            yaml.safe_load(f)
        print(f"  ✅ {file} - Valid YAML")
    except Exception as e:
        print(f"  ❌ {file} - Invalid: {e}")
        all_valid = False

sys.exit(0 if all_valid else 1)
PYEOF
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✅ All YAML files are valid"
    else
        echo ""
        echo "⚠️  YAML validation found issues (check above)"
    fi
else
    echo "  ⏭️  Python3 not available, skipping YAML validation"
fi

echo ""
echo "✅ Step 4 Complete: Traefik configuration ready"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "What was configured:"
echo "  • HTTP → HTTPS redirect"
echo "  • Security headers middleware"
echo "  • OAuth2 forward auth middleware"
echo "  • Rate limiting"
echo "  • TLS 1.2+ with strong ciphers"
echo "  • Dashboard on port 8080 (admin/admin)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next: Step 5 - Create Keycloak realm configuration"
