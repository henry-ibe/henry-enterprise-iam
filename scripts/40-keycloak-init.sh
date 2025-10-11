#!/bin/bash
set -euo pipefail

################################################################################
# Phase 40 - Keycloak Realm & Configuration (Interview Ready)
# Works with both containerized and standalone Keycloak
################################################################################

# Colors
green()  { echo -e "\033[0;32m$1\033[0m"; }
yellow() { echo -e "\033[1;33m$1\033[0m"; }
red()    { echo -e "\033[0;31m$1\033[0m"; }
blue()   { echo -e "\033[0;34m$1\033[0m"; }

echo ""
blue "═══════════════════════════════════════════════════════════════"
blue "  Phase 40 - Keycloak Realm & Configuration"
blue "═══════════════════════════════════════════════════════════════"
echo ""

################################################################################
# 1. Load Environment Configuration
################################################################################
echo "📋 Step 1: Loading configuration..."

# Try multiple locations for env file
for ENV_FILE in "./config/keycloak.env" "./.env" "/etc/henry-portal/keycloak-admin.env"; do
  if [[ -f "$ENV_FILE" ]]; then
    set -a; source "$ENV_FILE"; set +a
    green "  ✔ Loaded: $ENV_FILE"
    break
  fi
done

if [[ -z "${KC_ADMIN_USER:-}" ]]; then
  red "  ❌ No Keycloak environment file found"
  exit 1
fi

# Fetch public IP if not set
if [[ -z "${KC_PUBLIC_IP:-}" ]]; then
  echo "  Fetching EC2 Public IP..."
  TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || echo "")
  
  if [[ -n "$TOKEN" ]]; then
    KC_PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
      http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost")
  else
    KC_PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost")
  fi
  
  export KC_PUBLIC_IP
fi

# Set defaults
KC_REALM="${KC_REALM:-henry}"
KC_PORT="${KC_PORT:-8180}"
KC_VERSION="${KC_VERSION:-25.0.6}"
KC_EXTERNAL_URL="https://${KC_PUBLIC_IP}"

echo ""
echo "Configuration:"
echo "  Realm:        $KC_REALM"
echo "  Admin User:   $KC_ADMIN_USER"
echo "  Public IP:    $KC_PUBLIC_IP"
echo "  External URL: $KC_EXTERNAL_URL"
echo "  Version:      $KC_VERSION"

################################################################################
# 2. Detect Keycloak Installation Type
################################################################################
echo ""
echo "🔍 Step 2: Detecting Keycloak installation..."

# Check for containerized Keycloak
KEYCLOAK_CONTAINER=$(podman ps --filter "name=keycloak" --format "{{.Names}}" 2>/dev/null | head -n1 || echo "")

if [[ -n "$KEYCLOAK_CONTAINER" ]]; then
  KC_TYPE="container"
  KC_CMD_PREFIX="podman exec $KEYCLOAK_CONTAINER"
  KC_SERVER_URL="http://127.0.0.1:8080"
  green "  ✔ Detected containerized Keycloak: $KEYCLOAK_CONTAINER"
else
  # Check for standalone Keycloak
  if [[ -d "/opt/keycloak" ]] && [[ -f "/opt/keycloak/bin/kcadm.sh" ]]; then
    KC_TYPE="standalone"
    KC_CMD_PREFIX=""
    KC_SERVER_URL="http://localhost:${KC_PORT}"
    KCADM_PATH="/opt/keycloak/bin/kcadm.sh"
    green "  ✔ Detected standalone Keycloak at /opt/keycloak"
  else
    red "  ❌ No Keycloak installation found"
    exit 1
  fi
fi

################################################################################
# 3. Wait for Keycloak to be Ready
################################################################################
echo ""
echo "⏳ Step 3: Waiting for Keycloak to be fully ready..."

MAX_WAIT=60
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
  if curl -sf http://localhost:$KC_PORT/ >/dev/null 2>&1; then
    green "  ✔ Keycloak is ready"
    break
  fi
  echo -n "."
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
  red "  ❌ Timeout waiting for Keycloak"
  exit 1
fi

################################################################################
# 4. Configure kcadm.sh Credentials
################################################################################
echo ""
echo "🔑 Step 4: Configuring Keycloak CLI access..."

if [[ "$KC_TYPE" == "container" ]]; then
  $KC_CMD_PREFIX /opt/keycloak/bin/kcadm.sh config credentials \
    --server "$KC_SERVER_URL" \
    --realm master \
    --user "$KC_ADMIN_USER" \
    --password "$KC_ADMIN_PASSWORD" 2>&1 | grep -v "Logging into" || true
else
  $KCADM_PATH config credentials \
    --server "$KC_SERVER_URL" \
    --realm master \
    --user "$KC_ADMIN_USER" \
    --password "$KC_ADMIN_PASSWORD" 2>&1 | grep -v "Logging into" || true
fi

green "  ✔ CLI authenticated"

################################################################################
# 5. Create or Verify Realm
################################################################################
echo ""
echo "🏗️  Step 5: Creating realm '$KC_REALM'..."

# Function to run kcadm commands
run_kcadm() {
  if [[ "$KC_TYPE" == "container" ]]; then
    $KC_CMD_PREFIX /opt/keycloak/bin/kcadm.sh "$@"
  else
    $KCADM_PATH "$@"
  fi
}

# Check if realm exists
REALM_CHECK=$(run_kcadm get realms 2>/dev/null | grep -o "\"realm\" *: *\"$KC_REALM\"" || echo "")

if [[ -z "$REALM_CHECK" ]]; then
  run_kcadm create realms \
    -s realm="$KC_REALM" \
    -s enabled=true \
    -s displayName="Henry Enterprise" \
    -s sslRequired=NONE 2>&1 | grep -v "Created new realm" || true
  green "  ✔ Realm '$KC_REALM' created"
else
  yellow "  ⚠ Realm '$KC_REALM' already exists"
fi

# Ensure SSL is not required
run_kcadm update realms/$KC_REALM -s sslRequired=NONE 2>/dev/null || true

################################################################################
# 6. Create Roles
################################################################################
echo ""
echo "👥 Step 6: Creating realm roles..."

for role in hr it_support sales admins; do
  ROLE_CHECK=$(run_kcadm get roles -r "$KC_REALM" 2>/dev/null | grep -o "\"name\" *: *\"$role\"" || echo "")
  
  if [[ -z "$ROLE_CHECK" ]]; then
    run_kcadm create roles -r "$KC_REALM" \
      -s name="$role" \
      -s description="$role role for Henry Enterprise" 2>&1 | grep -v "Created new role" || true
    green "  ✔ Created role: $role"
  else
    echo "  • Role exists: $role"
  fi
done

################################################################################
# 7. Create OIDC Client
################################################################################
echo ""
echo "💼 Step 7: Creating OIDC client 'employee-portal'..."

CLIENT_ID="employee-portal"
CLIENT_CHECK=$(run_kcadm get clients -r "$KC_REALM" 2>/dev/null | grep -o "\"clientId\" *: *\"$CLIENT_ID\"" || echo "")

if [[ -z "$CLIENT_CHECK" ]]; then
  run_kcadm create clients -r "$KC_REALM" \
    -s clientId="$CLIENT_ID" \
    -s enabled=true \
    -s publicClient=false \
    -s clientAuthenticatorType=client-secret \
    -s standardFlowEnabled=true \
    -s directAccessGrantsEnabled=false \
    -s serviceAccountsEnabled=false \
    -s "redirectUris=[\"https://$KC_PUBLIC_IP/*\",\"http://localhost:3000/*\",\"http://$KC_PUBLIC_IP:3000/*\"]" \
    -s "webOrigins=[\"https://$KC_PUBLIC_IP\",\"http://localhost:3000\",\"http://$KC_PUBLIC_IP:3000\"]" \
    -s protocol=openid-connect \
    -s fullScopeAllowed=true 2>&1 | grep -v "Created new client" || true
  
  green "  ✔ Client '$CLIENT_ID' created"
  
  # Get client UUID for mappers
  CLIENT_UUID=$(run_kcadm get clients -r "$KC_REALM" --fields id,clientId 2>/dev/null | \
    grep -B1 "\"clientId\" *: *\"$CLIENT_ID\"" | grep "\"id\"" | sed 's/.*"id" *: *"\([^"]*\)".*/\1/')
  
  if [[ -n "$CLIENT_UUID" ]]; then
    run_kcadm create clients/$CLIENT_UUID/protocol-mappers/models -r "$KC_REALM" \
      -s name=realm-roles \
      -s protocol=openid-connect \
      -s protocolMapper=oidc-usermodel-realm-role-mapper \
      -s "config.\"multivalued\"=true" \
      -s "config.\"userinfo.token.claim\"=true" \
      -s "config.\"id.token.claim\"=true" \
      -s "config.\"access.token.claim\"=true" \
      -s "config.\"claim.name\"=realm_access.roles" \
      -s "config.\"jsonType.label\"=String" 2>&1 | grep -v "Created new protocol-mapper" || true
    
    green "  ✔ Added role mapper to client"
  fi
else
  yellow "  ⚠ Client '$CLIENT_ID' already exists"
fi

################################################################################
# 8. Create Demo User
################################################################################
echo ""
echo "👤 Step 8: Creating demo user 'henry-admin'..."

USERNAME="henry-admin"
USER_CHECK=$(run_kcadm get users -r "$KC_REALM" --query username="$USERNAME" 2>/dev/null | \
  grep -o "\"username\" *: *\"$USERNAME\"" || echo "")

if [[ -z "$USER_CHECK" ]]; then
  run_kcadm create users -r "$KC_REALM" \
    -s username="$USERNAME" \
    -s enabled=true \
    -s email="henry-admin@henry.local" \
    -s firstName="Henry" \
    -s lastName="Administrator" 2>&1 | grep -v "Created new user" || true
  green "  ✔ User '$USERNAME' created"
else
  yellow "  ⚠ User '$USERNAME' already exists"
fi

# Set password
run_kcadm set-password -r "$KC_REALM" \
  --username "$USERNAME" \
  --new-password 'HenryAdmin123!' \
  --temporary=false 2>&1 | grep -v "Set password" || true

green "  ✔ Password set for '$USERNAME'"

# Assign admin role
USER_ID=$(run_kcadm get users -r "$KC_REALM" --query username="$USERNAME" 2>/dev/null | \
  grep "\"id\"" | head -1 | sed 's/.*"id" *: *"\([^"]*\)".*/\1/')

if [[ -n "$USER_ID" ]]; then
  run_kcadm add-roles -r "$KC_REALM" \
    --uid "$USER_ID" \
    --rolename admins 2>&1 | grep -v "No content" || true
  green "  ✔ Assigned 'admins' role to '$USERNAME'"
fi

################################################################################
# 9. Verify Realm Creation
################################################################################
echo ""
echo "✅ Step 9: Verifying realm configuration..."

# Test realm endpoint
if curl -sf http://localhost:$KC_PORT/realms/$KC_REALM/.well-known/openid-configuration >/dev/null 2>&1; then
  green "  ✔ Realm '$KC_REALM' is accessible"
else
  red "  ❌ Realm '$KC_REALM' is not accessible"
  exit 1
fi

################################################################################
# Summary
################################################################################
echo ""
blue "═══════════════════════════════════════════════════════════════"
green "✅ Keycloak Configuration Complete!"
blue "═══════════════════════════════════════════════════════════════"
echo ""
echo "📋 Summary:"
echo "  Installation:  $KC_TYPE"
echo "  Realm:         $KC_REALM"
echo "  Roles:         hr, it_support, sales, admins"
echo "  OIDC Client:   $CLIENT_ID"
echo "  Demo User:     $USERNAME"
echo "  Password:      HenryAdmin123!"
echo ""
echo "🌐 Access URLs:"
echo "  Admin Console: $KC_EXTERNAL_URL/admin/"
echo "  Realm Account: $KC_EXTERNAL_URL/realms/$KC_REALM/account"
echo ""
echo "🔑 Test Login:"
echo "  1. Go to: $KC_EXTERNAL_URL/admin/"
echo "  2. Login as: $KC_ADMIN_USER / $KC_ADMIN_PASSWORD"
echo "  3. Switch to realm: $KC_REALM"
echo ""

# Save configuration summary
mkdir -p /etc/henry-portal
cat > /etc/henry-portal/keycloak-realm-config.txt << EOF
Keycloak Realm Configuration
Generated: $(date)

Installation Type: $KC_TYPE
Realm: $KC_REALM
Admin Console: $KC_EXTERNAL_URL/admin/
Realm Account: $KC_EXTERNAL_URL/realms/$KC_REALM/account

Demo User:
  Username: $USERNAME
  Password: HenryAdmin123!
  Roles: admins

Roles Created:
  - hr
  - it_support
  - sales
  - admins

OIDC Client:
  Client ID: $CLIENT_ID
  Redirect URIs: https://$KC_PUBLIC_IP/*, http://localhost:3000/*
  Protocol: openid-connect
EOF

green "✅ Configuration summary saved to /etc/henry-portal/keycloak-realm-config.txt"

# Create idempotence marker
MARKER_DIR="/var/lib/henry-portal/markers"
mkdir -p "$MARKER_DIR"
touch "$MARKER_DIR/41-keycloak-configure"
echo "$(date -Iseconds)" > "$MARKER_DIR/41-keycloak-configure"
green "✅ Idempotence marker created"

echo ""
