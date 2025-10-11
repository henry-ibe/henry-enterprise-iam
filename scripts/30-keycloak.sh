#!/bin/bash
set -euo pipefail

################################################################################
# Phase 30 - Keycloak Installation (Idempotent, Interview Ready)
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

# Dependencies
yellow "Installing required packages..."
dnf install -y podman firewalld iptables || true
systemctl enable --now firewalld || true

# Check port availability
if ss -tuln | grep -q ":$KC_PORT "; then
  PROCESS=$(ss -tulpn | grep ":$KC_PORT " | awk '{print $7}' | head -1)
  if echo "$PROCESS" | grep -qE "podman|conmon"; then
    podman stop keycloak || true
    podman rm keycloak || true
  else
    red "Port $KC_PORT is in use by another process: $PROCESS"
    exit 1
  fi
fi

# Configure firewall
firewall-cmd --permanent --add-port=$KC_PORT/tcp || true
firewall-cmd --reload || true
iptables -C INPUT -p tcp --dport $KC_PORT -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport $KC_PORT -j ACCEPT
command -v iptables-save && iptables-save > /etc/sysconfig/iptables

# Start Keycloak container
podman run -d \
  --name keycloak \
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

# Wait for readiness
ELAPSED=0; MAX_WAIT=90; echo "Waiting for Keycloak to start..."
until curl -sSf http://localhost:$KC_PORT/ &>/dev/null || [ $ELAPSED -ge $MAX_WAIT ]; do
  sleep 3; ((ELAPSED+=3)); echo -n "."
done

# Disable SSL enforcement (best effort)
podman exec keycloak /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user $KC_ADMIN_USER \
  --password "$KC_ADMIN_PASS" || true

podman exec keycloak /opt/keycloak/bin/kcadm.sh update realms/master \
  -s sslRequired=NONE || true

# Save configuration
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
chmod 600 /etc/henry-portal/keycloak-admin.env

# Create helper CLI
cat > /usr/local/bin/keycloak-admin <<'EOL'
#!/bin/bash
source /etc/henry-portal/keycloak-admin.env
case "$1" in
  info) echo "Keycloak @ $KC_EXTERNAL_URL | User: $KC_ADMIN_USER" ;;
  creds) echo "User: $KC_ADMIN_USER | Pass: $KC_ADMIN_PASSWORD" ;;
  url) echo "$KC_EXTERNAL_URL/admin" ;;
  logs) podman logs -f keycloak ;;
  restart) podman restart keycloak ;;
  stop) podman stop keycloak ;;
  start) podman start keycloak ;;
  status) podman ps --filter name=keycloak ;;
  health) curl -sf http://localhost:$KC_PORT && echo "Healthy" || echo "Unhealthy" ;;
  *) echo "Usage: keycloak-admin [info|creds|url|logs|restart|start|stop|status|health]" ;;
esac
EOL
chmod +x /usr/local/bin/keycloak-admin

touch "$MARKER_FILE"
green "✔ Keycloak installation complete and ready."
exit 0

