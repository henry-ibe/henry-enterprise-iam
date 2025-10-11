#!/bin/bash
# scripts/phase60/step-11-update-start-script.sh - Create idempotent start script

set -e

PROJECT_ROOT="$(pwd)"
PHASE60_ROOT="$PROJECT_ROOT/phase60"

echo "=== Phase 60 Step 11: Creating Idempotent Start Script ==="
echo ""

cat > "$PHASE60_ROOT/start.sh" << 'EOF'
#!/bin/bash
# Idempotent start script for Phase 60 Employee Portal
# Checks and installs Docker/Docker Compose if needed

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== Phase 60: Starting Employee Portal ==="
echo ""

# ==================== DEPENDENCY CHECKS ====================

echo "🔍 Checking dependencies..."
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if user is in docker group
user_in_docker_group() {
    groups | grep -q docker
}

# Check Docker
DOCKER_INSTALLED=false
NEED_RELOGIN=false

if command_exists docker; then
    echo "✅ Docker is installed ($(docker --version))"
    DOCKER_INSTALLED=true
    
    # Check if Docker daemon is running
    if ! sudo systemctl is-active --quiet docker; then
        echo "🔄 Starting Docker service..."
        sudo systemctl start docker
        sudo systemctl enable docker
    fi
    
    # Check if user is in docker group
    if ! user_in_docker_group; then
        echo "⚠️  Adding $USER to docker group..."
        sudo usermod -aG docker "$USER"
        NEED_RELOGIN=true
    fi
else
    echo "❌ Docker not found"
    DOCKER_INSTALLED=false
fi

# Check Docker Compose
COMPOSE_INSTALLED=false
COMPOSE_CMD=""

if command_exists docker-compose; then
    echo "✅ docker-compose is installed ($(docker-compose --version))"
    COMPOSE_INSTALLED=true
    COMPOSE_CMD="docker-compose"
elif docker compose version >/dev/null 2>&1; then
    echo "✅ docker compose plugin is installed ($(docker compose version))"
    COMPOSE_INSTALLED=true
    COMPOSE_CMD="docker compose"
else
    echo "❌ Docker Compose not found"
    COMPOSE_INSTALLED=false
fi

echo ""

# ==================== INSTALL DOCKER IF NEEDED ====================

if [ "$DOCKER_INSTALLED" = false ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 Docker Installation Required"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    read -p "Install Docker now? (yes/no): " install_docker
    
    if [ "$install_docker" != "yes" ]; then
        echo "❌ Cannot proceed without Docker. Exiting."
        exit 1
    fi
    
    echo ""
    echo "📦 Installing Docker..."
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    fi
    
    case "$OS" in
        amzn|amazonlinux)
            echo "  Detected: Amazon Linux"
            sudo yum install -y docker
            ;;
        rhel|centos|rocky|almalinux)
            echo "  Detected: RHEL/CentOS family"
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io
            ;;
        ubuntu|debian)
            echo "  Detected: Ubuntu/Debian"
            sudo apt-get update
            sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
            sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io
            ;;
        *)
            echo "❌ Unsupported OS: $OS"
            echo "Please install Docker manually: https://docs.docker.com/engine/install/"
            exit 1
            ;;
    esac
    
    # Start Docker
    echo "  Starting Docker service..."
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Add user to docker group
    echo "  Adding $USER to docker group..."
    sudo usermod -aG docker "$USER"
    
    echo "✅ Docker installed successfully"
    NEED_RELOGIN=true
fi

# ==================== INSTALL DOCKER COMPOSE IF NEEDED ====================

if [ "$COMPOSE_INSTALLED" = false ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 Docker Compose Installation Required"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    read -p "Install Docker Compose now? (yes/no): " install_compose
    
    if [ "$install_compose" != "yes" ]; then
        echo "❌ Cannot proceed without Docker Compose. Exiting."
        exit 1
    fi
    
    echo ""
    echo "📦 Installing Docker Compose..."
    
    # Get latest version
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    # Download and install
    sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    
    # Create symlink if needed
    if [ ! -L /usr/bin/docker-compose ]; then
        sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    fi
    
    echo "✅ Docker Compose installed successfully ($(docker-compose --version))"
    COMPOSE_CMD="docker-compose"
fi

# ==================== CHECK IF RELOGIN NEEDED ====================

if [ "$NEED_RELOGIN" = true ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  RELOGIN REQUIRED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Your user was added to the 'docker' group."
    echo "You need to log out and log back in for this to take effect."
    echo ""
    echo "After logging back in, run this script again:"
    echo "  cd $(pwd)"
    echo "  ./start.sh"
    echo ""
    exit 0
fi

# ==================== PRE-FLIGHT CHECKS ====================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ All dependencies satisfied"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found"
    echo "Please run the setup scripts first"
    exit 1
fi

# Load environment
source .env

echo "📋 Configuration:"
echo "  Domain: $DOMAIN"
echo "  Portal: $PORTAL_DOMAIN"
echo "  Compose Command: $COMPOSE_CMD"
echo ""

# Check for port conflicts
echo "🔍 Checking for port conflicts..."
PORTS_IN_USE=""
for port in 80 443 8080; do
    if sudo netstat -tuln 2>/dev/null | grep -q ":$port "; then
        PORTS_IN_USE="$PORTS_IN_USE $port"
    fi
done

if [ -n "$PORTS_IN_USE" ]; then
    echo "⚠️  Warning: Ports in use:$PORTS_IN_USE"
    echo ""
    echo "These services might be using the ports:"
    sudo netstat -tulpn 2>/dev/null | grep -E ":(80|443|8080) " || true
    echo ""
    read -p "Stop conflicting services and continue? (yes/no): " stop_services
    
    if [ "$stop_services" = "yes" ]; then
        echo "🛑 Attempting to stop common web services..."
        for service in httpd nginx apache2; do
            if sudo systemctl is-active --quiet $service 2>/dev/null; then
                echo "  Stopping $service..."
                sudo systemctl stop $service
            fi
        done
    else
        echo "❌ Cannot proceed with ports in use. Exiting."
        exit 1
    fi
fi

echo "✅ No port conflicts"
echo ""

# ==================== BUILD AND START ====================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔨 Building Docker images..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Try without sudo first, fall back to sudo if needed
if $COMPOSE_CMD build --parallel 2>/dev/null; then
    echo ""
else
    echo "  Retrying with sudo..."
    sudo $COMPOSE_CMD build --parallel
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Starting services..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Start services
if $COMPOSE_CMD up -d 2>/dev/null; then
    echo ""
else
    echo "  Retrying with sudo..."
    sudo $COMPOSE_CMD up -d
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⏳ Waiting for services to be healthy..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Wait for Keycloak to be healthy (it takes the longest)
echo "⏳ Waiting for Keycloak to initialize (this takes ~60 seconds)..."
for i in {1..60}; do
    if $COMPOSE_CMD ps 2>/dev/null | grep -q "keycloak.*healthy" || sudo $COMPOSE_CMD ps | grep -q "keycloak.*healthy"; then
        echo "✅ Keycloak is ready!"
        break
    fi
    sleep 2
    echo -n "."
done
echo ""

sleep 5

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Service Status:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Show service status
if $COMPOSE_CMD ps 2>/dev/null; then
    true
else
    sudo $COMPOSE_CMD ps
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Phase 60 Employee Portal Started!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "${GREEN}Access Points:${NC}"
echo "  🌐 Public Site:       ${BLUE}http://$DOMAIN${NC}"
echo "  🔐 Employee Portal:   ${BLUE}http://$PORTAL_DOMAIN${NC}"
echo "  ⚙️  Keycloak Admin:    ${BLUE}http://$DOMAIN:8080/auth/admin${NC}"
echo "  📊 Traefik Dashboard: ${BLUE}http://traefik.$DOMAIN:8080${NC}"
echo "  📈 Prometheus:        ${BLUE}http://localhost:9090${NC}"
echo ""
echo "${YELLOW}Test Users:${NC}"
echo "  • alice.hr      / HRPass123!      → HR Dashboard"
echo "  • bob.it        / ITPass123!      → IT Dashboard"
echo "  • carol.sales   / SalesPass123!   → Sales Dashboard"
echo "  • admin         / AdminPass123!   → Admin Dashboard (all access)"
echo ""
echo "${YELLOW}Keycloak Admin:${NC}"
echo "  • Username: ${KEYCLOAK_ADMIN}"
echo "  • Password: ${KEYCLOAK_ADMIN_PASSWORD}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📝 Useful commands:"
echo "  View logs:          ${COMPOSE_CMD} logs -f [service-name]"
echo "  Check status:       ./status.sh"
echo "  Stop all services:  ./stop.sh"
echo "  Restart a service:  ${COMPOSE_CMD} restart [service-name]"
echo ""
EOF

chmod +x "$PHASE60_ROOT/start.sh"

echo "✅ Created: Idempotent start.sh script"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Features added:"
echo "  ✅ Automatic Docker detection and installation"
echo "  ✅ Automatic Docker Compose detection and installation"
echo "  ✅ Docker group membership check"
echo "  ✅ Port conflict detection"
echo "  ✅ Automatic service stopping (with confirmation)"
echo "  ✅ Graceful sudo fallback"
echo "  ✅ Multi-OS support (Amazon Linux, RHEL, Ubuntu)"
echo "  ✅ Colored output for better readability"
echo "  ✅ Comprehensive error handling"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ Step 11 Complete: Enhanced start script ready!"
echo ""
echo "Now you can run:"
echo "  cd ~/henry-enterprise-iam/phase60"
echo "  ./start.sh"
echo ""
echo "The script will:"
echo "  1. Check if Docker is installed (install if missing)"
echo "  2. Check if Docker Compose is installed (install if missing)"
echo "  3. Check for port conflicts (stop services if needed)"
echo "  4. Build and start all services"
echo "  5. Wait for health checks"
echo "  6. Show you access URLs"
EOF

chmod +x "$PROJECT_ROOT/scripts/phase60/step-11-update-start-script.sh"

echo "✅ Created: step-11-update-start-script.sh"
echo ""
echo "Run this to update your start.sh:"
echo "  ./scripts/phase60/step-11-update-start-script.sh"
