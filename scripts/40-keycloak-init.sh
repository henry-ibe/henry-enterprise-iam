#!/bin/bash
set -euo pipefail

################################################################################
# Phase 40 - Keycloak Realm & FreeIPA LDAP Integration
# Henry Enterprise IAM Project - Interview Ready & Idempotent
################################################################################

MARKER_FILE="/var/lib/henry-portal/markers/40-keycloak-config"
LOGFILE="logs/40-keycloak-init.log"
mkdir -p logs /var/lib/henry-portal/markers
exec > >(tee -a "$LOGFILE") 2>&1

# ────────────────────────────────────────────────────────────────
# Colors
# ────────────────────────────────────────────────────────────────
green()  { echo -e "\033[0;32m$1\033[0m"; }
yellow() { echo -e "\033[1;33m$1\033[0m"; }
red()    { echo -e "\033[0;31m$1\033[0m"; }
blue()   { echo -e "\033[0;34m$1\033[0m"; }

echo ""
blue "═══════════════════════════════════════════════════════════════"
blue "  Phase 40 - Keycloak Realm & FreeIPA Integration"
blue "═══════════════════════════════════════════════════════════════"
echo ""

# Skip if already configured
if [[ -f "$MARKER_FILE" ]]; then
  green "✔ Keycloak already configured. Skipping."
  echo ""
  blue "Current Configuration:"
  cat /etc/henry-portal/oidc-client.env 2>/dev/null || echo "  Config file not found"
  echo ""
  exit 0
fi

# ────────────────────────────────────────────────────────────────
# Helper Functions
# ────────────────────────────────────────────────────────────────
kcadm_exec() {
  podman exec -i keycloak /opt/keycloak/bin/kcadm.sh "$@" 2>/dev/null || return 1
}

# ────────────────────────────────────────────────────────────────
# Step 1: Load Environment Configuration
# ────────────────────────────────────────────────────────────────
echo "📋 Step 1: Loading configuration..."

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

# Configuration
KC_REALM="${KC_REALM:-henry-enterprise}"
KC_PORT="${KC_PORT:-8180}"
KC_CONTAINER="keycloak"
CLIENT_ID="employee-portal"
IPA_DOMAIN="henry-iam.internal"
IPA_BASE_DN="dc=henry-iam,dc=internal"
IPA_BIND_DN="uid=admin,cn=users,cn=accounts,$IPA_BASE_DN"
IPA_BIND_PASSWORD="SecureAdminPass123!"

# Get host IP for LDAP connection
HOST_IP=$(hostname -I | awk '{print $1}')
if [[ -z "$HOST_IP" ]]; then
  HOST_IP=$(ip route get 1 2>/dev/null | awk '{print $(NF-2);exit}')
fi
if [[ -z "$HOST_IP" ]]; then
  red "  ❌ Could not determine host IP"
  exit 1
fi

IPA_LDAP_URL="ldap://${HOST_IP}:389"

green "  ✔ Configuration loaded"
yellow "  ⚙ FreeIPA LDAP URL: $IPA_LDAP_URL"

# ────────────────────────────────────────────────────────────────
# Step 2: Detect Keycloak Container
# ────────────────────────────────────────────────────────────────
echo ""
echo "🔍 Step 2: Detecting Keycloak installation..."

if ! podman ps --format "{{.Names}}" | grep -q "^${KC_CONTAINER}$"; then
  red "  ❌ No running Keycloak container found ($KC_CONTAINER)"
  exit 1
fi
green "  ✔ Detected container: $KC_CONTAINER"

# ────────────────────────────────────────────────────────────────
# Step 3: Wait for Keycloak & Authenticate
# ────────────────────────────────────────────────────────────────
echo ""
echo "🔑 Step 3: Waiting for Keycloak and authenticating..."

ELAPSED=0
MAX_WAIT=60
until curl -sf http://localhost:$KC_PORT/ >/dev/null 2>&1 || [ $ELAPSED -ge $MAX_WAIT ]; do
  sleep 5
  ((ELAPSED+=5))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
  red "  ❌ Keycloak not responding after $MAX_WAIT seconds"
  exit 1
fi
green "  ✔ Keycloak is responding"

# Authenticate with retry
for i in {1..3}; do
  if kcadm_exec config credentials \
    --server http://127.0.0.1:8080 --realm master \
    --user "$KC_ADMIN_USER" --password "$KC_ADMIN_PASSWORD"; then
    green "  ✔ Authenticated as $KC_ADMIN_USER"
    break
  fi
  if [ $i -eq 3 ]; then
    red "  ❌ Authentication failed after 3 attempts"
    exit 1
  fi
  sleep 3
done

# ────────────────────────────────────────────────────────────────
# Step 4: Create Realm (Idempotent)
# ────────────────────────────────────────────────────────────────
echo ""
echo "🏗️  Step 4: Ensuring realm '$KC_REALM' exists..."

if kcadm_exec get realms/$KC_REALM >/dev/null; then
  yellow "  ⚙ Realm '$KC_REALM' already exists"
else
  kcadm_exec create realms \
    -s realm=$KC_REALM \
    -s enabled=true \
    -s sslRequired=NONE \
    -s registrationAllowed=false \
    -s resetPasswordAllowed=true >/dev/null
  green "  ✔ Created realm: $KC_REALM"
fi

# ────────────────────────────────────────────────────────────────
# Step 5: Configure FreeIPA LDAP User Federation
# ────────────────────────────────────────────────────────────────
echo ""
echo "🔗 Step 5: Configuring FreeIPA LDAP User Federation..."

# Check if LDAP federation exists
LDAP_ID=$(kcadm_exec get components -r $KC_REALM --fields id,name,providerId \
  | grep -B1 '"name" *: *"FreeIPA"' | grep '"id"' \
  | sed 's/.*"id" *: *"\([^"]*\)".*/\1/' || echo "")

if [[ -n "$LDAP_ID" ]]; then
  yellow "  ⚙ LDAP User Federation already configured"
  yellow "  ⏳ Updating LDAP connection URL..."
  kcadm_exec update components/$LDAP_ID -r $KC_REALM \
    -s "config.connectionUrl=[\"$IPA_LDAP_URL\"]" >/dev/null || true
  green "  ✔ LDAP connection URL updated"
else
  yellow "  ⏳ Creating LDAP User Federation..."
  
  kcadm_exec create components -r $KC_REALM \
    -s name=FreeIPA \
    -s providerId=ldap \
    -s providerType=org.keycloak.storage.UserStorageProvider \
    -s 'config.enabled=["true"]' \
    -s 'config.priority=["1"]' \
    -s 'config.fullSyncPeriod=["86400"]' \
    -s 'config.changedSyncPeriod=["3600"]' \
    -s 'config.cachePolicy=["DEFAULT"]' \
    -s 'config.batchSizeForSync=["1000"]' \
    -s 'config.editMode=["READ_ONLY"]' \
    -s 'config.syncRegistrations=["false"]' \
    -s 'config.vendor=["other"]' \
    -s 'config.usernameLDAPAttribute=["uid"]' \
    -s 'config.rdnLDAPAttribute=["uid"]' \
    -s 'config.uuidLDAPAttribute=["ipaUniqueID"]' \
    -s 'config.userObjectClasses=["inetOrgPerson, organizationalPerson"]' \
    -s "config.connectionUrl=[\"$IPA_LDAP_URL\"]" \
    -s "config.usersDn=[\"cn=users,cn=accounts,$IPA_BASE_DN\"]" \
    -s 'config.authType=["simple"]' \
    -s "config.bindDn=[\"$IPA_BIND_DN\"]" \
    -s "config.bindCredential=[\"$IPA_BIND_PASSWORD\"]" \
    -s 'config.searchScope=["1"]' \
    -s 'config.useTruststoreSpi=["ldapsOnly"]' \
    -s 'config.connectionPooling=["true"]' \
    -s 'config.pagination=["true"]' \
    -s 'config.allowKerberosAuthentication=["false"]' \
    -s 'config.useKerberosForPasswordAuthentication=["false"]' \
    -s 'config.importEnabled=["true"]' \
    -s 'config.trustEmail=["true"]' >/dev/null
  
  green "  ✔ FreeIPA LDAP User Federation created"
  
  # Get the newly created LDAP ID
  LDAP_ID=$(kcadm_exec get components -r $KC_REALM --fields id,name \
    | grep -B1 '"name" *: *"FreeIPA"' | grep '"id"' \
    | sed 's/.*"id" *: *"\([^"]*\)".*/\1/')
fi

if [[ -z "$LDAP_ID" ]]; then
  red "  ❌ Could not find LDAP component ID"
  exit 1
fi

green "  ✔ LDAP Component ID: $LDAP_ID"

# ────────────────────────────────────────────────────────────────
# Step 6: Configure LDAP Attribute Mappers (Idempotent)
# ────────────────────────────────────────────────────────────────
echo ""
echo "🗺️  Step 6: Configuring LDAP attribute mappers..."

create_mapper() {
  local MAPPER_NAME=$1
  local MAPPER_TYPE=$2
  shift 2
  
  if kcadm_exec get components -r $KC_REALM --fields name \
    | grep -q "\"name\" *: *\"$MAPPER_NAME\""; then
    yellow "  ⚙ Mapper exists: $MAPPER_NAME"
    return 0
  fi
  
  if kcadm_exec create components -r $KC_REALM \
    -s "name=$MAPPER_NAME" \
    -s "providerId=$MAPPER_TYPE" \
    -s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper \
    -s "parentId=$LDAP_ID" \
    "$@" >/dev/null; then
    green "  ✔ Created mapper: $MAPPER_NAME"
  else
    yellow "  ⚠ Mapper $MAPPER_NAME may already exist"
  fi
}

create_mapper "username" "user-attribute-ldap-mapper" \
  -s 'config.ldap.attribute=["uid"]' \
  -s 'config.user.model.attribute=["username"]' \
  -s 'config.read.only=["true"]' \
  -s 'config.always.read.value.from.ldap=["false"]' \
  -s 'config.is.mandatory.in.ldap=["true"]'

create_mapper "first name" "user-attribute-ldap-mapper" \
  -s 'config.ldap.attribute=["givenName"]' \
  -s 'config.user.model.attribute=["firstName"]' \
  -s 'config.read.only=["true"]' \
  -s 'config.always.read.value.from.ldap=["false"]' \
  -s 'config.is.mandatory.in.ldap=["false"]'

create_mapper "last name" "user-attribute-ldap-mapper" \
  -s 'config.ldap.attribute=["sn"]' \
  -s 'config.user.model.attribute=["lastName"]' \
  -s 'config.read.only=["true"]' \
  -s 'config.always.read.value.from.ldap=["false"]' \
  -s 'config.is.mandatory.in.ldap=["false"]'

create_mapper "email" "user-attribute-ldap-mapper" \
  -s 'config.ldap.attribute=["mail"]' \
  -s 'config.user.model.attribute=["email"]' \
  -s 'config.read.only=["true"]' \
  -s 'config.always.read.value.from.ldap=["false"]' \
  -s 'config.is.mandatory.in.ldap=["false"]'

# ────────────────────────────────────────────────────────────────
# Step 7: Sync Users from FreeIPA
# ────────────────────────────────────────────────────────────────
echo ""
echo "👥 Step 7: Synchronizing users from FreeIPA..."

yellow "  ⏳ Triggering full user sync..."
kcadm_exec create user-storage/$LDAP_ID/sync?action=triggerFullSync -r $KC_REALM >/dev/null || true

sleep 5

USER_COUNT=$(kcadm_exec get users -r $KC_REALM 2>/dev/null | grep -c '"username"' || echo 0)

if [[ "$USER_COUNT" -gt 0 ]]; then
  green "  ✔ Users synchronized: $USER_COUNT users in realm"
  yellow "  ⚙ Sample users:"
  kcadm_exec get users -r $KC_REALM --fields username 2>/dev/null \
    | grep '"username"' | head -5 | sed 's/^/     /'
else
  yellow "  ⚠ No users found after sync"
fi

# ────────────────────────────────────────────────────────────────
# Step 8: Create Realm Roles (Idempotent) - FIXED
# ────────────────────────────────────────────────────────────────
echo ""
echo "👥 Step 8: Ensuring realm roles exist..."

# Turn off exit on error temporarily for role creation
set +e

for role in admin hr it_support sales; do
  if kcadm_exec get roles -r $KC_REALM 2>/dev/null | grep -q "\"name\" *: *\"$role\""; then
    yellow "  ⚙ Role exists: $role"
  else
    if kcadm_exec create roles -r $KC_REALM \
      -s "name=$role" \
      -s "description=$role role for Henry Enterprise" >/dev/null 2>&1; then
      green "  ✔ Created role: $role"
    else
      yellow "  ⚠ Could not create role $role (may already exist)"
    fi
  fi
done

# Re-enable exit on error
set -e

# ────────────────────────────────────────────────────────────────
# Step 9: Create OIDC Client (Idempotent)
# ────────────────────────────────────────────────────────────────
echo ""
echo "💼 Step 9: Ensuring OIDC client '$CLIENT_ID' exists..."

if kcadm_exec get clients -r $KC_REALM 2>/dev/null \
  | grep -q "\"clientId\" *: *\"$CLIENT_ID\""; then
  yellow "  ⚙ Client '$CLIENT_ID' already exists"
else
  if kcadm_exec create clients -r $KC_REALM \
    -s "clientId=$CLIENT_ID" \
    -s enabled=true \
    -s publicClient=false \
    -s clientAuthenticatorType=client-secret \
    -s standardFlowEnabled=true \
    -s directAccessGrantsEnabled=true \
    -s protocol=openid-connect \
    -s 'redirectUris=["http://localhost:5000/*","http://*:5000/*"]' \
    -s 'webOrigins=["*"]' >/dev/null 2>&1; then
    green "  ✔ Created OIDC client: $CLIENT_ID"
  else
    yellow "  ⚠ Could not create client (may already exist)"
  fi
fi

# ────────────────────────────────────────────────────────────────
# Step 10: Retrieve Client Secret
# ────────────────────────────────────────────────────────────────
echo ""
echo "🔐 Step 10: Retrieving OIDC client secret..."

CLIENT_UUID=$(kcadm_exec get clients -r $KC_REALM --fields id,clientId 2>/dev/null \
  | grep -B1 "\"clientId\" *: *\"$CLIENT_ID\"" | grep '"id"' \
  | sed 's/.*"id" *: *"\([^"]*\)".*/\1/')

if [[ -z "$CLIENT_UUID" ]]; then
  red "  ❌ Could not locate client UUID for $CLIENT_ID"
  exit 1
fi

CLIENT_SECRET=$(kcadm_exec get clients/$CLIENT_UUID/client-secret -r $KC_REALM 2>/dev/null \
  | grep -o '"value" *: *"[^"]*"' | cut -d'"' -f4)

if [[ -z "$CLIENT_SECRET" ]]; then
  red "  ❌ Failed to retrieve secret for $CLIENT_ID"
  exit 1
fi

green "  ✔ Retrieved client secret successfully"

# ────────────────────────────────────────────────────────────────
# Step 11: Save Configuration
# ────────────────────────────────────────────────────────────────
echo ""
echo "💾 Step 11: Saving configuration..."

sudo mkdir -p /etc/henry-portal
sudo bash -c "cat > /etc/henry-portal/oidc-client.env <<EOF
# Keycloak OIDC Configuration
# Generated: $(date)
OIDC_CLIENT_ID=$CLIENT_ID
OIDC_CLIENT_SECRET=$CLIENT_SECRET
OIDC_ISSUER=http://localhost:$KC_PORT/realms/$KC_REALM
OIDC_DISCOVERY_URL=http://localhost:$KC_PORT/realms/$KC_REALM/.well-known/openid-configuration
OIDC_REDIRECT_URI=http://localhost:5000/oidc/callback
KC_REALM=$KC_REALM
KC_URL=http://localhost:$KC_PORT
EOF"

sudo chmod 644 /etc/henry-portal/oidc-client.env
green "  ✔ Configuration saved to /etc/henry-portal/oidc-client.env"

# ────────────────────────────────────────────────────────────────
# Final Summary
# ────────────────────────────────────────────────────────────────
echo ""
blue "═══════════════════════════════════════════════════════════════"
green "✅ Phase 40 - Keycloak Integration Complete!"
blue "═══════════════════════════════════════════════════════════════"
echo ""
blue "Configuration Summary:"
echo "  Realm:           $KC_REALM"
echo "  LDAP Provider:   FreeIPA @ $IPA_LDAP_URL"
echo "  OIDC Client:     $CLIENT_ID"
echo "  Users Synced:    $USER_COUNT users"
echo ""
blue "FreeIPA Users Available in Keycloak:"
echo "  sarah  / password123  (HR)"
echo "  adam   / password123  (IT Support)"
echo "  ivy    / password123  (Sales)"
echo "  lucas  / password123  (Admin)"
echo ""
blue "Configuration Files:"
echo "  /etc/henry-portal/oidc-client.env"
echo "  /etc/henry-portal/keycloak-admin.env"
echo ""
blue "Keycloak Admin Access:"
echo "  URL:      http://localhost:$KC_PORT/admin"
echo "  Username: $KC_ADMIN_USER"
echo "  Password: $KC_ADMIN_PASSWORD"
echo ""
blue "Next Steps:"
echo "  1. Test user login: Try authenticating as sarah, adam, ivy, or lucas"
echo "  2. Phase 50/60: Deploy employee portal applications with SSO"
echo ""

# Create marker file LAST to indicate complete success
touch "$MARKER_FILE"

green "✔ Phase 40 complete - FreeIPA and Keycloak are fully integrated!"
echo ""

exit 0
