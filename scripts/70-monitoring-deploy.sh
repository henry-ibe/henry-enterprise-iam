#!/bin/bash
set -euo pipefail

################################################################################
# Phase 70 - Prometheus + Grafana Monitoring Stack (Idempotent)
# Henry Enterprise IAM Project - Security Monitoring Deployment
################################################################################

MARKER_FILE="/var/lib/henry-portal/markers/70-monitoring-deploy"
LOGFILE="logs/70-monitoring-deploy.log"
mkdir -p logs /var/lib/henry-portal/markers
exec > >(tee -a "$LOGFILE") 2>&1

# Colors
green()  { echo -e "\033[0;32m$1\033[0m"; }
yellow() { echo -e "\033[1;33m$1\033[0m"; }
red()    { echo -e "\033[0;31m$1\033[0m"; }
blue()   { echo -e "\033[0;34m$1\033[0m"; }

echo ""
blue "═══════════════════════════════════════════════════════════════"
blue "  Phase 70 - Prometheus + Grafana Monitoring Deployment"
blue "═══════════════════════════════════════════════════════════════"
echo ""

# Skip if already deployed
if [[ -f "$MARKER_FILE" ]]; then
  green "✔ Monitoring stack already deployed."
  echo ""
  blue "Service Status:"
  echo "Prometheus:"
  systemctl status prometheus --no-pager -l | head -5 || true
  echo ""
  echo "Grafana:"
  systemctl status grafana-server --no-pager -l | head -5 || true
  echo ""
  yellow "To redeploy: sudo rm $MARKER_FILE && sudo bash $0"
  exit 0
fi

# Configuration
PROMETHEUS_VERSION="2.45.0"
PROMETHEUS_USER="prometheus"
PROMETHEUS_DIR="/opt/prometheus"
PROMETHEUS_DATA="/var/lib/prometheus"

# ────────────────────────────────────────────────────────────────
# Step 1: Install Prometheus
# ────────────────────────────────────────────────────────────────
echo "🔍 Step 1: Installing Prometheus..."

# Create prometheus user
if ! id "$PROMETHEUS_USER" &>/dev/null; then
    useradd --no-create-home --shell /bin/false $PROMETHEUS_USER
    green "  ✔ Created prometheus user"
else
    yellow "  ⚙ Prometheus user already exists"
fi

# Check if already installed
if [[ -f "$PROMETHEUS_DIR/prometheus" ]]; then
    yellow "  ⚙ Prometheus already installed"
else
    # Download and install
    cd /tmp
    echo "  Downloading Prometheus ${PROMETHEUS_VERSION}..."
    wget -q https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
    tar xzf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
    
    # Install binaries
    mkdir -p $PROMETHEUS_DIR $PROMETHEUS_DATA
    cp prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus $PROMETHEUS_DIR/
    cp prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool $PROMETHEUS_DIR/
    cp -r prometheus-${PROMETHEUS_VERSION}.linux-amd64/consoles $PROMETHEUS_DIR/
    cp -r prometheus-${PROMETHEUS_VERSION}.linux-amd64/console_libraries $PROMETHEUS_DIR/
    
    # Set ownership
    chown -R $PROMETHEUS_USER:$PROMETHEUS_USER $PROMETHEUS_DIR $PROMETHEUS_DATA
    
    # Cleanup
    rm -rf /tmp/prometheus-${PROMETHEUS_VERSION}.linux-amd64*
    
    green "  ✔ Prometheus binaries installed"
fi

# Create/update configuration
cat > /etc/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'henry-portal'
    static_configs:
      - targets: ['localhost:5000']
    metrics_path: '/metrics'
EOF

green "  ✔ Prometheus configuration created"

# Create systemd service
cat > /etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=$PROMETHEUS_USER
Group=$PROMETHEUS_USER
Type=simple
ExecStart=$PROMETHEUS_DIR/prometheus \\
  --config.file=/etc/prometheus.yml \\
  --storage.tsdb.path=$PROMETHEUS_DATA \\
  --web.console.templates=$PROMETHEUS_DIR/consoles \\
  --web.console.libraries=$PROMETHEUS_DIR/console_libraries

[Install]
WantedBy=multi-user.target
EOF

# Start Prometheus
systemctl daemon-reload
systemctl enable prometheus
systemctl restart prometheus

sleep 3
if systemctl is-active --quiet prometheus; then
    green "  ✔ Prometheus is running on http://localhost:9090"
else
    red "  ❌ Prometheus failed to start"
    journalctl -u prometheus -n 20 --no-pager
    exit 1
fi

# ────────────────────────────────────────────────────────────────
# Step 2: Install Grafana
# ────────────────────────────────────────────────────────────────
echo ""
echo "📊 Step 2: Installing Grafana..."

# Add Grafana repository
if [[ ! -f /etc/yum.repos.d/grafana.repo ]]; then
    cat > /etc/yum.repos.d/grafana.repo <<'EOF'
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF
    green "  ✔ Grafana repository added"
else
    yellow "  ⚙ Grafana repository already exists"
fi

# Install Grafana
if ! rpm -qa | grep -q grafana; then
    echo "  Installing Grafana package..."
    dnf install -y grafana &>/dev/null
    green "  ✔ Grafana installed"
else
    yellow "  ⚙ Grafana already installed"
fi

# Configure Grafana (remove subpath for direct access)
sed -i 's|^root_url.*|;root_url = http://localhost:3000|' /etc/grafana/grafana.ini || true
sed -i 's|^serve_from_sub_path.*|;serve_from_sub_path = false|' /etc/grafana/grafana.ini || true

green "  ✔ Grafana configured"

# Start Grafana
systemctl daemon-reload
systemctl enable grafana-server
systemctl restart grafana-server

sleep 3
if systemctl is-active --quiet grafana-server; then
    green "  ✔ Grafana is running on http://localhost:3000"
else
    red "  ❌ Grafana failed to start"
    journalctl -u grafana-server -n 20 --no-pager
    exit 1
fi

# ────────────────────────────────────────────────────────────────
# Step 3: Configure Firewall
# ────────────────────────────────────────────────────────────────
echo ""
echo "🔥 Step 3: Configuring firewall..."

if systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-port=9090/tcp &>/dev/null || true
    firewall-cmd --permanent --add-port=3000/tcp &>/dev/null || true
    firewall-cmd --reload &>/dev/null || true
    green "  ✔ Firewall ports opened (9090, 3000)"
else
    yellow "  ⚙ Firewall not active, skipping"
fi

# ────────────────────────────────────────────────────────────────
# Step 4: Test Services
# ────────────────────────────────────────────────────────────────
echo ""
echo "🧪 Step 4: Testing services..."

sleep 2
curl -sf http://localhost:9090/-/healthy >/dev/null && green "  ✔ Prometheus healthy" || yellow "  ⚠ Prometheus health check inconclusive"
curl -sf http://localhost:3000/api/health >/dev/null && green "  ✔ Grafana healthy" || yellow "  ⚠ Grafana health check inconclusive"
curl -sf http://localhost:9090/api/v1/targets | grep -q henry-portal && green "  ✔ Prometheus scraping Flask metrics" || yellow "  ⚠ Flask target not yet discovered"

# ────────────────────────────────────────────────────────────────
# Final Summary
# ────────────────────────────────────────────────────────────────
echo ""
blue "═══════════════════════════════════════════════════════════════"
green "✅ Phase 70 - Monitoring Stack Complete!"
blue "═══════════════════════════════════════════════════════════════"
echo ""
blue "Services Running:"
echo "  Prometheus: http://localhost:9090"
echo "  Grafana:    http://localhost:3000"
echo ""
blue "Grafana Access:"
echo "  Username: admin"
echo "  Password: admin (change on first login)"
echo ""
blue "📊 Setup Grafana:"
echo "  1. Open http://localhost:3000/"
echo "  2. Login with admin/admin"
echo "  3. Add Prometheus data source:"
echo "     - Configuration → Data Sources → Add Prometheus"
echo "     - URL: http://localhost:9090"
echo "     - Click 'Save & Test'"
echo "  4. Import security dashboard (see documentation)"
echo ""
blue "📈 Available Metrics:"
echo "  - henry_portal_login_attempts_total"
echo "  - henry_portal_unauthorized_access_total"
echo "  - henry_portal_totp_verification_total"
echo "  - henry_portal_ldap_response_seconds"
echo "  - henry_portal_successful_auth_total"
echo ""
blue "Commands:"
echo "  sudo systemctl status prometheus"
echo "  sudo systemctl status grafana-server"
echo "  curl http://localhost:9090/api/v1/targets"
echo "  curl http://localhost:5000/metrics"
echo ""
blue "Next Steps:"
echo "  1. Configure Grafana data source"
echo "  2. Import security dashboard"
echo "  3. Generate test data by using the portal"
echo ""

touch "$MARKER_FILE"
green "✔ Phase 70 complete!"
echo ""
exit 0
