#!/bin/bash
set -euo pipefail

################################################################################
# FreeIPA User Seeding - WORKING VERSION
# The issue: KRB5CCNAME must be set BEFORE and EXPORTED
################################################################################

LOGFILE="logs/20-freeipa.log"
PASSFILE="logs/user-passwords.txt"
mkdir -p logs
exec > >(tee -a "$LOGFILE") 2>&1

DOMAIN="henry-iam.internal"
REALM="HENRY-IAM.INTERNAL"
HOSTNAME="ipa1.$DOMAIN"
ADMIN_PASS="SecureAdminPass123!"

log() {
  echo -e "\n[+] $1"
}

################################################################################
# Check if FreeIPA is already installed
################################################################################
if [ -f /etc/ipa/default.conf ]; then
  log "⚠️  FreeIPA is already installed - skipping installation"
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
# Kerberos Authentication - THE CRITICAL FIX
################################################################################
log "🎫 Authenticating with Kerberos..."

# Destroy any existing tickets
kdestroy -A 2>/dev/null || true

# CRITICAL: Set and EXPORT KRB5CCNAME *BEFORE* kinit
export KRB5CCNAME=/tmp/krb5cc_$$
log "   Setting KRB5CCNAME=$KRB5CCNAME"

# Create a temporary password file for kinit
TMPPASS=$(mktemp)
echo "$ADMIN_PASS" > "$TMPPASS"
chmod 600 "$TMPPASS"

# Use kinit with password file (no pipe/subshell issues)
if kinit admin@"$REALM" < "$TMPPASS" 2>&1; then
  rm -f "$TMPPASS"
  log "✅ Kerberos authentication successful"
  
  # Verify the ticket
  if klist -s 2>/dev/null; then
    log "   ✓ Ticket verified"
    klist | head -3
  else
    log "❌ Ticket verification failed"
    exit 1
  fi
else
  rm -f "$TMPPASS"
  log "❌ Kerberos authentication failed"
  exit 1
fi

# VERIFY IPA can see the ticket
log "🔍 Testing IPA connectivity..."
if ipa user-show admin &>/dev/null; then
  log "   ✓ IPA commands can use Kerberos ticket"
else
  log "❌ IPA commands cannot use ticket - debugging:"
  log "   KRB5CCNAME: $KRB5CCNAME"
  log "   Ticket info:"
  klist || true
  log "   Trying 'ipa user-show admin' manually..."
  ipa user-show admin || true
  exit 1
fi

################################################################################
# Create Groups
################################################################################
log "👥 Creating groups: hr, it_support, sales, admins"

for group in hr it_support sales admins; do
  if ipa group-show "$group" &>/dev/null; then
    log "   ⚠️ Group '$group' already exists"
  else
    ipa group-add "$group" --desc="$group department"
    log "   ✓ Created group: $group"
  fi
done

################################################################################
# Create Demo Users
################################################################################
log "👤 Creating demo users with auto-passwords..."

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
    log "   ⚠️ User '$user' already exists"
    ipa group-add-member "$ROLE" --users="$user" 2>/dev/null || true
    echo "$user: (existing) - $ROLE" >> "$PASSFILE"
    continue
  fi
  
  PW=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9@#%+=' | head -c 12)
  echo "$user: $PW ($ROLE)" | tee -a "$PASSFILE"
  
  # Use echo instead of printf with heredoc
  TMPUSERPASS=$(mktemp)
  echo "$PW" > "$TMPUSERPASS"
  echo "$PW" >> "$TMPUSERPASS"
  
  ipa user-add "$user" \
    --first="${user^}" \
    --last="Demo" \
    --email="$user@$DOMAIN" \
    --password < "$TMPUSERPASS" 2>/dev/null
  
  rm -f "$TMPUSERPASS"
  
  ipa group-add-member "$ROLE" --users="$user" 2>/dev/null
  log "   ✓ Created user: $user in $ROLE"
done

chmod 600 "$PASSFILE"
log "📄 Passwords saved to $PASSFILE"

################################################################################
# Create Service Account
################################################################################
log "🤖 Creating Keycloak service account..."

KC_USER="svc-keycloak"
KC_PASS=$(openssl rand -base64 24)

if ! ipa user-show "$KC_USER" &>/dev/null; then
  TMPKCPASS=$(mktemp)
  echo "$KC_PASS" > "$TMPKCPASS"
  echo "$KC_PASS" >> "$TMPKCPASS"
  
  ipa user-add "$KC_USER" \
    --first="Keycloak" \
    --last="Service" \
    --email="$KC_USER@$DOMAIN" \
    --password < "$TMPKCPASS" 2>/dev/null
  
  rm -f "$TMPKCPASS"
  
  mkdir -p /etc/henry-portal
  cat > /etc/henry-portal/keycloak-bind.env << EOF
KC_BIND_USER=$KC_USER
KC_BIND_PASSWORD=$KC_PASS
KC_BIND_DN=uid=$KC_USER,cn=users,cn=accounts,dc=$(echo "$DOMAIN" | sed 's/\./,dc=/g')
LDAP_URI=ldap://$HOSTNAME:389
LDAP_BASE_DN=dc=$(echo "$DOMAIN" | sed 's/\./,dc=/g')
LDAP_USERS_DN=cn=users,cn=accounts,dc=$(echo "$DOMAIN" | sed 's/\./,dc=/g')
LDAP_GROUPS_DN=cn=groups,cn=accounts,dc=$(echo "$DOMAIN" | sed 's/\./,dc=/g')
EOF
  chmod 600 /etc/henry-portal/keycloak-bind.env
  log "   ✓ Created $KC_USER"
fi

################################################################################
# Summary
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
echo "Service Account: /etc/henry-portal/keycloak-bind.env"
echo "═══════════════════════════════════════════════════════════════"
echo ""

kdestroy -A 2>/dev/null || true
exit 0
