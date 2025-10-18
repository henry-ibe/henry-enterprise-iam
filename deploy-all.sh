#!/bin/bash
set -euo pipefail

################################################################################
# Master Deployment Script - Henry Enterprise IAM Project
# Runs all phases in sequence: 20 → 30 → 40 → 50 → 70
# Fully idempotent - safe to run multiple times
################################################################################

LOGDIR="logs"
MASTER_LOG="$LOGDIR/deploy-all.log"
mkdir -p "$LOGDIR"

# Redirect all output to both console and log file
exec > >(tee -a "$MASTER_LOG") 2>&1

# ────────────────────────────────────────────────────────────────
# Colors and Formatting
# ────────────────────────────────────────────────────────────────
green()  { echo -e "\033[0;32m$1\033[0m"; }
yellow() { echo -e "\033[1;33m$1\033[0m"; }
red()    { echo -e "\033[0;31m$1\033[0m"; }
blue()   { echo -e "\033[0;34m$1\033[0m"; }
bold()   { echo -e "\033[1m$1\033[0m"; }

# ────────────────────────────────────────────────────────────────
# Banner
# ────────────────────────────────────────────────────────────────
clear
echo ""
blue "═══════════════════════════════════════════════════════════════"
bold "  🚀 Henry Enterprise IAM - Master Deployment Script"
blue "═══════════════════════════════════════════════════════════════"
echo ""
green "This script will deploy all phases of the IAM system:"
echo ""
echo "  📦 Phase 20 - FreeIPA/LDAP Server"
echo "  🔐 Phase 30 - Keycloak SSO"
echo "  ⚙️  Phase 40 - Keycloak Configuration"
echo "  🌐 Phase 50 - Employee Portal"
echo "  📊 Phase 70 - Monitoring Stack"
echo ""
yellow "⏱️  Total deployment time: ~10-15 minutes"
echo ""
blue "═══════════════════════════════════════════════════════════════"
echo ""

# ────────────────────────────────────────────────────────────────
# Pre-flight Checks
# ────────────────────────────────────────────────────────────────
echo ""
bold "🔍 Pre-flight Checks..."
echo ""

# Check if running as root/sudo
if [[ $EUID -ne 0 ]]; then
   red "❌ This script must be run as root or with sudo"
   exit 1
fi
green "✅ Running with root privileges"

# Check if scripts directory exists
if [[ ! -d "scripts" ]]; then
   red "❌ scripts/ directory not found. Are you in the project root?"
   exit 1
fi
green "✅ Found scripts directory"

# Check if required phase scripts exist
REQUIRED_SCRIPTS=(
    "scripts/20-freeipa.sh"
    "scripts/30-keycloak.sh"
    "scripts/40-keycloak-init.sh"
    "scripts/50-portal-deploy.sh"
    "scripts/70-monitoring-deploy.sh"
)

for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [[ ! -f "$script" ]]; then
        red "❌ Required script not found: $script"
        exit 1
    fi
done
green "✅ All required phase scripts found"

# Check if docker is installed
if ! command -v docker &> /dev/null; then
    red "❌ Docker is not installed"
    exit 1
fi
green "✅ Docker is installed"

# Check if docker is running
if ! docker ps &> /dev/null; then
    red "❌ Docker is not running or current user lacks permissions"
    exit 1
fi
green "✅ Docker is running"

# Detect server IP addresses
echo ""
yellow "🔍 Detecting server IP addresses..."

# Try to get PUBLIC IP first (for external access)
PUBLIC_IP=""

# Method 1: AWS metadata endpoint for public IPv4
PUBLIC_IP=$(curl -s --connect-timeout 2 --max-time 5 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)

# Method 2: External IP check services
if [[ -z "$PUBLIC_IP" ]] || [[ "$PUBLIC_IP" == "" ]]; then
    PUBLIC_IP=$(curl -s --connect-timeout 3 --max-time 5 http://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]')
fi

if [[ -z "$PUBLIC_IP" ]] || [[ "$PUBLIC_IP" == "" ]]; then
    PUBLIC_IP=$(curl -s --connect-timeout 3 --max-time 5 https://api.ipify.org 2>/dev/null)
fi

if [[ -z "$PUBLIC_IP" ]] || [[ "$PUBLIC_IP" == "" ]]; then
    PUBLIC_IP=$(curl -s --connect-timeout 3 --max-time 5 https://ifconfig.me 2>/dev/null)
fi

# Get PRIVATE IP (for internal reference)
PRIVATE_IP=$(curl -s --connect-timeout 2 --max-time 5 http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null)

# If we still don't have a public IP, try local network IPs
if [[ -z "$PUBLIC_IP" ]] || [[ "$PUBLIC_IP" == "" ]]; then
    PUBLIC_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
fi

if [[ -z "$PUBLIC_IP" ]] || [[ "$PUBLIC_IP" == "" ]]; then
    PUBLIC_IP=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[^ ]+')
fi

# Final fallback
if [[ -z "$PUBLIC_IP" ]] || [[ "$PUBLIC_IP" == "" ]]; then
    PUBLIC_IP="localhost"
fi

# If private IP is empty, use public IP
if [[ -z "$PRIVATE_IP" ]] || [[ "$PRIVATE_IP" == "" ]]; then
    PRIVATE_IP="$PUBLIC_IP"
fi

# Display detected IPs
green "✅ Public IP detected: $PUBLIC_IP"
if [[ "$PUBLIC_IP" != "$PRIVATE_IP" ]]; then
    green "✅ Private IP detected: $PRIVATE_IP"
fi

echo ""
green "✅ All pre-flight checks passed!"
echo ""

# ────────────────────────────────────────────────────────────────
# Confirmation Prompt
# ────────────────────────────────────────────────────────────────
yellow "⚠️  This will deploy the complete IAM system."
yellow "⚠️  Existing deployments will be safely skipped (idempotent)."
echo ""
read -p "Continue with deployment? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    yellow "Deployment cancelled by user."
    exit 0
fi

# ────────────────────────────────────────────────────────────────
# Track deployment start time
# ────────────────────────────────────────────────────────────────
START_TIME=$(date +%s)
DEPLOYMENT_DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo ""
blue "═══════════════════════════════════════════════════════════════"
bold "  🚀 Starting Deployment at $DEPLOYMENT_DATE"
blue "═══════════════════════════════════════════════════════════════"
echo ""

# ────────────────────────────────────────────────────────────────
# Helper function to run phase scripts
# ────────────────────────────────────────────────────────────────
run_phase() {
    local phase_num=$1
    local phase_name=$2
    local script_path=$3
    
    echo ""
    blue "───────────────────────────────────────────────────────────────"
    bold "  📦 Phase $phase_num - $phase_name"
    blue "───────────────────────────────────────────────────────────────"
    echo ""
    
    if [[ ! -f "$script_path" ]]; then
        red "❌ Script not found: $script_path"
        return 1
    fi
    
    # Make script executable if it isn't already
    chmod +x "$script_path"
    
    # Run the phase script
    if bash "$script_path"; then
        green "✅ Phase $phase_num completed successfully"
        return 0
    else
        red "❌ Phase $phase_num failed"
        return 1
    fi
}

# ────────────────────────────────────────────────────────────────
# Phase 20 - FreeIPA/LDAP Server
# ────────────────────────────────────────────────────────────────
if ! run_phase "20" "FreeIPA/LDAP Server" "scripts/20-freeipa.sh"; then
    red "❌ FreeIPA/LDAP deployment failed. Stopping deployment."
    exit 1
fi

# Wait for LDAP to stabilize
echo ""
yellow "⏳ Waiting 15 seconds for LDAP to stabilize..."
sleep 15

# ────────────────────────────────────────────────────────────────
# Phase 30 - Keycloak SSO
# ────────────────────────────────────────────────────────────────
if ! run_phase "30" "Keycloak SSO" "scripts/30-keycloak.sh"; then
    red "❌ Keycloak deployment failed. Stopping deployment."
    exit 1
fi

# Wait for Keycloak to fully start
echo ""
yellow "⏳ Waiting 45 seconds for Keycloak to fully initialize..."
sleep 45

# ────────────────────────────────────────────────────────────────
# Phase 40 - Keycloak Configuration
# ────────────────────────────────────────────────────────────────
if ! run_phase "40" "Keycloak Configuration" "scripts/40-keycloak-init.sh"; then
    red "❌ Keycloak configuration failed. Stopping deployment."
    exit 1
fi

# ────────────────────────────────────────────────────────────────
# Phase 50 - Employee Portal
# ────────────────────────────────────────────────────────────────
if ! run_phase "50" "Employee Portal" "scripts/50-portal-deploy.sh"; then
    red "❌ Portal deployment failed. Stopping deployment."
    exit 1
fi

# Wait for portal to stabilize
echo ""
yellow "⏳ Waiting 10 seconds for portal to stabilize..."
sleep 10

# ────────────────────────────────────────────────────────────────
# Phase 70 - Monitoring Stack
# ────────────────────────────────────────────────────────────────
if ! run_phase "70" "Monitoring Stack" "scripts/70-monitoring-deploy.sh"; then
    yellow "⚠️  Monitoring deployment failed, but core system is operational."
fi

# ────────────────────────────────────────────────────────────────
# Deployment Complete
# ────────────────────────────────────────────────────────────────
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

echo ""
blue "═══════════════════════════════════════════════════════════════"
green "  ✅ DEPLOYMENT COMPLETE!"
blue "═══════════════════════════════════════════════════────════════"
echo ""
green "⏱️  Total deployment time: ${MINUTES}m ${SECONDS}s"
echo ""

# ────────────────────────────────────────────────────────────────
# Display Access Information
# ────────────────────────────────────────────────────────────────
bold "📋 ACCESS INFORMATION:"
echo ""
echo "🌐 Employee Portal:"
echo "   External URL: http://$PUBLIC_IP:3000"
if [[ "$PUBLIC_IP" != "$PRIVATE_IP" ]]; then
    echo "   Internal URL: http://$PRIVATE_IP:3000"
fi
echo ""
echo "🔐 Keycloak Admin Console:"
echo "   External URL: http://$PUBLIC_IP:8080"
if [[ "$PUBLIC_IP" != "$PRIVATE_IP" ]]; then
    echo "   Internal URL: http://$PRIVATE_IP:8080"
fi
echo "   Username: admin"
echo "   Password: HenryAdmin123!"
echo ""
echo "📁 LDAP (phpLDAPadmin):"
echo "   External URL: http://$PUBLIC_IP:8081"
if [[ "$PUBLIC_IP" != "$PRIVATE_IP" ]]; then
    echo "   Internal URL: http://$PRIVATE_IP:8081"
fi
echo "   Login DN: cn=admin,dc=henryiam,dc=com"
echo "   Password: HenryAdmin123!"
echo ""
echo "📊 Prometheus:"
echo "   External URL: http://$PUBLIC_IP:9090"
if [[ "$PUBLIC_IP" != "$PRIVATE_IP" ]]; then
    echo "   Internal URL: http://$PRIVATE_IP:9090"
fi
echo ""
echo "📈 Grafana:"
echo "   External URL: http://$PUBLIC_IP:3001"
if [[ "$PUBLIC_IP" != "$PRIVATE_IP" ]]; then
    echo "   Internal URL: http://$PRIVATE_IP:3001"
fi
echo "   Username: admin"
echo "   Password: HenryAdmin123!"
echo ""

# ────────────────────────────────────────────────────────────────
# Save deployment summary
# ────────────────────────────────────────────────────────────────
SUMMARY_FILE="/etc/henry-portal/deployment-summary.txt"
mkdir -p /etc/henry-portal

cat > "$SUMMARY_FILE" <<EOF
═══════════════════════════════════════════════════════════════
Henry Enterprise IAM - Deployment Summary
═══════════════════════════════════════════════════════════════

Deployment Date: $DEPLOYMENT_DATE
Deployment Duration: ${MINUTES}m ${SECONDS}s
Public IP: $PUBLIC_IP
Private IP: $PRIVATE_IP

COMPONENTS DEPLOYED:
──────────────────────────────────────────────────────────────
✅ Phase 20 - FreeIPA/LDAP Server
✅ Phase 30 - Keycloak SSO Server
✅ Phase 40 - Keycloak Configuration (Realm, Roles, Users)
✅ Phase 50 - Employee Portal (Flask Application)
✅ Phase 70 - Monitoring Stack (Prometheus + Grafana)

ACCESS URLS (External):
──────────────────────────────────────────────────────────────
Employee Portal:    http://$PUBLIC_IP:3000
Keycloak Console:   http://$PUBLIC_IP:8080
phpLDAPadmin:       http://$PUBLIC_IP:8081
Prometheus:         http://$PUBLIC_IP:9090
Grafana:            http://$PUBLIC_IP:3001

ACCESS URLS (Internal):
──────────────────────────────────────────────────────────────
Employee Portal:    http://$PRIVATE_IP:3000
Keycloak Console:   http://$PRIVATE_IP:8080
phpLDAPadmin:       http://$PRIVATE_IP:8081
Prometheus:         http://$PRIVATE_IP:9090
Grafana:            http://$PRIVATE_IP:3001

DEFAULT CREDENTIALS:
──────────────────────────────────────────────────────────────
Portal Demo User:   jane.doe / JaneSecure123!
Keycloak Admin:     admin / HenryAdmin123!
LDAP Admin:         cn=admin,dc=henryiam,dc=com / HenryAdmin123!
Grafana Admin:      admin / HenryAdmin123!

DOCKER CONTAINERS:
──────────────────────────────────────────────────────────────
$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "freeipa|ldap|keycloak|portal|prometheus|grafana" || echo "No containers found")

NEXT STEPS:
──────────────────────────────────────────────────────────────
1. Test portal login at http://$PUBLIC_IP:3000
2. Configure AWS Security Group to allow ports: 3000, 8080, 8081, 9090, 3001
3. Check container status: docker ps
4. View logs: docker logs <container_name>
5. Import Grafana dashboards for metrics visualization

TROUBLESHOOTING:
──────────────────────────────────────────────────────────────
- Logs directory: $LOGDIR
- Master log: $MASTER_LOG
- Container logs: docker logs <container_name>
- Restart services: docker restart <container_name>

═══════════════════════════════════════════════════════════════
EOF

green "📝 Deployment summary saved to: $SUMMARY_FILE"
echo ""

# ────────────────────────────────────────────────────────────────
# Health Check
# ────────────────────────────────────────────────────────────────
bold "🏥 Running Health Checks..."
echo ""

# Check FreeIPA/LDAP (Docker or systemd)
if docker ps 2>/dev/null | grep -q "freeipa\|ldap"; then
    green "✅ FreeIPA/LDAP container is running"
elif systemctl is-active --quiet ipa 2>/dev/null; then
    green "✅ FreeIPA service is running"
elif systemctl is-active --quiet slapd 2>/dev/null; then
    green "✅ LDAP service is running"
else
    yellow "⚠️  FreeIPA/LDAP not found (may be running differently)"
fi

# Check Keycloak (Docker or systemd)
if docker ps 2>/dev/null | grep -q "keycloak"; then
    green "✅ Keycloak container is running"
elif systemctl is-active --quiet keycloak 2>/dev/null; then
    green "✅ Keycloak service is running"
elif pgrep -f "keycloak" > /dev/null 2>&1; then
    green "✅ Keycloak process is running"
else
    yellow "⚠️  Keycloak not found (may be running differently)"
fi

# Check Portal (Docker or systemd)
if docker ps 2>/dev/null | grep -q "portal"; then
    green "✅ Portal container is running"
elif systemctl is-active --quiet henry-portal 2>/dev/null; then
    green "✅ Portal service is running"
else
    red "❌ Portal is not running"
fi

# Check Prometheus (Docker or systemd)
if docker ps 2>/dev/null | grep -q "prometheus"; then
    green "✅ Prometheus container is running"
elif systemctl is-active --quiet prometheus 2>/dev/null; then
    green "✅ Prometheus service is running"
else
    yellow "⚠️  Prometheus is not running"
fi

# Check Grafana (Docker or systemd)
if docker ps 2>/dev/null | grep -q "grafana"; then
    green "✅ Grafana container is running"
elif systemctl is-active --quiet grafana-server 2>/dev/null; then
    green "✅ Grafana service is running"
else
    yellow "⚠️  Grafana is not running"
fi

echo ""

# ────────────────────────────────────────────────────────────────
# Quick Test URLs
# ────────────────────────────────────────────────────────────────
bold "🧪 Testing Service Endpoints..."
echo ""

# Test Portal
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:3000" | grep -q "200\|302"; then
    green "✅ Portal is responding"
else
    yellow "⚠️  Portal is not responding yet (may need more time to start)"
fi

# Test Keycloak
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080" | grep -q "200\|302"; then
    green "✅ Keycloak is responding"
else
    yellow "⚠️  Keycloak is not responding yet (may need more time to start)"
fi

# Test Prometheus
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:9090" | grep -q "200\|302"; then
    green "✅ Prometheus is responding"
else
    yellow "⚠️  Prometheus is not responding yet"
fi

echo ""

# ────────────────────────────────────────────────────────────────
# Final Instructions
# ────────────────────────────────────────────────────────────────
blue "═══════════════════════════════════════════════════════════════"
bold "  🎉 Your Henry Enterprise IAM System is Ready!"
blue "═══════════════════════════════════════════════════════════════"
echo ""
yellow "📌 IMPORTANT: Configure AWS Security Group"
echo ""
echo "   Add these inbound rules to access the services:"
echo "   • Port 3000 (Employee Portal)"
echo "   • Port 8080 (Keycloak)"
echo "   • Port 8081 (phpLDAPadmin)"
echo "   • Port 9090 (Prometheus)"
echo "   • Port 3001 (Grafana)"
echo ""
if [[ "$PUBLIC_IP" != "$PRIVATE_IP" ]]; then
    yellow "📡 IP Address Information:"
    echo ""
    echo "   Public IP ($PUBLIC_IP):"
    echo "   └─ Use this for external/internet access"
    echo ""
    echo "   Private IP ($PRIVATE_IP):"
    echo "   └─ Use this for internal/VPC access"
    echo ""
fi
bold "🚀 QUICK START:"
echo ""
echo "   1. Open in browser: http://$PUBLIC_IP:3000"
echo "   2. Login with: jane.doe / JaneSecure123!"
echo "   3. Explore the dashboard and features"
echo ""
if [[ "$PUBLIC_IP" != "$PRIVATE_IP" ]]; then
    yellow "   💡 TIP: If accessing from the same network, use:"
    echo "      http://$PRIVATE_IP:3000"
    echo ""
fi
green "✅ Deployment logs saved to: $MASTER_LOG"
green "✅ Summary saved to: $SUMMARY_FILE"
echo ""
blue "═══════════════════════════════════════════════════════════════"
echo ""
