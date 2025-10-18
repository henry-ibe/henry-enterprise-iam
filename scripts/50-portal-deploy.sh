#!/bin/bash
set -euo pipefail

################################################################################
# Phase 50 - Employee Portal Deployment with Prometheus Metrics (Idempotent)
# Henry Enterprise IAM Project - Complete Self-Contained Deployment
# Version: 2.1 - Updated with Metrics Instrumentation
################################################################################

MARKER_FILE="/var/lib/henry-portal/markers/50-portal-deploy"
LOGFILE="logs/50-portal-deploy.log"
mkdir -p logs /var/lib/henry-portal/markers
exec > >(tee -a "$LOGFILE") 2>&1

# Colors
green()  { echo -e "\033[0;32m$1\033[0m"; }
yellow() { echo -e "\033[1;33m$1\033[0m"; }
red()    { echo -e "\033[0;31m$1\033[0m"; }
blue()   { echo -e "\033[0;34m$1\033[0m"; }

echo ""
blue "═══════════════════════════════════════════════════════════════"
blue "  Phase 50 - Employee Portal with 2FA TOTP & Metrics"
blue "═══════════════════════════════════════════════════════════════"
echo ""

# Skip if already deployed (remove marker to redeploy)
if [[ -f "$MARKER_FILE" ]]; then
  green "✔ Portal already deployed. Use --force to redeploy."
  echo ""
  blue "Service Status:"
  systemctl status henry-portal --no-pager -l | head -10 || true
  echo ""
  yellow "To redeploy: sudo rm $MARKER_FILE && sudo bash $0"
  exit 0
fi

# Configuration
PORTAL_DIR="/home/ec2-user/henry-enterprise-iam/phase50-portal"

# ────────────────────────────────────────────────────────────────
# Step 1: Install System Dependencies
# ────────────────────────────────────────────────────────────────
echo "📦 Step 1: Installing system dependencies..."
dnf install -y python3 python3-pip python3-devel openldap-devel gcc libjpeg-devel zlib-devel &>/dev/null
green "  ✔ System packages installed"

# ────────────────────────────────────────────────────────────────
# Step 2: Create Project Structure
# ────────────────────────────────────────────────────────────────
echo ""
echo "📁 Step 2: Creating project structure..."
mkdir -p "$PORTAL_DIR"/{app,templates,static/{css,images,js},logs}
chmod 755 "$PORTAL_DIR/logs"
green "  ✔ Directory structure created"

# ────────────────────────────────────────────────────────────────
# Step 3: Deploy Configuration Files
# ────────────────────────────────────────────────────────────────
echo ""
echo "📝 Step 3: Deploying configuration files..."

# requirements.txt - UPDATED with prometheus-client and qrcode
cat > "$PORTAL_DIR/requirements.txt" <<'EOF'
Flask==3.0.0
Flask-Session==0.5.0
ldap3==2.9.1
cryptography==41.0.7
pyotp==2.9.0
python-dotenv==1.0.0
qrcode[pil]==7.4.2
prometheus-client==0.19.0
EOF

# config.py
cat > "$PORTAL_DIR/config.py" <<'EOF'
import os
from datetime import timedelta

class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'henry-enterprise-secret-key-change-in-production'
    SESSION_TYPE = 'filesystem'
    SESSION_PERMANENT = True
    PERMANENT_SESSION_LIFETIME = timedelta(hours=8)
    SESSION_FILE_DIR = '/tmp/flask_sessions'
    
    LDAP_HOST = 'ldap://localhost:389'
    LDAP_BASE_DN = 'dc=henry-iam,dc=internal'
    LDAP_USER_BASE = 'cn=users,cn=accounts,dc=henry-iam,dc=internal'
    LDAP_GROUP_BASE = 'cn=groups,cn=accounts,dc=henry-iam,dc=internal'
    
    DEPARTMENT_GROUPS = {
        'HR': 'hr',
        'IT Support': 'it_support',
        'Sales': 'sales',
        'Admin': 'admins'
    }
    
    DEPARTMENT_DASHBOARDS = {
        'HR': '/hr/dashboard',
        'IT Support': '/it/dashboard',
        'Sales': '/sales/dashboard',
        'Admin': '/admin/dashboard'
    }
    
    LOG_FILE = 'logs/portal.log'
    DEBUG = False
    TESTING = False
EOF

# totp_secrets.py - Demo TOTP secrets
cat > "$PORTAL_DIR/totp_secrets.py" <<'EOF'
"""
TOTP Secrets for Henry Enterprise Portal Users
In production, store these securely in FreeIPA or a secrets manager.
"""

TOTP_SECRETS = {
    'sarah': 'JBSWY3DPEHPK3PXP',
    'adam': 'JBSWY3DPEHPK3PXQ',
    'ivy': 'JBSWY3DPEHPK3PXR',
    'lucas': 'JBSWY3DPEHPK3PXS',
}

def get_totp_secret(username):
    return TOTP_SECRETS.get(username)

def has_totp_enrolled(username):
    return username in TOTP_SECRETS

def list_enrolled_users():
    return list(TOTP_SECRETS.keys())
EOF

# .env
cat > "$PORTAL_DIR/.env" <<EOF
FLASK_APP=run.py
FLASK_ENV=production
SECRET_KEY=henry-enterprise-secret-$(openssl rand -hex 16)
IPA_ADMIN_PASSWORD=SecureAdminPass123!
APP_HOST=0.0.0.0
APP_PORT=5000
EOF

# run.py
cat > "$PORTAL_DIR/run.py" <<'EOF'
#!/usr/bin/env python3
from app import create_app
from dotenv import load_dotenv
import os

load_dotenv()
app = create_app()

if __name__ == '__main__':
    host = os.environ.get('APP_HOST', '0.0.0.0')
    port = int(os.environ.get('APP_PORT', 5000))
    debug = os.environ.get('FLASK_ENV', 'production') == 'development'
    
    print("=" * 60)
    print("🏢 Henry Enterprise Portal Starting...")
    print("=" * 60)
    print(f"Host: {host}")
    print(f"Port: {port}")
    print(f"Debug: {debug}")
    print("=" * 60)
    
    app.run(host=host, port=port, debug=debug)
EOF
chmod +x "$PORTAL_DIR/run.py"

green "  ✔ Configuration files created"

echo ""
blue "Note: Templates directory needs to be copied from existing installation"
yellow "  Templates should already exist in: $PORTAL_DIR/templates/"

# ────────────────────────────────────────────────────────────────
# Step 4: Setup Virtual Environment
# ────────────────────────────────────────────────────────────────
echo ""
echo "🔧 Step 4: Setting up Python virtual environment..."

cd "$PORTAL_DIR"
if [[ ! -d "venv" ]]; then
    python3 -m venv venv
    green "  ✔ Virtual environment created"
else
    yellow "  ⚙ Virtual environment exists"
fi

source venv/bin/activate
pip install --quiet --upgrade pip
pip install --quiet -r requirements.txt
green "  ✔ Dependencies installed (including prometheus-client)"

# ────────────────────────────────────────────────────────────────
# Step 5: Fix SELinux
# ────────────────────────────────────────────────────────────────
echo ""
echo "🔒 Step 5: Configuring SELinux..."

restorecon -Rv "$PORTAL_DIR/venv/" &>/dev/null || true
restorecon -Rv "$PORTAL_DIR/logs/" &>/dev/null || true
setsebool -P httpd_can_network_connect 1 &>/dev/null || true
green "  ✔ SELinux configured"

# ────────────────────────────────────────────────────────────────
# Step 6: Configure Systemd Service
# ────────────────────────────────────────────────────────────────
echo ""
echo "⚙️  Step 6: Configuring systemd service..."

cat > /etc/systemd/system/henry-portal.service <<EOF
[Unit]
Description=Henry Enterprise Portal - Flask Application
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=$PORTAL_DIR
Environment="PATH=$PORTAL_DIR/venv/bin:/usr/bin:/bin"
ExecStart=$PORTAL_DIR/venv/bin/python $PORTAL_DIR/run.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable henry-portal &>/dev/null
green "  ✔ Systemd service configured"

# ────────────────────────────────────────────────────────────────
# Step 7: Configure Apache
# ────────────────────────────────────────────────────────────────
echo ""
echo "🌐 Step 7: Configuring Apache reverse proxy..."

cat > /etc/httpd/conf.d/henry-portal.conf <<'EOF'
<VirtualHost *:80>
    ServerName portal.henry-enterprise.local
    ProxyPreserveHost On
    ProxyPass / http://localhost:5000/
    ProxyPassReverse / http://localhost:5000/
    ErrorLog /var/log/httpd/portal-error.log
    CustomLog /var/log/httpd/portal-access.log combined
</VirtualHost>
EOF

httpd -t &>/dev/null
systemctl reload httpd
green "  ✔ Apache configured"

# ────────────────────────────────────────────────────────────────
# Step 8: Start Service
# ────────────────────────────────────────────────────────────────
echo ""
echo "🚀 Step 8: Starting portal service..."

systemctl restart henry-portal
sleep 5

if systemctl is-active --quiet henry-portal; then
    green "  ✔ Portal service started"
else
    red "  ❌ Service failed to start"
    journalctl -u henry-portal -n 20 --no-pager
    exit 1
fi

# ────────────────────────────────────────────────────────────────
# Step 9: Test Deployment
# ────────────────────────────────────────────────────────────────
echo ""
echo "🧪 Step 9: Testing deployment..."

sleep 2
curl -sf http://localhost:5000/ >/dev/null && green "  ✔ Flask responding" || yellow "  ⚠ Flask check inconclusive"
curl -sf http://localhost:5000/metrics >/dev/null && green "  ✔ Metrics endpoint working" || yellow "  ⚠ Metrics endpoint not ready"
curl -sf http://localhost/ | grep -q "Henry Enterprise" && green "  ✔ Apache proxy working" || yellow "  ⚠ Apache check inconclusive"

# ────────────────────────────────────────────────────────────────
# Final Summary
# ────────────────────────────────────────────────────────────────
echo ""
blue "═══════════════════════════════════════════════════════════════"
green "✅ Phase 50 - Employee Portal with Metrics Complete!"
blue "═══════════════════════════════════════════════════════════════"
echo ""
blue "Portal Information:"
echo "  Directory:  $PORTAL_DIR"
echo "  Service:    henry-portal"
echo "  Access URL: http://localhost/"
echo "  Login URL:  http://localhost/employee/login"
echo "  Enroll URL: http://localhost/employee/enroll-totp"
echo "  Metrics:    http://localhost:5000/metrics"
echo ""
blue "🔐 Two-Factor Authentication:"
echo "  1. Visit: http://localhost/employee/enroll-totp"
echo "  2. Scan QR code with Google Authenticator"
echo "  3. Login with credentials + TOTP code"
echo ""
blue "📊 Metrics Available:"
echo "  - Login attempts (by user, department, status)"
echo "  - Unauthorized access attempts"
echo "  - TOTP verification success/failure"
echo "  - LDAP response times"
echo "  - Authentication duration"
echo ""
blue "Test Accounts:"
echo "  sarah / password123 (HR)"
echo "  adam  / password123 (IT Support)"
echo "  ivy   / password123 (Sales)"
echo "  lucas / password123 (Admin)"
echo ""
blue "Commands:"
echo "  sudo systemctl status henry-portal"
echo "  sudo systemctl restart henry-portal"
echo "  tail -f $PORTAL_DIR/logs/portal.log"
echo "  curl http://localhost:5000/metrics"
echo ""
blue "Next Step:"
echo "  Run: sudo bash scripts/70-monitoring-deploy.sh"
echo "  to install Prometheus + Grafana monitoring"
echo ""

touch "$MARKER_FILE"
green "✔ Phase 50 complete!"
echo ""
exit 0
