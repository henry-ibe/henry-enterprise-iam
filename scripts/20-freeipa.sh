#!/bin/bash
set -euo pipefail

################################################################################
# Phase 20 - FreeIPA Installation & Seeding (Idempotent + Auto-Healing)
# Henry Enterprise IAM Project (Interview Ready)
################################################################################

LOGFILE="logs/20-freeipa.log"
PASSFILE="logs/user-passwords.txt"
mkdir -p logs
exec > >(tee -a "$LOGFILE") 2>&1

DOMAIN="henry-iam.internal"
REALM="HENRY-IAM.INTERNAL"
HOSTNAME="ipa1.$DOMAIN"
ADMIN_PASS="SecureAdminPass123!"
MARKER_FILE="/etc/henry-portal/.freeipa-seeded"

green()  { echo -e "\033[0;32m$1\033[0m"; }
yellow() { echo -e "\033[1;33m$1\033[0m"; }
red()    { echo -e "\033[0;31m$1\033[0m"; }
log()    { echo -e "\n[+] $1"; }
fail()   { echo -e "\n[✘] $1"; exit 1; }

################################################################################
# 0. Skip if already seeded
################################################################################
if [[ -f "$MARKER_FILE" ]]; then
  log "⚠️  FreeIPA already seeded. Skipping."
  exit 0
fi

################################################################################
# 1. Install FreeIPA (if not already)
################################################################################
if [ -f /etc/ipa/default.conf ]; then
  log "⚙️  FreeIPA already installed - skipping installation"
else
  log "📦 Installing FreeIPA packages..."
  dnf install -y ipa-server ipa-server-dns bind bind-dyndb-ldap

  log "🧱 Running ipa-server-install..."
  ipa-server-install -U \
    --realm="$REALM" \
    --domain="$DOMAIN" \
    --ds-password="$ADMIN_PASS" \
    --admin-password="$ADMIN_PASS" \
    --hostname="$HOSTNAME" \
    --no-ntp \
    --setup-dns --auto-forwarders

  log "🔐 Enabling IPA services..."
  systemctl enable --now ipa.service
  log "✅ FreeIPA server installed and running."
fi

################################################################################
# 2. Ensure services are healthy and reachable
################################################################################
log "🩺 Checking FreeIPA service health..."

# Fix /etc/hosts entry
if ! getent hosts "$HOSTNAME" >/dev/null 2>&1; then
  yellow "Fixing /etc/hosts entry for $HOSTNAME..."
  grep -q "$HOSTNAME" /etc/hosts || echo "127.0.0.1 $HOSTNAME ipa1" >> /etc/hosts
fi

# Restart key services if needed
SERVICES=(ipa krb5kdc dirsrv named-pkcs11 httpd pki-tomcatd@pki-tomcat)
for svc in "${SERVICES[@]}"; do
  if ! systemctl is-active --quiet "$svc"; then
    yellow "Restarting $svc..."
    systemctl restart "$svc" || true
  fi
done

sleep 5

# Verify KDC port
if ! ss -tulpn | grep -q ':88'; then
  yellow "KDC not listening, restarting ipa..."
  systemctl restart ipa
  sleep 5
fi

log "   ✓ IPA health check complete."

################################################################################
# 3. Authenticate with Kerberos (with retry)
################################################################################
log "🎫 Authenticating with Kerberos..."

kdestroy -A 2>/dev/null || true
export KRB5CCNAME=/tmp/krb5cc_$$
log "   Using KRB5CCNAME=$KRB5CCNAME"

TMPPASS=$(mktemp)
echo "$ADMIN_PASS" > "$TMPPASS"
chmod 600 "$TMPPASS"

# Retry up to 3 times in case of timing issues
MAX_RETRIES=3
for attempt in $(seq 1 $MAX_RETRIES); do
  if kinit admin@"$REALM" < "$TMPPASS" 2>/dev/null; then
    log "✅ Kerberos authentication successful (attempt $attempt)"
    break
  fi
  if [[ "$attempt" -eq "$MAX_RETRIES" ]]; then
    rm -f "$TMPPASS"
    fail "Kerberos authentication failed after $MAX_RETRIES attempts"
  fi
  yellow "Kerberos failed (attempt $attempt), retrying in 5s..."
  sleep 5
done

rm -f "$TMPPASS"

# Verify ticket
if ! klist -s; then
  fail "Kerberos ticket not active after kinit"
else
  klist | head -3
fi

################################################################################
# 4. Verify IPA connectivity
################################################################################
log "🔍 Verifying IPA connectivity..."
if ipa user-show admin &>/dev/null; then
  log "   ✓ IPA CLI access confirmed"
else
  fail "IPA CLI cannot use ticket; check KDC or /etc/hosts"
fi

################################################################################
# 5. Create Groups
################################################################################
log "👥 Creating groups (hr, it_support, sales, admins)..."

for group in hr it_support sales admins; do
  if ipa group-show "$group" &>/dev/null; then
    log "   ⚙️  Group '$group' exists"
  else
    ipa group-add "$group" --desc="$group department"
    log "   ✓ Created group: $group"
  fi
done

################################################################################
# 6. Create Demo Users
################################################################################
log "👤 Creating demo users..."

cat > "$PASSFILE" << EOF
# Henry Enterprise IAM - User Credentials
# Generated: $(date)
# Domain: $DOMAIN
# Realm: $REALM
#
EOF

declare -A users=(
  [ivy]=sales
  [adam]=it_support
  [sarah]=hr
  [lucas]=admins
)

for user in "${!users[@]}"; do
  ROLE="${users[$user]}"
  if ipa user-show "$user" &>/dev/null; then
    log "   ⚙️  User '$user' exists"
    ipa group-add-member "$ROLE" --users="$user" 2>/dev/null || true
    echo "$user: (existing) - $ROLE" >> "$PASSFILE"
    continue
  fi

  PW=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9@#%+=' | head -c 12)
  TMPUSERPASS=$(mktemp)
  echo "$PW" > "$TMPUSERPASS"
  echo "$PW" >> "$TMPUSERPASS"

  ipa user-add "$user" \
    --first="${user^}" \
    --last="Demo" \
    --email="$user@$DOMAIN" \
    --password < "$TMPUSERPASS" 2>/dev/null || true

  rm -f "$TMPUSERPASS"
  ipa group-add-member "$ROLE" --users="$user" 2>/dev/null
  echo "$user: $PW ($ROLE)" >> "$PASSFILE"
  log "   ✓ Created user: $user ($ROLE)"
done

chmod 600 "$PASSFILE"
log "📄 Passwords saved to $PASSFILE"

################################################################################
# 7. Create Keycloak Bind Service Account
################################################################################
log "🤖 Creating Keycloak service account..."

KC_USER="svc-keycloak"
KC_PASS=$(openssl rand -base64 24)
KC_ENV="/etc/henry-portal/keycloak-bind.env"
LDAP_DN="dc=$(echo "$DOMAIN" | sed 's/\./,dc=/g')"

if ! ipa user-show "$KC_USER" &>/dev/null; then
  TMPKCPASS=$(mktemp)
  echo "$KC_PASS" > "$TMPKCPASS"
  echo "$KC_PASS" >> "$TMPKCPASS"

  ipa user-add "$KC_USER" \
    --first="Keycloak" \
    --last="Service" \
    --email="$KC_USER@$DOMAIN" \
    --password < "$TMPKCPASS" 2>/dev/null || true

  rm -f "$TMPKCPASS"

  mkdir -p /etc/henry-portal
  cat > "$KC_ENV" << EOF
KC_BIND_USER=$KC_USER
KC_BIND_PASSWORD=$KC_PASS
KC_BIND_DN=uid=$KC_USER,cn=users,cn=accounts,$LDAP_DN
LDAP_URI=ldap://$HOSTNAME:389
LDAP_BASE_DN=$LDAP_DN
LDAP_USERS_DN=cn=users,cn=accounts,$LDAP_DN
LDAP_GROUPS_DN=cn=groups,cn=accounts,$LDAP_DN
EOF
  chmod 600 "$KC_ENV"
  log "   ✓ Created Keycloak bind account and env file"
else
  log "   ⚙️  Keycloak service account already exists"
fi

################################################################################
# 8. Summary & Cleanup
################################################################################
log "🚀 FreeIPA seeding complete!"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Users:"
ipa user-find --sizelimit=20 | grep "User login:" | awk '{print "  •", $3}'
echo ""
echo "Groups:"
ipa group-find --sizelimit=20 | grep "Group name:" | awk '{print "  •", $3}'
echo ""
echo "Credentials: $PASSFILE"
echo "Service Account: $KC_ENV"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# mark completion
mkdir -p /etc/henry-portal
touch "$MARKER_FILE"

kdestroy -A 2>/dev/null || true
exit 0

