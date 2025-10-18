#!/bin/bash
set -euo pipefail

echo "🔍 Installing Prometheus..."

# Configuration
PROMETHEUS_VERSION="2.45.0"
PROMETHEUS_USER="prometheus"
PROMETHEUS_DIR="/opt/prometheus"
PROMETHEUS_DATA="/var/lib/prometheus"

# Create prometheus user
if ! id "$PROMETHEUS_USER" &>/dev/null; then
    sudo useradd --no-create-home --shell /bin/false $PROMETHEUS_USER
    echo "✔ Created prometheus user"
fi

# Download and install Prometheus
cd /tmp
echo "Downloading Prometheus..."
wget -q https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
tar xzf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz

# Install to /opt
echo "Installing binaries..."
sudo mkdir -p $PROMETHEUS_DIR $PROMETHEUS_DATA
sudo cp prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus $PROMETHEUS_DIR/
sudo cp prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool $PROMETHEUS_DIR/
sudo cp -r prometheus-${PROMETHEUS_VERSION}.linux-amd64/consoles $PROMETHEUS_DIR/
sudo cp -r prometheus-${PROMETHEUS_VERSION}.linux-amd64/console_libraries $PROMETHEUS_DIR/

# Set ownership
sudo chown -R $PROMETHEUS_USER:$PROMETHEUS_USER $PROMETHEUS_DIR $PROMETHEUS_DATA

echo "✔ Prometheus binaries installed"

# Create configuration
echo "Creating configuration..."
sudo bash -c 'cat > /etc/prometheus.yml' <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'henry-portal'
    static_configs:
      - targets: ['localhost:5000']
    metrics_path: '/metrics'
EOF

echo "✔ Prometheus configuration created"

# Create systemd service
echo "Creating systemd service..."
sudo bash -c "cat > /etc/systemd/system/prometheus.service" <<EOF
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
echo "Starting Prometheus..."
sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus

# Wait and check
sleep 5
if sudo systemctl is-active --quiet prometheus; then
    echo ""
    echo "✅ Prometheus is running!"
    echo "   Status: sudo systemctl status prometheus"
    echo "   Web UI: http://localhost:9090"
    echo "   Targets: http://localhost:9090/targets"
else
    echo "❌ Prometheus failed to start"
    sudo journalctl -u prometheus -n 20
    exit 1
fi

# Cleanup
rm -rf /tmp/prometheus-${PROMETHEUS_VERSION}.linux-amd64*

echo ""
echo "🎉 Prometheus installation complete!"
