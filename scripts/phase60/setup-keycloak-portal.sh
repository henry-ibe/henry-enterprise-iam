#!/bin/bash
# scripts/phase60/setup-keycloak-portal.sh
set -euo pipefail

################################################################################
# Phase 60 – Keycloak OIDC Client and Role Setup (Employee Portal)
# Idempotent – Safe to rerun
################################################################################

# Load shared env config
ENV_FILE="./env/phase60.portal.env"
[[ -f "$ENV_FILE" ]] || { echo "❌ Missing $ENV_FILE"; exit 1; }
set -a; source "$ENV_FILE"; set +a

# Colors
blue()   { echo -e "\033[0;34m$1\033[0m"; }
green()  { echo -e "\033[0;32m$1\033[0m"; }
yellow() { echo -e "\033[1;33m$1\033[0m"; }
red()    { echo -e "\033[0;31m$1\033[0m"; }

blue "\n═══════════════════════════════════════════════════════════════"
blue " Phase 60 – Keycloak OIDC Client + Realm Role Setup"
blue "═══════════════════════════════════════════════════════════════"

# Check dependencies
command -v kcadm.sh >/dev/null || {
  red "❌ kcadm.sh not found in PATH. Run this inside Keycloak container or bind CLI."
  exit 1
}

# Login to Keycloak
export KRB5CCNAME="/tmp/krb5cc_keycloak"
kcadm.sh config credentials \
  --server "$KC_BASE_URL" \
  --realm master \
  --user "$KC_ADMIN_USER" \
  --password "$KC_ADMIN_PASS" || {
    red "❌ Failed to authenticate with Keycloak"
    exit 1
}

echo "🔐 Connected to Keycloak at $KC_BASE_URL"

# Check if client exists
client_id="$KC_CLIENT_ID"
existing_id=$(kcadm.sh get clients -r "$KC_REALM" -q clientId="$client_id" | jq -r '.[0].id // empty')

if [[ -n "$existing_id" ]]; then
  yellow "⚠️  Client '$client_id' already exists – skipping creation"
else
  echo "➕ Creating OIDC client '$client_id'..."
  kcadm.sh create clients -r "$KC_REALM" \
    -s clientId="$client_id" \
    -s enabled=true \
    -s publicClient=false \
    -s standardFlowEnabled=true \
    -s serviceAccountsEnabled=false \
    -s 'redirectUris=["https://'"$PUBLIC_HOST"'/*"]' \
    -s 'webOrigins=["https://'"$PUBLIC_HOST"'"]' \
    -s protocol=openid-connect
  green "  ✔ Client created"
fi

# Create roles if missing
for role in hr it_support sales admins; do
  if kcadm.sh get roles -r "$KC_REALM" | jq -e ".[] | select(.name==\"$role\")" >/dev/null; then
    echo "  ✔ Role '$role' already exists"
  else
    echo "  ➕ Creating role: $role"
    kcadm.sh create roles -r "$KC_REALM" -s name="$role"
  fi

done

echo "👥 Assigning demo users to roles..."
kcadm.sh add-roles -r "$KC_REALM" --uusername henry-hr --rolename hr || true
kcadm.sh add-roles -r "$KC_REALM" --uusername henry-it --rolename it_support || true
kcadm.sh add-roles -r "$KC_REALM" --uusername henry-sales --rolename sales || true
kcadm.sh add-roles -r "$KC_REALM" --uusername henry-admin --rolename admins || true

green "\n✅ Phase 60 – Keycloak OIDC Client Setup Complete"
blue "═══════════════════════════════════════════════════════════════"

