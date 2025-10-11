#!/bin/bash
# scripts/phase60/step-6-oauth2-proxy-config.sh - Create OAuth2-Proxy configuration

set -e

PROJECT_ROOT="$(pwd)"
PHASE60_ROOT="$PROJECT_ROOT/phase60"
OAUTH2_DIR="$PHASE60_ROOT/oauth2-proxy"
ENV_FILE="$PHASE60_ROOT/.env"

echo "=== Phase 60 Step 6: OAuth2-Proxy Configuration ==="
echo ""

# Check if .env exists
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Error: .env file not found"
    echo "Please run step-2-environment.sh first"
    exit 1
fi

# Load environment variables
source "$ENV_FILE"

echo "📝 Creating OAuth2-Proxy configuration file..."
echo ""

# Create oauth2-proxy.cfg
cat > "$OAUTH2_DIR/oauth2-proxy.cfg" << EOF
# OAuth2-Proxy Configuration
# Authentication gateway for employee portal

# Provider Configuration
provider = "keycloak-oidc"
provider_display_name = "Henry Enterprise SSO"
redirect_url = "https://${PORTAL_DOMAIN}/oauth2/callback"
oidc_issuer_url = "http://keycloak:8080/realms/${KEYCLOAK_REALM}"

# Client Configuration
client_id = "${OAUTH2_PROXY_CLIENT_ID}"
client_secret = "${OAUTH2_PROXY_CLIENT_SECRET}"
code_challenge_method = "S256"

# Scope Configuration
scope = "openid profile email roles"
email_domains = ["*"]
insecure_oidc_allow_unverified_email = true

# Cookie Configuration
cookie_name = "_henry_oauth2"
cookie_secret = "${OAUTH2_PROXY_COOKIE_SECRET}"
cookie_domains = [".${DOMAIN}"]
cookie_secure = false
cookie_httponly = true
cookie_samesite = "lax"
cookie_expire = "24h"
cookie_refresh = "1h"

# Session Storage (Redis)
session_store_type = "redis"
redis_connection_url = "redis://redis:6379"

# Header Configuration
set_xauthrequest = true
pass_authorization_header = true
pass_access_token = false
pass_user_headers = true
set_authorization_header = true

# Upstream Configuration
upstreams = ["http://portal-router:8500"]
skip_provider_button = false

# Whitelist Configuration (health checks)
skip_auth_routes = [
  "^/health$",
  "^/ready$"
]

# Logging
request_logging = true
auth_logging = true
standard_logging = true
logging_filename = ""
logging_max_size = 100
logging_max_age = 7
logging_compress = false

# HTTP Configuration
http_address = "0.0.0.0:4180"
reverse_proxy = true

# SSL Configuration (handled by Traefik)
ssl_insecure_skip_verify = false
EOF

echo "✅ Created: oauth2-proxy.cfg"
echo ""

# Create README for OAuth2-Proxy directory
cat > "$OAUTH2_DIR/README.md" << EOF
# OAuth2-Proxy Configuration

This directory contains the OAuth2-Proxy configuration for Phase 60.

## Configuration File

- **oauth2-proxy.cfg**: Main configuration file

## Key Settings

- **Provider**: Keycloak OIDC
- **Session Storage**: Redis (persistent sessions)
- **Cookie Lifetime**: 24 hours
- **Cookie Refresh**: 1 hour

## Environment Variables Used

The following variables from \`.env\` are used:
- \`OAUTH2_PROXY_CLIENT_ID\`
- \`OAUTH2_PROXY_CLIENT_SECRET\`
- \`OAUTH2_PROXY_COOKIE_SECRET\`
- \`PORTAL_DOMAIN\`
- \`KEYCLOAK_REALM\`

## Headers Forwarded to Applications

OAuth2-Proxy forwards these headers to upstream applications:
- \`X-Auth-Request-Email\`: User's email address
- \`X-Auth-Request-User\`: Username
- \`X-Auth-Request-Groups\`: User's groups/roles (comma-separated)
- \`X-Auth-Request-Preferred-Username\`: Preferred username

## Testing

After deployment, test authentication:
1. Access: https://${PORTAL_DOMAIN}
2. You should be redirected to Keycloak login
3. After login, headers should be passed to portal-router

## Troubleshooting

### Check OAuth2-Proxy logs
\`\`\`bash
docker-compose logs -f oauth2-proxy
\`\`\`

### Test OIDC discovery
\`\`\`bash
curl http://keycloak:8080/realms/${KEYCLOAK_REALM}/.well-known/openid-configuration
\`\`\`

### Verify Redis connection
\`\`\`bash
docker-compose exec redis redis-cli ping
\`\`\`
EOF

echo "✅ Created: README.md (documentation)"
echo ""

# Validate configuration file syntax
echo "🧪 Validating configuration syntax..."

# Check for required fields
REQUIRED_FIELDS=(
    "provider"
    "client_id"
    "client_secret"
    "cookie_secret"
    "oidc_issuer_url"
    "redirect_url"
)

all_present=true
for field in "${REQUIRED_FIELDS[@]}"; do
    if grep -q "^${field} = " "$OAUTH2_DIR/oauth2-proxy.cfg"; then
        echo "  ✅ ${field} - Present"
    else
        echo "  ❌ ${field} - Missing"
        all_present=false
    fi
done

echo ""
if [ "$all_present" = true ]; then
    echo "✅ All required fields present"
else
    echo "❌ Some required fields are missing"
    exit 1
fi

echo ""
echo "📋 Configuration Summary:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Provider:        Keycloak OIDC"
echo "Client ID:       ${OAUTH2_PROXY_CLIENT_ID}"
echo "Redirect URL:    https://${PORTAL_DOMAIN}/oauth2/callback"
echo "OIDC Issuer:     http://keycloak:8080/realms/${KEYCLOAK_REALM}"
echo "Session Store:   Redis"
echo "Cookie Lifetime: 24 hours"
echo "Cookie Refresh:  1 hour"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Show file location and permissions
echo "📁 Files created:"
ls -lh "$OAUTH2_DIR"
echo ""

echo "✅ Step 6 Complete: OAuth2-Proxy configuration ready"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "What this does:"
echo "  • Authenticates users via Keycloak"
echo "  • Stores sessions in Redis"
echo "  • Forwards user identity to portal-router"
echo "  • Handles token refresh automatically"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next: Step 7 - Create public website"
