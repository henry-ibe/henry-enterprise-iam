#!/bin/bash
set -euo pipefail

LOGFILE="logs/00-prereqs.log"
mkdir -p logs
exec > >(tee -a "$LOGFILE") 2>&1

EXPECTED_OS="Red Hat Enterprise Linux release 9"
EXPECTED_HOSTNAME="ipa1.henry-iam.internal"
AWS_DNS="169.254.169.253"
FALLBACK_DNS_1="1.1.1.1"
FALLBACK_DNS_2="8.8.8.8"

green()  { echo -e "\033[0;32m$1\033[0m"; }
yellow() { echo -e "\033[1;33m$1\033[0m"; }
red()    { echo -e "\033[0;31m$1\033[0m"; }
log()    { echo -e "\n[+] $1"; }
fail()   { echo -e "\n[✘] $1"; exit 1; }
req()    { command -v "$1" >/dev/null 2>&1 || fail "$1 not installed!"; }

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
  # Only apply stickiness as a last resort; caller decides when
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
  # Prints NM connection names for a TYPE (e.g., ethernet)
  nmcli -t -f NAME,TYPE,STATE connection show --active 2>/dev/null | awk -F: -v t="$1" '$2==t{print $1}'
  nmcli -t -f NAME,TYPE connection show 2>/dev/null | awk -F: -v t="$1" '$2==t{print $1}'
}

nm_force_dns_all_eth(){
  # Force DNS on every ethernet profile we can find
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
      # Restart NM to flush caches and re-sync resolvers
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

  # Choose resolver list
  local lines
  if is_ec2; then
    lines="nameserver $AWS_DNS"
  else
    lines=$"nameserver $FALLBACK_DNS_1\nnameserver $FALLBACK_DNS_2"
  fi

  yellow "DNS lookup failed; attempting automated self-heal..."
  ensure_nss_uses_dns

  # 1) Try to force via NetworkManager (best long-term fix)
  local nm_touched=1
  nm_force_dns_all_eth || nm_touched=0

  # 2) Write a sane resolv.conf
  write_resolv "$lines"

  # 3) Re-test
  sleep 1
  if test_dns "$test_host"; then
    green "DNS restored via resolv.conf$([ $nm_touched -eq 1 ] && echo ' + NetworkManager')."
    return 0
  fi

  # 4) Last resort: make resolv.conf sticky so nothing clobbers it during the interview
  yellow "DNS still failing after NM and resolv.conf. Applying sticky resolv.conf (chattr +i)."
  make_resolv_sticky
  sleep 1
  test_dns "$test_host" || fail "DNS self-heal failed; inspect /etc/resolv.conf and NetworkManager after the interview."
}

### ---- MAIN CHECKS ----

log "🔧 Checking OS version..."
grep -q "$EXPECTED_OS" /etc/redhat-release || fail "Not RHEL 9!"

log "🧑‍💼 Checking user (ec2-user or root)..."
USER_NAME=$(whoami)
if [[ "$USER_NAME" != "ec2-user" && "$USER_NAME" != "root" ]]; then
  fail "Must run as ec2-user or root. Got: $USER_NAME"
fi

log "📦 Checking required tools (curl, sudo, nmcli, lsattr)..."
req curl
req sudo
command -v nmcli >/dev/null 2>&1 || yellow "nmcli not found; proceeding without NetworkManager tuning."
command -v lsattr >/dev/null 2>&1 || yellow "lsattr not found (e2fsprogs); resolv.conf immutability checks may be limited."

log "📡 Checking outbound internet (ping 1.1.1.1)..."
ping -c1 -W1 1.1.1.1 >/dev/null 2>&1 || fail "Ping failed!"

log "🌐 Checking DNS resolution..."
if ! test_dns "google.com"; then
  self_heal_dns "google.com"
else
  green "DNS looks good."
fi

log "🕰️ Verifying chronyd time sync status..."
if ! systemctl is-active --quiet chronyd; then
  yellow "chronyd inactive; enabling and starting..."
  sudo systemctl enable --now chronyd
fi
chronyc tracking || true

log "🔐 Checking SELinux status..."
getenforce || true

log "📛 Setting hostname to $EXPECTED_HOSTNAME..."
CURRENT_HOST=$(hostnamectl --static | tr -d '[:space:]')
if [[ "$CURRENT_HOST" != "$EXPECTED_HOSTNAME" ]]; then
  sudo hostnamectl set-hostname "$EXPECTED_HOSTNAME"
fi
hostnamectl

green "✅ All prerequisites passed. System is ready."
exit 0

