#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Phase 50 – Apache Reverse Proxy (TLS via FreeIPA httpd)
# Supports Keycloak 25+ (no /auth base path)
# Idempotent & interview-ready
# ─────────────────────────────────────────────────────────────

# Colors
green()  { echo -e "\033[0;32m$1\033[0m"; }
yellow() { echo -e "\033[1;33m$1\033[0m"; }
red()    { echo -e "\033[0;31m$1\033[0m"; }
blue()   { echo -e "\033[0;34m$1\033[0m"; }

blue "\n═══════════════════════════════════════════════════════════════"
blue "  Phase 50 - Apache Reverse Proxy with TLS (FreeIPA httpd)"
blue "═══════════════════════════════════════════════════════════════"
echo ""

# Must be root
if [[ $EUID -ne 0 ]]; then
  red "❌ This script must be run as root (use sudo)"
  exit 1
fi

# ── Load config
ENV_FILE="./.env"
[[ -f "$ENV_FILE" ]] || ENV_FILE="./config/keycloak.env"
[[ -f "$ENV_FILE" ]] || ENV_FILE="/etc/henry-portal/keycloak-admin.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
  green "✔ Loaded: $ENV_FILE"
else
  yellow "⚠ No env file found — continuing with sensible defaults"
fi

DOMAIN="${DOMAIN:-henry-iam.internal}"
HOSTNAME="$(hostname -f)"
KC_PORT="${KC_PORT:-8180}"
PORTAL_PORT="${PORTAL_PORT:-3000}"
KC_VERSION="${KC_VERSION:-25.0.6}"

# Get public IP (AWS IMDSv2)
if [[ -z "${KC_PUBLIC_IP:-}" ]]; then
  TOKEN="$(curl -s -X PUT http://169.254.169.254/latest/api/token \
    -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' || true)"
  KC_PUBLIC_IP="$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/public-ipv4 || true)"
fi
KC_PUBLIC_IP="${KC_PUBLIC_IP:-localhost}"

cat <<CFG

Configuration:
  Hostname:    $HOSTNAME
  Public IP:   $KC_PUBLIC_IP
  Domain:      $DOMAIN
  Keycloak:    localhost:$KC_PORT
  Portal:      localhost:$PORTAL_PORT (future)

CFG

# ── Step 1: Ensure Apache installed & running
echo "🔍 Step 1: Verifying Apache (httpd) status..."
dnf install -y httpd mod_ssl >/dev/null || true
systemctl enable --now httpd

if systemctl is-active --quiet httpd; then
  green "  ✔ Apache is running"
else
  red "  ❌ Failed to start Apache"
  exit 1
fi

# ── Step 2: Ensure required modules
echo "\n📦 Step 2: Ensuring required Apache modules (proxy, ssl, headers)..."
MODULES_CONF="/etc/httpd/conf.modules.d/00-proxy-henry.conf"

# Clean out conflicting LoadModule lines from other conf.modules.d files
echo "\n🧼 Cleaning conflicting LoadModule lines from other config files..."
MODS=(proxy_module proxy_http_module proxy_wstunnel_module ssl_module headers_module)
for mod in "${MODS[@]}"; do
  mapfile -t files < <(grep -rl "LoadModule ${mod} " /etc/httpd/conf.modules.d/ | grep -v "$MODULES_CONF" || true)
  for file in "${files[@]}"; do
    sed -i "/LoadModule ${mod} /d" "$file"
    echo "  ✂ Removed LoadModule ${mod} from $file"
  done
  echo "  ✔ Ensured clean LoadModule for $mod"
done

# Recreate our module config cleanly
cat > "$MODULES_CONF" <<EOF
# Henry IAM - Custom Proxy Modules
LoadModule proxy_module          modules/mod_proxy.so
LoadModule proxy_http_module     modules/mod_proxy_http.so
LoadModule proxy_wstunnel_module modules/mod_proxy_wstunnel.so
LoadModule headers_module        modules/mod_headers.so
LoadModule ssl_module            modules/mod_ssl.so
EOF

green "  ✔ Required modules configured in $MODULES_CONF"

# ── Step 3: Create reverse proxy config
echo "\n⚙️  Step 3: Writing Keycloak proxy config..."
PROXY_CONF="/etc/httpd/conf.d/keycloak-proxy.conf"
cat > "$PROXY_CONF" <<EOF
# Henry IAM - Apache Reverse Proxy for Keycloak + Portal
ProxyPreserveHost On
ProxyRequests Off
ProxyTimeout 300

# Headers
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
Header always set X-XSS-Protection "1; mode=block"
RequestHeader set X-Forwarded-Proto "https"
RequestHeader set X-Forwarded-Port "443"

# Keycloak
ProxyPass        /admin/  http://localhost:$KC_PORT/admin/ retry=0
ProxyPassReverse /admin/  http://localhost:$KC_PORT/admin/
ProxyPass        /realms/ http://localhost:$KC_PORT/realms/ retry=0
ProxyPassReverse /realms/ http://localhost:$KC_PORT/realms/
ProxyPass        /resources/ http://localhost:$KC_PORT/resources/ retry=0
ProxyPassReverse /resources/ http://localhost:$KC_PORT/resources/

# Portal (future)
ProxyPass        /portal/ http://localhost:$PORTAL_PORT/ retry=0
ProxyPassReverse /portal/ http://localhost:$PORTAL_PORT/

# WebSocket support
RewriteEngine On
RewriteCond %{HTTP:Upgrade} =websocket [NC]
RewriteRule ^/portal/(.*) ws://localhost:$PORTAL_PORT/
RewriteCond %{HTTP:Upgrade} !=websocket [NC]
RewriteRule ^/portal/(.*) http://localhost:$PORTAL_PORT/

# Health
<Location /health>
    SetHandler server-status
    Require local
</Location>
EOF

green "  ✔ Proxy config written to $PROXY_CONF"

# ── Step 4: Validate Apache config
echo -e "\n🔍 Step 4: Validating Apache configuration..."
apache_output="$(apachectl configtest 2>&1)"

if [[ "$apache_output" == *"Syntax OK"* ]]; then
  green "  ✔ Apache configuration is valid"
  echo "$apache_output" | grep "AH[0-9]\+" && yellow "  ⚠ Apache warnings shown above (usually harmless)"
else
  red "  ❌ Apache configuration has errors:"
  echo "$apache_output"
  exit 1
fi

# ── Step 5: SELinux tweaks
if command -v getenforce >/dev/null && [[ "$(getenforce)" == "Enforcing" ]]; then
  echo "\n🛡️  Step 5: Enabling SELinux proxy permissions..."
  setsebool -P httpd_can_network_connect 1
  setsebool -P httpd_can_network_relay 1
  green "  ✔ SELinux permissions set"
else
  yellow "⚠ SELinux not enforcing — skipping"
fi

# ── Step 6: Restart Apache
echo "\n🚀 Step 6: Restarting Apache..."
systemctl restart httpd && green "  ✔ Apache restarted"

# ── Step 7: Firewall
if systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --add-service=http >/dev/null || true
  firewall-cmd --permanent --add-service=https >/dev/null || true
  firewall-cmd --reload >/dev/null || true
  green "  ✔ Firewalld allows HTTP/HTTPS"
else
  yellow "⚠ Firewalld not running — skipping"
fi

# ── Step 8: Verify proxies
curl -skI https://localhost/            >/dev/null && green "  ✔ HTTPS reachable" || yellow "  ⚠ HTTPS not responding"
curl -skI https://localhost/realms/     >/dev/null && green "  ✔ /realms proxy ok" || yellow "  ⚠ /realms proxy issue"
curl -skI https://localhost/admin/      >/dev/null && green "  ✔ /admin proxy ok" || yellow "  ⚠ /admin proxy issue"

# ── Save summary
mkdir -p /etc/henry-portal
cat > /etc/henry-portal/apache-proxy-summary.txt <<EOM
Henry IAM – Apache Reverse Proxy
Date: $(date)
Host: $HOSTNAME

Apache Version: $(httpd -v | head -1)
Public IP:      $KC_PUBLIC_IP

Keycloak: https://$KC_PUBLIC_IP/admin/
Realms:   https://$KC_PUBLIC_IP/realms/
Portal:   https://$KC_PUBLIC_IP/portal/

Logs:
  /var/log/httpd/error_log
  /var/log/httpd/ssl_error_log
EOM

mkdir -p /var/lib/henry-portal/markers
MARKER_FILE="/var/lib/henry-portal/markers/51-apache-proxy-ready"
touch "$MARKER_FILE"
echo "$(date -Iseconds)" > "$MARKER_FILE"
green "✅ Idempotence marker created: $MARKER_FILE"

blue "\n═══════════════════════════════════════════════════════════════"
green "✅ Phase 50 - Reverse Proxy with TLS Complete!"
blue "═══════════════════════════════════════════════════════════════"
echo ""
echo "📋 Summary: /etc/henry-portal/apache-proxy-summary.txt"
echo "🌐 Access:"
echo "  Keycloak: https://$KC_PUBLIC_IP/admin/"
echo "  Realm:    https://$KC_PUBLIC_IP/realms/"
echo "  Portal:   https://$KC_PUBLIC_IP/portal/"

