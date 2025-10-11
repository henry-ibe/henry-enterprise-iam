#!/bin/bash
# setup-project-structure.sh - Idempotent project structure setup

set -e  # Exit on error

# Use current directory as project root
PROJECT_ROOT="$(pwd)"

echo "=== Phase 60: Project Structure Setup ==="
echo "Working in: $PROJECT_ROOT"
echo ""

# Function to create directory if it doesn't exist
create_dir() {
    if [ ! -d "$1" ]; then
        mkdir -p "$1"
        echo "✅ Created: $1"
    else
        echo "⏭️  Already exists: $1"
    fi
}

# Create Phase 60 subdirectory structure
echo "Creating Phase 60 subdirectories..."

# Create phase60 as a subdirectory to keep it organized
create_dir "$PROJECT_ROOT/phase60"
create_dir "$PROJECT_ROOT/phase60/traefik"
create_dir "$PROJECT_ROOT/phase60/oauth2-proxy"
create_dir "$PROJECT_ROOT/phase60/keycloak"
create_dir "$PROJECT_ROOT/phase60/public-site"
create_dir "$PROJECT_ROOT/phase60/portal-router"
create_dir "$PROJECT_ROOT/phase60/portal-router/utils"
create_dir "$PROJECT_ROOT/phase60/dashboards"
create_dir "$PROJECT_ROOT/phase60/dashboards/hr"
create_dir "$PROJECT_ROOT/phase60/dashboards/it"
create_dir "$PROJECT_ROOT/phase60/dashboards/sales"
create_dir "$PROJECT_ROOT/phase60/dashboards/admin"
create_dir "$PROJECT_ROOT/phase60/monitoring"
create_dir "$PROJECT_ROOT/phase60/monitoring/grafana-dashboards"
create_dir "$PROJECT_ROOT/phase60/docs"

# Keep scripts in existing scripts directory
echo ""
echo "Using existing scripts directory: $PROJECT_ROOT/scripts"

echo ""
echo "=== Directory Structure Created ==="
echo ""
echo "Phase 60 structure:"
ls -la "$PROJECT_ROOT/phase60/" 2>/dev/null || echo "Creating phase60 directory..."

echo ""
echo "✅ Step 1 Complete: Project structure ready"
echo ""
echo "Your project layout:"
echo "henry-enterprise-iam/"
echo "├── config/          (existing)"
echo "├── git/             (existing)"
echo "├── iam/             (existing)"
echo "├── any/             (existing)"
echo "├── scripts/         (existing - we'll add Phase 60 scripts here)"
echo "└── phase60/         (NEW - all Phase 60 files here)"
echo "    ├── traefik/"
echo "    ├── oauth2-proxy/"
echo "    ├── keycloak/"
echo "    ├── portal-router/"
echo "    ├── dashboards/"
echo "    └── docs/"
echo ""
echo "Next: We'll create the .env file and environment setup"
