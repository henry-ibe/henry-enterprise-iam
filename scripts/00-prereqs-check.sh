#!/bin/bash
set -euo pipefail

################################################################################
# Phase 00 - System Prerequisites Check & Auto-Install
# Henry Enterprise IAM - Flask + Keycloak Architecture
# Fully idempotent: checks, installs, configures, and self-heals
################################################################################

LOGFILE="logs/00-prereqs.log"
MARKER_DIR="/var/lib/henry-portal/markers"
MARKER_FILE="$MARKER_DIR/00-prereqs-complete"

mkdir -p logs
mkdir -p "$MARKER_DIR"
exec > >(tee -a "$LOGFILE") 2>&1

EXPECTED_OS="Red Hat Enterprise Linux release 9"
EXPECTED_HOSTNAME="ipa1.henry-iam.internal"
AWS_DNS="169.254.169.253"
FALLBACK_DNS_1="1.1.1.1"
FALLBACK_DNS_2="8.8.8.8"
FLASK_PORT=5000
KEYCLOAK_PORT=8180

# Colors
green()  { echo -e "\033[0;32m$1\033[0m"; }
yellow() { echo -e "\033[1;33m$1\033[0m"; }
red()    { echo -e "\033[0;31m$1\033[0m"; }
blue()   { echo -e "\033[0;34m$1\033[0m"; }
log()    { echo -e "\n[+] $1"; }
fail()   { echo -e "\n[✘] $1"; exit 1; }

is_ec2(){
  curl -s --connect-timeout 1 http://169.254.169.254/latest/meta-data/ >/dev/null 2>&1
}

resolv_is_immutable(){
  lsattr -a /etc/resolv.conf 2>/dev/null | awk '{print $1}' | grep -q 'i'
}

make_resolv_writable(){
  if resolv_is_immutable; then
    sudo chattr -i /etc/resolv.conf || true
  fi
}

make_resolv_sticky(){
  sudo chattr +i /etc/resolv.conf || true
}

write_resolv(){
  local dns_lines="$1"
  make_resolv_writable
  sudo bash -c "cat > /etc/resolv.conf <<EOF
$dns_lines
options timeout:2 attempts:2
EOF"
}

nm_profiles_for_type(){
  nmcli -t -f NAME,TYPE,STATE connection show --active 2>/dev/null | awk -F: -v t="$1" '$2==t{print $1}'
  nmcli -t -f NAME,TYPE connection show 2>/dev/null | awk -F: -v t="$1" '$2==t{print $1}'
}

nm_force_dns_all_eth(){
  local any=0
  if command -v nmcli >/dev/null 2>&1; then
    mapfile -t ETH_CONNS < <(nm_profiles_for_type "ethernet" | awk 'NF' | awk '!seen[$0]++')
    if [ "${#ETH_CONNS[@]}" -gt 0 ]; then
      for C in "${ETH_CONNS[@]}"; do
        any=1
        sudo nmcli connection modify "$C" \
          ipv4.dns "$AWS_DNS" \
          ipv4.ignore-auto-dns yes \
          ipv4.method auto || true
        sudo nmcli connection up "$C" || true
      done
      sudo systemctl restart NetworkManager || true
    fi
  fi
  return $any
}

ensure_nss_uses_dns(){
  if ! grep -qE '^hosts:\s+files\s+dns' /etc/nsswitch.conf; then
    sudo sed -i 's/^hosts:.*/hosts: files dns/' /etc/nsswitch.conf
  fi
}

test_dns(){
  local host="${1:-google.com}"
  getent hosts "$host" >/dev/null 2>&1
}

self_heal_dns(){
  local test_host="${1:-google.com}"
  local lines
  
  if is_ec2; then
    lines="nameserver $AWS_DNS"
  else
    lines=$"nameserver $FALLBACK_DNS_1\nnameserver $FALLBACK_DNS_2"
  fi

  yellow "  DNS lookup failed; self-healing..."
  ensure_nss_uses_dns
  
  local nm_touched=1
  nm_force_dns_all_eth || nm_touched=0
  write_resolv "$lines"
  
  sleep 1
  if test_dns "$test_host"; then
    green "  ✓ DNS restored"
    return 0
  fi

  yellow "  Applying sticky resolv.conf..."
  make_resolv_sticky
  sleep 1
  test_dns "$test_host" || fail "DNS self-heal failed"
}

check_and_install_package(){
  local pkg=$1
  local cmd=${2:-$1}
  
  if command -v "$cmd" >/dev/null 2>&1; then
    green "  ✓ $pkg already installed"
    return 0
  fi
  
  yellow "  ⚙ Installing $pkg..."
  sudo dnf install -y "$pkg" >/dev/null 2>&1 || fail "Failed to install $pkg"
  green "  ✓ $pkg installed successfully"
}

handle_port_conflict(){
  local port=$1
  local service_name=$2
  
  if ! sudo ss -tlnp | grep -q ":$port "; then
    green "  ✓ Port $port available"
    return 0
  fi
  
  yellow "  ⚠ Port $port in use"
  
  # Get process using the port
  local pid=$(sudo ss -tlnp | grep ":$port " | grep -oP 'pid=\K[0-9]+' | head -1)
  
  if [[ -n "$pid" ]]; then
    local process=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
    echo "    Process: $process (PID: $pid)"
    
    # Don't kill Keycloak or our own services
    if [[ "$process" =~ (keycloak|docker|podman|java) ]]; then
      yellow "    Keeping $process running (managed service)"
      if [[ "$port" == "$FLASK_PORT" ]]; then
        yellow "    Flask will use alternate port 5001"
        FLASK_PORT=5001
      fi
    else
      yellow "    Stopping process to free port..."
      sudo kill "$pid" 2>/dev/null || true
      sleep 2
      green "    ✓ Port $port freed"
    fi
  fi
}

################################################################################
# MAIN CHECKS
################################################################################

echo ""
blue "═══════════════════════════════════════════════════════════════"
blue "  Phase 00 - System Prerequisites (Auto-Install)"
blue "  Henry Enterprise IAM - Flask + Keycloak Architecture"
blue "═══════════════════════════════════════════════════════════════"
echo ""

# Check if already completed
if [[ -f "$MARKER_FILE" ]]; then
  LAST_RUN=$(cat "$MARKER_FILE")
  yellow "Prerequisites already completed at: $LAST_RUN"
  yellow "Re-running verification checks..."
  echo ""
fi

################################################################################
log "1/15 🔧 Checking OS version..."
if grep -q "$EXPECTED_OS" /etc/redhat-release; then
  green "  ✓ RHEL 9 confirmed"
else
  fail "Not RHEL 9! This script requires RHEL 9"
fi

################################################################################
log "2/15 🧑‍💼 Checking user privileges..."
USER_NAME=$(whoami)
if [[ "$USER_NAME" != "ec2-user" && "$USER_NAME" != "root" ]]; then
  fail "Must run as ec2-user or root. Current user: $USER_NAME"
fi
green "  ✓ User: $USER_NAME (sufficient privileges)"

################################################################################
log "3/15 📦 Checking core system tools..."
check_and_install_package "curl" "curl"
check_and_install_package "wget" "wget"
check_and_install_package "net-tools" "netstat"

if ! command -v lsattr >/dev/null 2>&1; then
  check_and_install_package "e2fsprogs" "lsattr"
fi

################################################################################
log "4/15 📡 Checking network connectivity..."
if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
  green "  ✓ Internet connectivity confirmed"
else
  yellow "  ⚠ Ping failed, checking DNS..."
fi

################################################################################
log "5/15 🌐 Checking DNS resolution..."
if test_dns "google.com"; then
  green "  ✓ DNS resolution working"
else
  self_heal_dns "google.com"
fi

################################################################################
log "6/15 🕰️ Ensuring time synchronization..."
if ! systemctl is-active --quiet chronyd; then
  yellow "  ⚙ Starting chronyd..."
  sudo systemctl enable --now chronyd 2>/dev/null || true
fi

if chronyc tracking >/dev/null 2>&1; then
  green "  ✓ Time synchronization active"
else
  yellow "  ⚠ chrony tracking unavailable (may be starting)"
fi

################################################################################
log "7/15 🔐 Checking SELinux..."
SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Unknown")
if [[ "$SELINUX_STATUS" == "Enforcing" ]]; then
  green "  ✓ SELinux: $SELINUX_STATUS (secure)"
else
  yellow "  ⚠ SELinux: $SELINUX_STATUS"
fi

################################################################################
log "8/15 📛 Configuring hostname..."
CURRENT_HOST=$(hostnamectl --static 2>/dev/null | tr -d '[:space:]')
if [[ "$CURRENT_HOST" != "$EXPECTED_HOSTNAME" ]]; then
  yellow "  ⚙ Setting hostname to $EXPECTED_HOSTNAME..."
  sudo hostnamectl set-hostname "$EXPECTED_HOSTNAME"
  green "  ✓ Hostname configured"
else
  green "  ✓ Hostname already correct: $EXPECTED_HOSTNAME"
fi

################################################################################
log "9/15 🐍 Checking Python 3.9+..."
if command -v python3 >/dev/null 2>&1; then
  PYTHON_VERSION=$(python3 --version | awk '{print $2}')
  PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d. -f1)
  PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d. -f2)
  
  if [[ $PYTHON_MAJOR -ge 3 ]] && [[ $PYTHON_MINOR -ge 9 ]]; then
    green "  ✓ Python $PYTHON_VERSION (compatible)"
  else
    yellow "  ⚠ Python $PYTHON_VERSION (3.9+ recommended)"
  fi
else
  check_and_install_package "python3" "python3"
fi

################################################################################
log "10/15 📦 Ensuring pip3 is installed..."
check_and_install_package "python3-pip" "pip3"

# Upgrade pip if needed
if command -v pip3 >/dev/null 2>&1; then
  yellow "  ⚙ Upgrading pip to latest version..."
  python3 -m pip install --upgrade pip >/dev/null 2>&1 || true
  green "  ✓ pip3 ready"
fi

################################################################################
log "11/15 🐳 Ensuring container engine..."
CONTAINER_ENGINE=""

if command -v docker >/dev/null 2>&1; then
  CONTAINER_ENGINE="docker"
  green "  ✓ Docker detected"
  
  # Ensure Docker service is running
  if ! systemctl is-active --quiet docker; then
    yellow "  ⚙ Starting Docker service..."
    sudo systemctl enable --now docker || fail "Failed to start Docker"
  fi
  green "  ✓ Docker service running"
  
elif command -v podman >/dev/null 2>&1; then
  CONTAINER_ENGINE="podman"
  green "  ✓ Podman detected"
else
  yellow "  ⚙ Installing Podman..."
  sudo dnf install -y podman podman-docker >/dev/null 2>&1 || fail "Failed to install Podman"
  CONTAINER_ENGINE="podman"
  green "  ✓ Podman installed"
fi

################################################################################
log "12/15 💾 Checking system resources..."
TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
if [[ $TOTAL_MEM -ge 4 ]]; then
  green "  ✓ Memory: ${TOTAL_MEM}GB (optimal)"
else
  yellow "  ⚠ Memory: ${TOTAL_MEM}GB (4GB+ recommended, but will work)"
fi

DISK_AVAIL=$(df -BG / | awk 'NR==2{print $4}' | sed 's/G//')
if [[ $DISK_AVAIL -ge 10 ]]; then
  green "  ✓ Disk: ${DISK_AVAIL}GB available"
else
  yellow "  ⚠ Disk: ${DISK_AVAIL}GB (10GB+ recommended)"
fi

################################################################################
log "13/15 🔌 Checking port availability..."
echo ""
handle_port_conflict $FLASK_PORT "Flask Portal"
handle_port_conflict $KEYCLOAK_PORT "Keycloak"
handle_port_conflict 8501 "HR Dashboard"
handle_port_conflict 8502 "IT Dashboard"
handle_port_conflict 8503 "Sales Dashboard"
handle_port_conflict 8504 "Admin Dashboard"

################################################################################
log "14/15 📁 Creating project directories..."
PROJECT_DIRS=(
  "/var/lib/henry-portal"
  "/var/lib/henry-portal/markers"
  "/etc/henry-portal"
  "logs"
  "scripts"
  "portal"
  "dashboards"
)

for dir in "${PROJECT_DIRS[@]}"; do
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
  fi
done
green "  ✓ Directory structure ready"

################################################################################
log "15/15 🔥 Configuring firewall (if active)..."
if systemctl is-active --quiet firewalld; then
  yellow "  ⚙ Firewall active - opening required ports..."
  
  PORTS_TO_OPEN=($FLASK_PORT $KEYCLOAK_PORT 8501 8502 8503 8504)
  for port in "${PORTS_TO_OPEN[@]}"; do
    sudo firewall-cmd --permanent --add-port=${port}/tcp >/dev/null 2>&1 || true
  done
  
  sudo firewall-cmd --reload >/dev/null 2>&1 || true
  green "  ✓ Firewall configured"
else
  green "  ✓ Firewall inactive (development mode)"
fi

################################################################################
# Create marker file
echo "$(date -Iseconds)" > "$MARKER_FILE"

echo ""
blue "═══════════════════════════════════════════════════════════════"
green "✅ Prerequisites Complete!"
blue "═══════════════════════════════════════════════════════════════"
echo ""
echo "System Summary:"
echo "  ✓ OS: RHEL 9"
echo "  ✓ Hostname: $EXPECTED_HOSTNAME"
echo "  ✓ Python: $(python3 --version | awk '{print $2}')"
echo "  ✓ Container: $CONTAINER_ENGINE"
echo "  ✓ Memory: ${TOTAL_MEM}GB"
echo "  ✓ Disk: ${DISK_AVAIL}GB"
echo "  ✓ Flask Port: $FLASK_PORT"
echo "  ✓ Keycloak Port: $KEYCLOAK_PORT"
echo ""
echo "Ready for Phase 20: FreeIPA Installation"
echo ""

exit 0
