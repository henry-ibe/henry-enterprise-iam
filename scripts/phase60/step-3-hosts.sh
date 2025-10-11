#!/bin/bash
# scripts/phase60/step-3-hosts.sh - Idempotent /etc/hosts configuration

set -e

PROJECT_ROOT="$(pwd)"
PHASE60_ROOT="$PROJECT_ROOT/phase60"
ENV_FILE="$PHASE60_ROOT/.env"

echo "=== Phase 60 Step 3: DNS Configuration (/etc/hosts) ==="
echo ""

# Check if .env exists
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Error: .env file not found at $ENV_FILE"
    echo "Please run step-2-environment.sh first"
    exit 1
fi

# Load environment variables
source "$ENV_FILE"

# Detect IP address to use
echo "🔍 Detecting network configuration..."
echo ""

# Get the primary IP address (not localhost)
PRIMARY_IP=$(hostname -I | awk '{print $1}')

echo "Available options:"
echo "1. Use 127.0.0.1 (localhost - for testing on this machine only)"
echo "2. Use $PRIMARY_IP (local network - accessible from other machines)"
echo ""
read -p "Select option [1 or 2, default: 1]: " IP_CHOICE
IP_CHOICE=${IP_CHOICE:-1}

if [ "$IP_CHOICE" == "2" ]; then
    TARGET_IP=$PRIMARY_IP
    echo "✅ Using local network IP: $TARGET_IP"
else
    TARGET_IP="127.0.0.1"
    echo "✅ Using localhost: $TARGET_IP"
fi

echo ""
echo "📝 Hosts entries to be added:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$TARGET_IP $DOMAIN"
echo "$TARGET_IP $PORTAL_DOMAIN"
echo "$TARGET_IP traefik.$DOMAIN"
echo "$TARGET_IP prometheus.$DOMAIN"
echo "$TARGET_IP grafana.$DOMAIN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if entries already exist
HOSTS_FILE="/etc/hosts"
MARKER_START="# Phase 60 - Henry Enterprise - START"
MARKER_END="# Phase 60 - Henry Enterprise - END"

if grep -q "$MARKER_START" "$HOSTS_FILE" 2>/dev/null; then
    echo "⚠️  Phase 60 entries already exist in $HOSTS_FILE"
    echo ""
    read -p "Do you want to update them? (yes/no): " UPDATE_CONFIRM
    if [ "$UPDATE_CONFIRM" != "yes" ]; then
        echo "❌ Aborted. Keeping existing entries."
        exit 0
    fi
    
    echo "🔄 Removing old entries..."
    sudo sed -i "/$MARKER_START/,/$MARKER_END/d" "$HOSTS_FILE"
fi

# Create temporary file with new entries
TEMP_FILE=$(mktemp)
cat > "$TEMP_FILE" << EOF

$MARKER_START
$TARGET_IP $DOMAIN
$TARGET_IP $PORTAL_DOMAIN
$TARGET_IP traefik.$DOMAIN
$TARGET_IP prometheus.$DOMAIN
$TARGET_IP grafana.$DOMAIN
$MARKER_END
EOF

# Backup current hosts file
echo "💾 Backing up current /etc/hosts..."
sudo cp "$HOSTS_FILE" "$HOSTS_FILE.backup.$(date +%s)"

# Append new entries
echo "✍️  Adding entries to $HOSTS_FILE..."
sudo bash -c "cat $TEMP_FILE >> $HOSTS_FILE"

# Cleanup
rm -f "$TEMP_FILE"

echo ""
echo "✅ /etc/hosts updated successfully!"
echo ""

# Verify entries
echo "📋 Verification - Current Phase 60 entries:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo grep -A 10 "$MARKER_START" "$HOSTS_FILE" || echo "No entries found"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test DNS resolution
echo "🧪 Testing DNS resolution..."
for host in "$DOMAIN" "$PORTAL_DOMAIN" "traefik.$DOMAIN"; do
    if ping -c 1 -W 1 "$host" &>/dev/null; then
        echo "  ✅ $host resolves to $(ping -c 1 "$host" | grep -oP '\(\K[^\)]+'|head -1)"
    else
        echo "  ⚠️  $host - resolution configured (services not running yet)"
    fi
done

echo ""
echo "✅ Step 3 Complete: DNS configured"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Configured domains:"
echo "  • Main Site:   http://$DOMAIN"
echo "  • Portal:      http://$PORTAL_DOMAIN"
echo "  • Traefik UI:  http://traefik.$DOMAIN:8080"
echo "  • Prometheus:  http://prometheus.$DOMAIN"
echo "  • Grafana:     http://grafana.$DOMAIN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next: Step 4 - Create Traefik configuration files"
