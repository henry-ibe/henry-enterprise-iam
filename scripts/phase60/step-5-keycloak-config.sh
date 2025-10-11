#!/bin/bash
# scripts/phase60/step-5-keycloak-config.sh - Create Keycloak realm configuration

set -e

PROJECT_ROOT="$(pwd)"
PHASE60_ROOT="$PROJECT_ROOT/phase60"
KEYCLOAK_DIR="$PHASE60_ROOT/keycloak"
ENV_FILE="$PHASE60_ROOT/.env"

echo "=== Phase 60 Step 5: Keycloak Realm Configuration ==="
echo ""

# Check if .env exists
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Error: .env file not found"
    echo "Please run step-2-environment.sh first"
    exit 1
fi

# Load environment variables
source "$ENV_FILE"

echo "📝 Creating Keycloak realm export file..."
echo ""

# Create realm-export.json
cat > "$KEYCLOAK_DIR/realm-export.json" << EOF
{
  "realm": "${KEYCLOAK_REALM}",
  "enabled": true,
  "sslRequired": "none",
  "registrationAllowed": false,
  "loginTheme": "keycloak",
  "accountTheme": "keycloak",
  "adminTheme": "keycloak",
  "emailTheme": "keycloak",
  "accessTokenLifespan": 300,
  "accessTokenLifespanForImplicitFlow": 900,
  "ssoSessionIdleTimeout": 1800,
  "ssoSessionMaxLifespan": 36000,
  "offlineSessionIdleTimeout": 2592000,
  "roles": {
    "realm": [
      {
        "name": "hr",
        "description": "Human Resources role - access to HR portal",
        "composite": false,
        "clientRole": false
      },
      {
        "name": "it_support",
        "description": "IT Support role - access to IT portal",
        "composite": false,
        "clientRole": false
      },
      {
        "name": "sales",
        "description": "Sales role - access to sales portal",
        "composite": false,
        "clientRole": false
      },
      {
        "name": "admin",
        "description": "Administrator role - full access to all portals",
        "composite": false,
        "clientRole": false
      }
    ]
  },
  "clients": [
    {
      "clientId": "${OAUTH2_PROXY_CLIENT_ID}",
      "name": "Employee Portal",
      "description": "OAuth2 client for employee portal access",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": false,
      "bearerOnly": false,
      "standardFlowEnabled": true,
      "implicitFlowEnabled": false,
      "directAccessGrantsEnabled": true,
      "serviceAccountsEnabled": false,
      "redirectUris": [
        "https://${PORTAL_DOMAIN}/*",
        "https://${PORTAL_DOMAIN}/oauth2/callback",
        "http://${PORTAL_DOMAIN}/*",
        "http://${PORTAL_DOMAIN}/oauth2/callback"
      ],
      "webOrigins": ["+"],
      "attributes": {
        "pkce.code.challenge.method": "S256",
        "post.logout.redirect.uris": "+"
      },
      "secret": "${OAUTH2_PROXY_CLIENT_SECRET}",
      "protocolMappers": [
        {
          "name": "groups",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-group-membership-mapper",
          "consentRequired": false,
          "config": {
            "full.path": "false",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "claim.name": "groups",
            "userinfo.token.claim": "true"
          }
        },
        {
          "name": "realm-roles",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-usermodel-realm-role-mapper",
          "consentRequired": false,
          "config": {
            "multivalued": "true",
            "user.attribute": "foo",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "claim.name": "roles",
            "jsonType.label": "String"
          }
        },
        {
          "name": "email",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-usermodel-property-mapper",
          "consentRequired": false,
          "config": {
            "userinfo.token.claim": "true",
            "user.attribute": "email",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "claim.name": "email",
            "jsonType.label": "String"
          }
        },
        {
          "name": "preferred_username",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-usermodel-property-mapper",
          "consentRequired": false,
          "config": {
            "userinfo.token.claim": "true",
            "user.attribute": "username",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "claim.name": "preferred_username",
            "jsonType.label": "String"
          }
        }
      ]
    }
  ],
  "users": [
    {
      "username": "alice.hr",
      "enabled": true,
      "emailVerified": true,
      "email": "alice@${DOMAIN}",
      "firstName": "Alice",
      "lastName": "Henderson",
      "realmRoles": ["hr"],
      "credentials": [
        {
          "type": "password",
          "value": "HRPass123!",
          "temporary": false
        }
      ]
    },
    {
      "username": "bob.it",
      "enabled": true,
      "emailVerified": true,
      "email": "bob@${DOMAIN}",
      "firstName": "Bob",
      "lastName": "Technical",
      "realmRoles": ["it_support"],
      "credentials": [
        {
          "type": "password",
          "value": "ITPass123!",
          "temporary": false
        }
      ]
    },
    {
      "username": "carol.sales",
      "enabled": true,
      "emailVerified": true,
      "email": "carol@${DOMAIN}",
      "firstName": "Carol",
      "lastName": "Seller",
      "realmRoles": ["sales"],
      "credentials": [
        {
          "type": "password",
          "value": "SalesPass123!",
          "temporary": false
        }
      ]
    },
    {
      "username": "admin",
      "enabled": true,
      "emailVerified": true,
      "email": "admin@${DOMAIN}",
      "firstName": "System",
      "lastName": "Administrator",
      "realmRoles": ["admin", "hr", "it_support", "sales"],
      "credentials": [
        {
          "type": "password",
          "value": "AdminPass123!",
          "temporary": false
        }
      ]
    }
  ]
}
EOF

echo "✅ Created: realm-export.json"
echo ""

# Validate JSON syntax
echo "🧪 Validating JSON syntax..."
if command -v python3 &> /dev/null; then
    python3 << 'PYEOF'
import json
import sys

try:
    with open('phase60/keycloak/realm-export.json', 'r') as f:
        data = json.load(f)
    print(f"  ✅ realm-export.json - Valid JSON")
    print(f"  📊 Realm: {data['realm']}")
    print(f"  📊 Roles: {len(data['roles']['realm'])} realm roles")
    print(f"  📊 Clients: {len(data['clients'])} client(s)")
    print(f"  📊 Users: {len(data['users'])} user(s)")
except Exception as e:
    print(f"  ❌ realm-export.json - Invalid: {e}")
    sys.exit(1)
PYEOF
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✅ JSON validation passed"
    else
        echo ""
        echo "❌ JSON validation failed"
        exit 1
    fi
else
    echo "  ⏭️  Python3 not available, skipping JSON validation"
fi

echo ""
echo "📋 Configuration Summary:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Realm: ${KEYCLOAK_REALM}"
echo ""
echo "Roles configured:"
echo "  • hr          - Human Resources"
echo "  • it_support  - IT Support"
echo "  • sales       - Sales Team"
echo "  • admin       - Administrator (all roles)"
echo ""
echo "Test users created:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "%-15s %-20s %-15s %-s\n" "USERNAME" "EMAIL" "PASSWORD" "ROLE(S)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "%-15s %-20s %-15s %-s\n" "alice.hr" "alice@${DOMAIN}" "HRPass123!" "hr"
printf "%-15s %-20s %-15s %-s\n" "bob.it" "bob@${DOMAIN}" "ITPass123!" "it_support"
printf "%-15s %-20s %-15s %-s\n" "carol.sales" "carol@${DOMAIN}" "SalesPass123!" "sales"
printf "%-15s %-20s %-15s %-s\n" "admin" "admin@${DOMAIN}" "AdminPass123!" "all roles"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "OAuth2 Client configured:"
echo "  • Client ID: ${OAUTH2_PROXY_CLIENT_ID}"
echo "  • Redirect URIs: https://${PORTAL_DOMAIN}/*"
echo "  • Protocol: OpenID Connect"
echo ""

echo "✅ Step 5 Complete: Keycloak realm configuration ready"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚠️  Security Note:"
echo "The test users have simple passwords for development."
echo "In production, enforce strong password policies!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next: Step 6 - Create OAuth2-Proxy configuration"
