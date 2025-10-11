#!/bin/bash
# scripts/phase60/step-2-environment.sh - Idempotent environment setup

set -e

PROJECT_ROOT="$(pwd)"
PHASE60_ROOT="$PROJECT_ROOT/phase60"
ENV_FILE="$PHASE60_ROOT/.env"

echo "=== Phase 60 Step 2: Environment Configuration ==="
echo "Working in: $PHASE60_ROOT"
echo ""

# Function to generate random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Function to generate hex password
generate_hex() {
    openssl rand -hex 16
}

# Check if .env already exists
if [ -f "$ENV_FILE" ]; then
    echo "⚠️  .env file already exists at: $ENV_FILE"
    echo ""
    read -p "Do you want to regenerate it? This will OVERWRITE existing values. (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "❌ Aborted. Keeping existing .env file."
        exit 0
    fi
    echo "📝 Backing up existing .env to .env.backup.$(date +%s)"
    cp "$ENV_FILE" "$ENV_FILE.backup.$(date +%s)"
fi

echo "🔐 Generating secure secrets..."
echo ""

# Generate secrets
COOKIE_SECRET=$(generate_password)
KC_DB_PASSWORD=$(generate_password)
OAUTH_CLIENT_SECRET=$(generate_password)
POSTGRES_PASSWORD=$(generate_password)

# Prompt for domain (or use default)
read -p "Enter your domain [default: henry-enterprise.local]: " DOMAIN
DOMAIN=${DOMAIN:-henry-enterprise.local}

read -p "Enter portal subdomain [default: portal]: " PORTAL_SUBDOMAIN
PORTAL_SUBDOMAIN=${PORTAL_SUBDOMAIN:-portal}

read -p "Enter admin email [default: admin@$DOMAIN]: " ADMIN_EMAIL
ADMIN_EMAIL=${ADMIN_EMAIL:-admin@$DOMAIN}

# Create .env file
cat > "$ENV_FILE" << EOF
# Phase 60 - Employee Portal Environment Configuration
# Generated: $(date)
# WARNING: Keep this file secure and never commit to git!

# Domain Configuration
DOMAIN=$DOMAIN
PORTAL_DOMAIN=$PORTAL_SUBDOMAIN.$DOMAIN

# Keycloak Configuration
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=SecureAdmin123!
KEYCLOAK_REALM=henry-enterprise
KC_DB_PASSWORD=$KC_DB_PASSWORD

# OAuth2 Proxy Configuration
OAUTH2_PROXY_CLIENT_ID=employee-portal
OAUTH2_PROXY_CLIENT_SECRET=$OAUTH_CLIENT_SECRET
OAUTH2_PROXY_COOKIE_SECRET=$COOKIE_SECRET

# PostgreSQL for OAuth2 Proxy Sessions
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# Traefik / TLS
ACME_EMAIL=$ADMIN_EMAIL

# Application Ports (for reference)
# Traefik: 80, 443, 8080 (dashboard)
# Keycloak: 8080 (internal)
# OAuth2-Proxy: 4180 (internal)
# Portal Router: 8500 (internal)
# HR Dashboard: 8501 (internal)
# IT Dashboard: 8502 (internal)
# Sales Dashboard: 8503 (internal)
# Admin Dashboard: 8504 (internal)
EOF

# Secure the .env file
chmod 600 "$ENV_FILE"

echo "✅ .env file created at: $ENV_FILE"
echo ""
echo "📋 Configuration Summary:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Domain:              $DOMAIN"
echo "Portal Domain:       $PORTAL_SUBDOMAIN.$DOMAIN"
echo "Admin Email:         $ADMIN_EMAIL"
echo "Keycloak Admin User: admin"
echo "Keycloak Admin Pass: SecureAdmin123!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔐 Generated secrets (stored in .env):"
echo "  • Cookie Secret: ${COOKIE_SECRET:0:8}...${COOKIE_SECRET: -8}"
echo "  • DB Password: ${KC_DB_PASSWORD:0:8}...${KC_DB_PASSWORD: -8}"
echo "  • OAuth Secret: ${OAUTH_CLIENT_SECRET:0:8}...${OAUTH_CLIENT_SECRET: -8}"
echo ""

# Add .env to .gitignore if it exists
if [ -f "$PROJECT_ROOT/.gitignore" ]; then
    if ! grep -q "phase60/.env" "$PROJECT_ROOT/.gitignore"; then
        echo "phase60/.env" >> "$PROJECT_ROOT/.gitignore"
        echo "phase60/.env.backup.*" >> "$PROJECT_ROOT/.gitignore"
        echo "✅ Added .env to .gitignore"
    fi
else
    echo "⚠️  No .gitignore found. Consider creating one to exclude .env files"
fi

echo ""
echo "✅ Step 2 Complete: Environment configured"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Next Steps:"
echo "1. Review the .env file: cat $ENV_FILE"
echo "2. Update /etc/hosts for local testing (Step 3)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
