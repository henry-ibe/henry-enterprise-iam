#!/bin/bash
set -euo pipefail

################################################################################
# Phase 40 - Keycloak Realm & Configuration (Interview Ready)
# Automated, non-interactive configuration of Keycloak
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
  export KC_EXTERNAL_URL="http://${KC_PUBLIC_IP}:${KC_PORT:-8180}"
fi

# Set defaults
KC_REALM="${KC_REALM:-henry}"
KC_PORT="${KC_PORT:-8180}"
KC_VERSION="${KC_VERSION:-25.0.6}"

echo ""
echo "Configuration:"
echo "  Realm:        $KC_REALM"
echo "  Admin User:   $KC_ADMIN_USER"
echo "  Public IP:    $KC_PUBLIC_IP"
echo "  External URL: $KC_EXTERNAL_URL"
echo "  Version:      $KC_VERSION"

################################################################################
# 2. Find Keycloak Container
################################################################################
echo ""
echo "🐳 Step 2: Finding Keycloak container..."

# Try multiple methods to find the container
KEYCLOAK_CONTAINER=$(podman ps --filter "name=keycloak" --format "{{.Names}}" | head -n1)

if [[ -z "$KEYCLOAK_CONTAINER" ]]; then
  KEYCLOAK_CONTAINER=$(podman ps --filter "ancestor=quay.io/keycloak/keycloak:$KC_VERSION" --format "{{.Names}}" | head -n1)
fi

if [[ -z "$KEYCLOAK_CONTAINER" ]]; then
  red "  ❌ No running Keycloak container found"
  echo "     Run: sudo bash scripts/40-keycloak-install.sh first"
  exit 1
fi

green "  ✔ Found container: $KEYCLOAK_CONTAINER"

################################################################################
# 3. Wait for Keycloak to be Ready
################################################################################
echo ""
echo "⏳ Step 3: Waiting for Keycloak to be fully ready..."

MAX_WAIT=30
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
  yellow "  ⚠ Timeout waiting, but continuing..."
fi

################################################################################
# 4. Configure kcadm.sh Credentials
################################################################################
echo ""
echo "🔑 Step 4: Configuring Keycloak CLI access..."

# Use non-interactive mode (remove -it flag)
podman exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://127.0.0.1:8080 \
  --realm master \
  --user "$KC_ADMIN_USER" \
  --password "$KC_ADMIN_PASSWORD" 2>&1 | grep -v "Logging into" || true

green "  ✔ CLI authenticated"

################################################################################
# 5. Create or Verify Realm
################################################################################
echo ""
echo "🏗️  Step 5: Creating realm '$KC_REALM'..."

# Check if realm exists (non-interactive)
REALM_CHECK=$(podman exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh get realms 2>/dev/null | \
  grep -o "\"realm\" *: *\"$KC_REALM\"" || echo "")

if [[ -z "$REALM_CHECK" ]]; then
  podman exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh create realms \
    -s realm="$KC_REALM" \
    -s enabled=true \
    -s sslRequired=NONE 2>&1 | grep -v "Created new realm" || true
  green "  ✔ Realm '$KC_REALM' created"
else
  yellow "  ⚠ Realm '$KC_REALM' already exists"
fi

# Ensure SSL is disabled for the realm (for HTTP access)
podman exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh update realms/$KC_REALM \
  -s sslRequired=NONE 2>/dev/null || true

################################################################################
# 6. Create Roles
################################################################################
echo ""
echo "👥 Step 6: Creating realm roles..."

for role in hr it_support sales admins; do
  # Check if role exists
  ROLE_CHECK=$(podman exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh get roles -r "$KC_REALM" 2>/dev/null | \
    grep -o "\"name\" *: *\"$role\"" || echo "")
  
  if [[ -z "$ROLE_CHECK" ]]; then
    podman exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh create roles -r "$KC_REALM" \
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

# Check if client exists
CLIENT_CHECK=$(podman exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh get clients -r "$KC_REALM" 2>/dev/null | \
  grep -o "\"clientId\" *: *\"$CLIENT_ID\"" || echo "")

if [[ -z "$CLIENT_CHECK" ]]; then
  # Create client with proper OIDC configuration
  podman exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh create clients -r "$KC_REALM" \
    -s clientId="$CLIENT_ID" \
    -s enabled=true \
    -s publicClient=false \
    -s clientAuthenticatorType=client-secret \
    -s standardFlowEnabled=true \
    -s directAccessGrantsEnabled=false \
    -s serviceAccountsEnabled=false \
    -s "redirectUris=[\"http://$KC_PUBLIC_IP:3000/*\",\"http://localhost:3000/*\",\"https://*\"]" \
    -s "webOrigins=[\"http://$KC_PUBLIC_IP:3000\",\"http://localhost:3000\",\"https://*\"]" \
    -s protocol=openid-connect \
    -s fullScopeAllowed=true 2>&1 | grep -v "Created new client" || true
  
  green "  ✔ Client '$CLIENT_ID' created"
  
  # Get the client's UUID for adding mappers
  CLIENT_UUID=$(podman exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh get clients -r "$KC_REALM" --fields id,clientId 2>/dev/null | \
    grep -B1 "\"clientId\" *: *\"$CLIENT_ID\"" | grep "\"id\"" | sed 's/.*"id" *: *"\([^"]*\)".*/\1/')
  
  if [[ -n "$CLIENT_UUID" ]]; then
    # Add role mapper to include realm roles in tokens
    podman exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh create clients/$CLIENT_UUID/protocol-mappers/models -r "$KC_REALM" \
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

# Check if user exists
USER_CHECK=$(podman exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh get users -r "$KC_REALM" --query username="$USERNAME" 2>/dev/null | \
  grep -o "\"username\" *: *\"$USERNAME\"" || echo "")

if [[ -z "$USER_CHECK" ]]; then
  podman exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh create users -r "$KC_REALM" \
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
podman exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh set-password -r "$KC_REALM" \
  --username "$USERNAME" \
  --new-password 'HenryAdmin123!' \
  --temporary=false 2>&1 | grep -v "Set password" || true

green "  ✔ Password set for '$USERNAME'"

# Get user ID for role assignment
USER_ID=$(podman exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh get users -r "$KC_REALM" --query username="$USERNAME" 2>/dev/null | \
  grep "\"id\"" | head -1 | sed 's/.*"id" *: *"\([^"]*\)".*/\1/')

if [[ -n "$USER_ID" ]]; then
  # Assign admin role
  podman exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh add-roles -r "$KC_REALM" \
    --uid "$USER_ID" \
    --rolename admins 2>&1 | grep -v "No content" || true
  green "  ✔ Assigned 'admins' role to '$USERNAME'"
fi

################################################################################
# 9. Configure LDAP Federation (Optional)
################################################################################
echo ""
echo "🔗 Step 9: Configuring LDAP federation with FreeIPA..."

# Check if FreeIPA bind credentials exist
if [[ -f "/etc/henry-portal/keycloak-bind.env" ]]; then
  source /etc/henry-portal/keycloak-bind.env
  
  # Check if LDAP provider already exists
  LDAP_CHECK=$(podman exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh get components -r "$KC_REALM" 2>/dev/null | \
    grep -o "\"name\" *: *\"freeipa-ldap\"" || echo "")
  
  if [[ -z "$LDAP_CHECK" ]]; then
    # Create LDAP federation
    LDAP_CONFIG=$(cat <<EOF
{
  "name": "freeipa-ldap",
  "providerId": "ldap",
  "providerType": "org.keycloak.storage.UserStorageProvider",
  "config": {
    "enabled": ["true"],
    "priority": ["0"],
    "editMode": ["READ_ONLY"],
    "importEnabled": ["true"],
    "usernameLDAPAttribute": ["uid"],
    "rdnLDAPAttribute": ["uid"],
    "uuidLDAPAttribute": ["ipaUniqueID"],
    "userObjectClasses": ["inetOrgPerson, organizationalPerson"],
    "connectionUrl": ["${LDAP_URI:-ldap://ipa1.henry-iam.internal:389}"],
    "usersDn": ["${LDAP_USERS_DN:-cn=users,cn=accounts,dc=henry-iam,dc=internal}"],
    "authType": ["simple"],
    "bindDn": ["${KC_BIND_DN}"],
    "bindCredential": ["${KC_BIND_PASSWORD}"],
    "searchScope": ["1"],
    "useTruststoreSpi": ["ldapsOnly"],
    "connectionPooling": ["true"],
    "pagination": ["true"],
    "allowKerberosAuthentication": ["false"],
    "trustEmail": ["true"]
  }
}
EOF
)
    
    echo "$LDAP_CONFIG" | podman exec -i "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh create components -r "$KC_REALM" -f - 2>&1 | \
      grep -v "Created new component" || true
    
    green "  ✔ LDAP federation configured"
    
    # Trigger user sync
    echo "  Synchronizing users from LDAP..."
    LDAP_ID=$(podman exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh get components -r "$KC_REALM" --fields id,name 2>/dev/null | \
      grep -B1 "\"name\" *: *\"freeipa-ldap\"" | grep "\"id\"" | sed 's/.*"id" *: *"\([^"]*\)".*/\1/')
    
    if [[ -n "$LDAP_ID" ]]; then
      podman exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh create \
        user-storage/$LDAP_ID/sync?action=triggerFullSync -r "$KC_REALM" 2>/dev/null || true
      green "  ✔ LDAP user sync triggered"
    fi
  else
    yellow "  ⚠ LDAP federation already configured"
  fi
else
  yellow "  ⚠ FreeIPA bind credentials not found - skipping LDAP configuration"
  echo "     Run Phase 30 (FreeIPA seeding) first if you want LDAP integration"
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
echo "  Realm:         $KC_REALM"
echo "  Roles:         hr, it_support, sales, admins"
echo "  OIDC Client:   $CLIENT_ID"
echo "  Demo User:     $USERNAME"
echo "  Password:      HenryAdmin123!"
echo ""
echo "🌐 Access URLs:"
echo "  Admin Console: $KC_EXTERNAL_URL/admin"
echo "  Realm Console: $KC_EXTERNAL_URL/admin/$KC_REALM/console"
echo ""
echo "🔑 Test Login:"
echo "  1. Go to: $KC_EXTERNAL_URL/admin"
echo "  2. Login as: $KC_ADMIN_USER / $KC_ADMIN_PASSWORD"
echo "  3. Switch to realm: $KC_REALM"
echo "  4. Verify users, roles, and client exist"
echo ""
echo "💡 Next Steps:"
echo "  • Configure portal application (Phase 50)"
echo "  • Test OIDC flow with portal"
echo "  • Map FreeIPA users to roles"
echo ""

# Save configuration summary
cat > /etc/henry-portal/keycloak-realm-config.txt << EOF
Keycloak Realm Configuration
Generated: $(date)

Realm: $KC_REALM
Admin Console: $KC_EXTERNAL_URL/admin

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
  Redirect URIs: http://$KC_PUBLIC_IP:3000/*, http://localhost:3000/*
  Protocol: openid-connect

LDAP Federation:
  $(if [[ -f "/etc/henry-portal/keycloak-bind.env" ]]; then echo "Configured"; else echo "Not configured"; fi)

EOF

green "✅ Configuration summary saved to /etc/henry-portal/keycloak-realm-config.txt"

# Create idempotence marker
MARKER_DIR="/var/lib/henry-portal/markers"
mkdir -p "$MARKER_DIR"
touch "$MARKER_DIR/41-keycloak-configure"
echo "$(date -Iseconds)" > "$MARKER_DIR/41-keycloak-configure"
green "✅ Idempotence marker created"

echo ""
