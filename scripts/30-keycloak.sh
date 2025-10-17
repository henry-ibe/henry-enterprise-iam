#!/bin/bash
set -euo pipefail

################################################################################
# Phase 30 - Keycloak Installation (Idempotent, Interview Ready)
# Fixed: Permission issue + Restart policy
################################################################################

MARKER_FILE="/var/lib/henry-portal/markers/40-keycloak-install"
LOGFILE="logs/30-keycloak.log"
mkdir -p logs /var/lib/henry-portal/markers /etc/henry-portal
exec > >(tee -a "$LOGFILE") 2>&1

# Colors
green()  { echo -e "\033[0;32m$1\033[0m"; }
yellow() { echo -e "\033[1;33m$1\033[0m"; }
red()    { echo -e "\033[0;31m$1\033[0m"; }
blue()   { echo -e "\033[0;34m$1\033[0m"; }

# Skip if already installed
if [[ -f "$MARKER_FILE" ]]; then
  green "✔ Keycloak already installed. Skipping."
  exit 0
fi

# Configuration
DOMAIN="henry-iam.internal"
REALM="henry"
KC_ADMIN_USER="admin"
KC_ADMIN_PASS="Admin123!@#"
KC_VERSION="25.0.6"
KC_PORT=8180
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "127.0.0.1")

yellow "Starting Keycloak installation..."

# Dependencies
yellow "Installing required packages..."
dnf install -y podman firewalld iptables || true
systemctl enable --now firewalld || true

# Check port availability
if ss -tuln | grep -q ":$KC_PORT "; then
  PROCESS=$(ss -tulpn | grep ":$KC_PORT " | awk '{print $7}' | head -1)
  if echo "$PROCESS" | grep -qE "podman|conmon"; then
    yellow "Stopping existing Keycloak container..."
    podman stop keycloak || true
    podman rm keycloak || true
  else
    red "Port $KC_PORT is in use by another process: $PROCESS"
    exit 1
  fi
fi

# Configure firewall
yellow "Configuring firewall rules..."
firewall-cmd --permanent --add-port=$KC_PORT/tcp || true
firewall-cmd --reload || true
iptables -C INPUT -p tcp --dport $KC_PORT -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport $KC_PORT -j ACCEPT
command -v iptables-save && iptables-save > /etc/sysconfig/iptables

yellow "Starting Keycloak container (version $KC_VERSION)..."

# Start Keycloak container with restart policy
podman run -d \
  --name keycloak \
  --restart=unless-stopped \
  -p $KC_PORT:8080 \
  -e KEYCLOAK_ADMIN=$KC_ADMIN_USER \
  -e KEYCLOAK_ADMIN_PASSWORD="$KC_ADMIN_PASS" \
  -e KC_HTTP_ENABLED=true \
  -e KC_HOSTNAME_STRICT=false \
  -e KC_HEALTH_ENABLED=true \
  -e KC_METRICS_ENABLED=true \
  -e KC_LOG_LEVEL=INFO \
  -e KC_PROXY_HEADERS=xforwarded \
  quay.io/keycloak/keycloak:$KC_VERSION \
  start-dev

# Wait for readiness with better feedback
ELAPSED=0
MAX_WAIT=120
echo ""
yellow "Waiting for Keycloak to start (this may take up to 2 minutes)..."
until curl -sSf http://localhost:$KC_PORT/ &>/dev/null || [ $ELAPSED -ge $MAX_WAIT ]; do
  sleep 5
  ((ELAPSED+=5))
  echo -n "."
  if [ $((ELAPSED % 30)) -eq 0 ]; then
    echo " ($ELAPSED/$MAX_WAIT seconds)"
  fi
done
echo ""

if [ $ELAPSED -ge $MAX_WAIT ]; then
  red "❌ Keycloak failed to start within $MAX_WAIT seconds"
  yellow "Container logs:"
  podman logs keycloak | tail -30
  exit 1
fi

green "✔ Keycloak is responding!"

# Disable SSL enforcement (best effort)
yellow "Configuring Keycloak settings..."
sleep 10  # Give Keycloak a bit more time to fully initialize

podman exec keycloak /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user $KC_ADMIN_USER \
  --password "$KC_ADMIN_PASS" 2>/dev/null || yellow "⚠ Could not configure kcadm (non-critical)"

podman exec keycloak /opt/keycloak/bin/kcadm.sh update realms/master \
  -s sslRequired=NONE 2>/dev/null || yellow "⚠ Could not disable SSL requirement (non-critical)"

# Save configuration with proper permissions
yellow "Saving configuration..."
cat > /etc/henry-portal/keycloak-admin.env <<EOF
KC_ADMIN_USER=$KC_ADMIN_USER
KC_ADMIN_PASSWORD=$KC_ADMIN_PASS
KC_URL=http://localhost:$KC_PORT
KC_EXTERNAL_URL=http://$PUBLIC_IP:$KC_PORT
KC_PORT=$KC_PORT
KC_HOSTNAME=$(hostname -f)
KC_PUBLIC_IP=$PUBLIC_IP
KC_REALM=$REALM
KC_VERSION=$KC_VERSION
KC_DEMO_MODE=true
EOF

# FIX: Changed from 600 to 644 so helper script can read it
chmod 644 /etc/henry-portal/keycloak-admin.env
chown root:root /etc/henry-portal/keycloak-admin.env

# Create helper CLI
yellow "Creating helper CLI tool..."
cat > /usr/local/bin/keycloak-admin <<'EOL'
#!/bin/bash
source /etc/henry-portal/keycloak-admin.env
case "$1" in
  info) 
    echo "Keycloak Information:"
    echo "  Local URL:    $KC_URL/admin"
    echo "  External URL: $KC_EXTERNAL_URL/admin"
    echo "  Username:     $KC_ADMIN_USER"
    echo "  Password:     $KC_ADMIN_PASSWORD"
    echo "  Container:    $(podman ps --filter name=keycloak --format '{{.Names}} ({{.Status}})' 2>/dev/null || echo 'Not running')"
    ;;
  creds) 
    echo "Username: $KC_ADMIN_USER"
    echo "Password: $KC_ADMIN_PASSWORD"
    ;;
  url) echo "$KC_EXTERNAL_URL/admin" ;;
  logs) podman logs -f keycloak ;;
  restart) podman restart keycloak && echo "✅ Keycloak restarted" ;;
  stop) podman stop keycloak && echo "⏸ Keycloak stopped" ;;
  start) podman start keycloak && echo "🚀 Keycloak started" ;;
  status) podman ps --filter name=keycloak ;;
  health) 
    if curl -sf http://localhost:$KC_PORT/ >/dev/null 2>&1; then
      echo "✅ Healthy"
    else
      echo "❌ Unhealthy"
    fi
    ;;
  *) 
    echo "Usage: keycloak-admin [info|creds|url|logs|restart|start|stop|status|health]"
    echo ""
    echo "Commands:"
    echo "  info     - Show Keycloak connection information"
    echo "  creds    - Show admin credentials"
    echo "  url      - Show external admin URL"
    echo "  logs     - Follow container logs"
    echo "  restart  - Restart Keycloak container"
    echo "  start    - Start Keycloak container"
    echo "  stop     - Stop Keycloak container"
    echo "  status   - Show container status"
    echo "  health   - Check if Keycloak is responding"
    ;;
esac
EOL
chmod +x /usr/local/bin/keycloak-admin

# Create marker file
touch "$MARKER_FILE"

echo ""
green "✔✔✔ Keycloak installation complete! ✔✔✔"
echo ""
blue "Access Information:"
echo "  External URL: http://$PUBLIC_IP:$KC_PORT/admin"
echo "  Username:     $KC_ADMIN_USER"
echo "  Password:     $KC_ADMIN_PASS"
echo ""
yellow "⚠ IMPORTANT: Make sure port $KC_PORT is open in your AWS Security Group!"
echo ""
blue "Helper commands:"
echo "  keycloak-admin info     - View all connection details"
echo "  keycloak-admin status   - Check container status"
echo "  keycloak-admin health   - Test if Keycloak is responding"
echo ""

exit 0
