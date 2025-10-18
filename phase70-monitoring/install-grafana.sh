#!/bin/bash
set -euo pipefail

echo "📊 Installing Grafana..."

# Add Grafana repository
echo "Adding Grafana repository..."
sudo bash -c 'cat > /etc/yum.repos.d/grafana.repo' <<'EOF'
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

# Install Grafana
echo "Installing Grafana package..."
sudo dnf install -y grafana

echo "✔ Grafana installed"

# Configure Grafana for sub-path
echo "Configuring Grafana..."
sudo sed -i 's|^;root_url.*|root_url = http://localhost/grafana|' /etc/grafana/grafana.ini
sudo sed -i 's|^;serve_from_sub_path.*|serve_from_sub_path = true|' /etc/grafana/grafana.ini

# Start Grafana
echo "Starting Grafana..."
sudo systemctl daemon-reload
sudo systemctl enable grafana-server
sudo systemctl start grafana-server

# Wait and check
sleep 5
if sudo systemctl is-active --quiet grafana-server; then
    echo ""
    echo "✅ Grafana is running!"
    echo "   Status: sudo systemctl status grafana-server"
    echo "   Web UI: http://localhost:3000"
    echo "   Username: admin"
    echo "   Password: admin (change on first login)"
else
    echo "❌ Grafana failed to start"
    sudo journalctl -u grafana-server -n 20
    exit 1
fi

echo ""
echo "🎉 Grafana installation complete!"
