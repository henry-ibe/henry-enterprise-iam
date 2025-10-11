#!/bin/bash
# scripts/phase60/step-8-portal-router.sh - Create portal router application

set -e

PROJECT_ROOT="$(pwd)"
PHASE60_ROOT="$PROJECT_ROOT/phase60"
ROUTER_DIR="$PHASE60_ROOT/portal-router"
UTILS_DIR="$ROUTER_DIR/utils"
ENV_FILE="$PHASE60_ROOT/.env"

echo "=== Phase 60 Step 8: Portal Router Application ==="
echo ""

# Check if .env exists
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Error: .env file not found"
    echo "Please run step-2-environment.sh first"
    exit 1
fi

# Load environment variables
source "$ENV_FILE"

echo "📝 Creating portal router application..."
echo ""

# Create requirements.txt
cat > "$ROUTER_DIR/requirements.txt" << 'EOF'
flask==3.0.0
gunicorn==21.2.0
requests==2.31.0
EOF

echo "✅ Created: requirements.txt"

# Create main router.py
cat > "$ROUTER_DIR/router.py" << 'EOF'
#!/usr/bin/env python3
"""
Portal Router - Smart role-based routing for Henry Enterprise Portal
Routes authenticated users to appropriate dashboards based on their roles
"""

from flask import Flask, request, Response
import logging
import requests
from utils.auth import extract_roles, validate_headers, get_primary_role
from utils.logging_config import setup_logging

app = Flask(__name__)
setup_logging()
logger = logging.getLogger(__name__)

# Role to upstream service mapping
ROLE_SERVICES = {
    'admin': 'http://admin-dashboard:8504',
    'hr': 'http://hr-dashboard:8501',
    'it_support': 'http://it-dashboard:8502',
    'sales': 'http://sales-dashboard:8503',
}

# Role precedence (highest to lowest priority)
ROLE_PRECEDENCE = ['admin', 'hr', 'it_support', 'sales']

@app.before_request
def log_request():
    """Log all incoming requests"""
    logger.info(f"Request: {request.method} {request.path}")
    logger.debug(f"Headers: {dict(request.headers)}")

@app.route('/health')
def health():
    """Health check endpoint"""
    return {'status': 'healthy', 'service': 'portal-router'}, 200

@app.route('/ready')
def ready():
    """Readiness check endpoint"""
    # Check if we can reach at least one dashboard
    try:
        resp = requests.get('http://hr-dashboard:8501/_stcore/health', timeout=2)
        if resp.status_code == 200:
            return {'status': 'ready', 'service': 'portal-router'}, 200
    except:
        pass
    return {'status': 'not ready'}, 503

@app.route('/', defaults={'path': ''})
@app.route('/<path:path>')
def route_to_dashboard(path):
    """
    Main routing function - directs users to appropriate dashboard
    based on their roles from OAuth2-Proxy headers
    """
    
    # Validate authentication headers
    if not validate_headers(request.headers):
        logger.warning("Invalid or missing authentication headers")
        return Response(
            "<html><body><h1>401 Unauthorized</h1>"
            "<p>Invalid authentication headers. Please log in again.</p>"
            "<a href='/oauth2/sign_out'>Sign Out</a></body></html>",
            status=401,
            mimetype='text/html'
        )
    
    # Extract user information from headers
    email = request.headers.get('X-Auth-Request-Email')
    user = request.headers.get('X-Auth-Request-User', 'unknown')
    roles_header = request.headers.get('X-Auth-Request-Groups', '')
    
    # Parse roles
    roles = extract_roles(roles_header)
    
    if not roles:
        logger.warning(f"No roles found for user {email}")
        return Response(
            "<html><body><h1>403 Access Denied</h1>"
            "<p>No roles assigned to your account. Please contact your administrator.</p>"
            f"<p>User: {email}</p>"
            "<a href='/oauth2/sign_out'>Sign Out</a></body></html>",
            status=403,
            mimetype='text/html'
        )
    
    # Determine primary role based on precedence
    primary_role = get_primary_role(roles, ROLE_PRECEDENCE)
    
    if not primary_role:
        logger.warning(f"User {email} has unrecognized roles: {roles}")
        return Response(
            "<html><body><h1>403 Access Denied</h1>"
            "<p>Invalid role assignment. Please contact your administrator.</p>"
            f"<p>User: {email}</p>"
            f"<p>Roles: {', '.join(roles)}</p>"
            "<a href='/oauth2/sign_out'>Sign Out</a></body></html>",
            status=403,
            mimetype='text/html'
        )
    
    # Get target service for the primary role
    target_service = ROLE_SERVICES.get(primary_role)
    
    if not target_service:
        logger.error(f"No service configured for role {primary_role}")
        return Response(
            "<html><body><h1>500 Internal Server Error</h1>"
            "<p>Service configuration error. Please contact support.</p></body></html>",
            status=500,
            mimetype='text/html'
        )
    
    # Log successful routing
    logger.info(f"✅ Routing user {email} (role: {primary_role}) to {target_service}/{path}")
    
    # Proxy the request to the appropriate dashboard
    try:
        target_url = f"{target_service}/{path}"
        
        # Prepare headers to forward
        forward_headers = {
            'X-User-Email': email,
            'X-User-Roles': ','.join(roles),
            'X-Primary-Role': primary_role,
            'X-Forwarded-For': request.headers.get('X-Forwarded-For', request.remote_addr),
            'X-Forwarded-Proto': request.headers.get('X-Forwarded-Proto', 'http'),
        }
        
        # Forward the request
        resp = requests.request(
            method=request.method,
            url=target_url,
            headers=forward_headers,
            data=request.get_data(),
            cookies=request.cookies,
            allow_redirects=False,
            timeout=30,
            stream=True
        )
        
        # Prepare response headers
        excluded_headers = ['content-encoding', 'content-length', 'transfer-encoding', 'connection']
        headers = [
            (name, value) for (name, value) in resp.raw.headers.items()
            if name.lower() not in excluded_headers
        ]
        
        # Create and return response
        response = Response(
            resp.iter_content(chunk_size=8192),
            resp.status_code,
            headers
        )
        return response
        
    except requests.exceptions.ConnectionError as e:
        logger.error(f"Connection error to {target_service}: {str(e)}")
        return Response(
            "<html><body><h1>503 Service Unavailable</h1>"
            f"<p>The {primary_role} dashboard is currently unavailable.</p>"
            "<p>Please try again later.</p></body></html>",
            status=503,
            mimetype='text/html'
        )
    except requests.exceptions.Timeout as e:
        logger.error(f"Timeout connecting to {target_service}: {str(e)}")
        return Response(
            "<html><body><h1>504 Gateway Timeout</h1>"
            f"<p>The {primary_role} dashboard is taking too long to respond.</p>"
            "<p>Please try again later.</p></body></html>",
            status=504,
            mimetype='text/html'
        )
    except Exception as e:
        logger.error(f"Unexpected error proxying to {target_service}: {str(e)}")
        return Response(
            "<html><body><h1>500 Internal Server Error</h1>"
            "<p>An unexpected error occurred. Please contact support.</p></body></html>",
            status=500,
            mimetype='text/html'
        )

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8500, debug=False)
EOF

echo "✅ Created: router.py (main application)"

# Create utils/auth.py
cat > "$UTILS_DIR/auth.py" << 'EOF'
"""
Authentication utilities for portal router
Handles role extraction and header validation
"""

import logging
import json

logger = logging.getLogger(__name__)

def extract_roles(roles_header):
    """
    Extract roles from header.
    Supports both comma-separated and JSON array formats.
    
    Args:
        roles_header: String containing roles (comma-separated or JSON array)
    
    Returns:
        List of role strings
    """
    if not roles_header:
        return []
    
    # Handle JSON array format: ["role1","role2"]
    if roles_header.startswith('['):
        try:
            roles = json.loads(roles_header)
            # Filter out empty strings and convert to lowercase
            return [role.strip().lower() for role in roles if role.strip()]
        except json.JSONDecodeError:
            logger.warning(f"Failed to parse roles as JSON: {roles_header}")
            return []
    
    # Handle comma-separated format: "role1,role2"
    roles = [role.strip().lower() for role in roles_header.split(',') if role.strip()]
    return roles

def validate_headers(headers):
    """
    Validate that required authentication headers are present.
    These headers are injected by OAuth2-Proxy and should NEVER
    come from the browser directly.
    
    Args:
        headers: Flask request headers object
    
    Returns:
        Boolean indicating if headers are valid
    """
    required_headers = ['X-Auth-Request-Email', 'X-Auth-Request-User']
    
    for header in required_headers:
        if not headers.get(header):
            logger.warning(f"Missing required header: {header}")
            return False
    
    # Additional validation: email should look like an email
    email = headers.get('X-Auth-Request-Email', '')
    if '@' not in email:
        logger.warning(f"Invalid email format in header: {email}")
        return False
    
    return True

def get_primary_role(roles, precedence):
    """
    Determine primary role based on precedence.
    The first role found in precedence list is returned.
    
    Args:
        roles: List of user's roles
        precedence: List of roles in priority order
    
    Returns:
        String role name or None if no valid role found
    """
    for role in precedence:
        if role in roles:
            logger.debug(f"Selected primary role: {role} from {roles}")
            return role
    
    logger.warning(f"No valid role found in {roles} matching precedence {precedence}")
    return None
EOF

echo "✅ Created: utils/auth.py"

# Create utils/logging_config.py
cat > "$UTILS_DIR/logging_config.py" << 'EOF'
"""
Logging configuration for portal router
Provides structured JSON logging for easy parsing
"""

import logging
import json
import sys
from datetime import datetime

class JSONFormatter(logging.Formatter):
    """
    Format logs as JSON for easy parsing by log aggregators.
    """
    def format(self, record):
        log_data = {
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'level': record.levelname,
            'logger': record.name,
            'message': record.getMessage(),
            'module': record.module,
            'function': record.funcName,
            'line': record.lineno
        }
        
        # Add user context if available
        if hasattr(record, 'user_email'):
            log_data['user_email'] = record.user_email
        
        if hasattr(record, 'user_roles'):
            log_data['user_roles'] = record.user_roles
        
        # Add exception info if present
        if record.exc_info:
            log_data['exception'] = self.formatException(record.exc_info)
        
        return json.dumps(log_data)

def setup_logging():
    """
    Configure application logging with JSON formatter.
    """
    # Create handler
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JSONFormatter())
    
    # Configure root logger
    root_logger = logging.getLogger()
    root_logger.addHandler(handler)
    root_logger.setLevel(logging.INFO)
    
    # Set debug level for auth-related logs
    logging.getLogger('utils.auth').setLevel(logging.DEBUG)
    
    # Reduce noise from other libraries
    logging.getLogger('werkzeug').setLevel(logging.WARNING)
    logging.getLogger('urllib3').setLevel(logging.WARNING)
EOF

echo "✅ Created: utils/logging_config.py"

# Create utils/__init__.py
cat > "$UTILS_DIR/__init__.py" << 'EOF'
"""
Utility modules for portal router
"""
from .auth import extract_roles, validate_headers, get_primary_role
from .logging_config import setup_logging

__all__ = ['extract_roles', 'validate_headers', 'get_primary_role', 'setup_logging']
EOF

echo "✅ Created: utils/__init__.py"

# Create Dockerfile
cat > "$ROUTER_DIR/Dockerfile" << 'EOF'
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY router.py .
COPY utils/ ./utils/

# Create non-root user
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 8500

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:8500/health', timeout=5)"

# Run with gunicorn
CMD ["gunicorn", "--bind", "0.0.0.0:8500", "--workers", "4", "--timeout", "120", "--access-logfile", "-", "--error-logfile", "-", "router:app"]
EOF

echo "✅ Created: Dockerfile"

# Create README
cat > "$ROUTER_DIR/README.md" << EOF
# Portal Router

Smart role-based routing application for Henry Enterprise Portal.

## Purpose

The portal router:
1. Receives authenticated requests from OAuth2-Proxy
2. Extracts user roles from HTTP headers
3. Routes users to appropriate dashboard based on role precedence
4. Proxies all requests/responses transparently

## Architecture

\`\`\`
OAuth2-Proxy → Portal Router → Role-Specific Dashboard
              (validates headers)
              (determines role)
              (proxies request)
\`\`\`

## Role Precedence

When a user has multiple roles, priority is:
1. **admin** - Full access (sees admin dashboard)
2. **hr** - HR dashboard
3. **it_support** - IT dashboard
4. **sales** - Sales dashboard

## Headers

### Input (from OAuth2-Proxy)
- \`X-Auth-Request-Email\`: User's email
- \`X-Auth-Request-User\`: Username
- \`X-Auth-Request-Groups\`: Comma-separated or JSON array of roles

### Output (to dashboards)
- \`X-User-Email\`: User's email
- \`X-User-Roles\`: All user roles (comma-separated)
- \`X-Primary-Role\`: The role used for routing

## Endpoints

- \`GET /health\`: Health check (always returns 200)
- \`GET /ready\`: Readiness check (tests dashboard connectivity)
- \`GET /*\`: All other requests are routed based on user role

## Local Development

\`\`\`bash
# Install dependencies
pip install -r requirements.txt

# Run locally
python router.py

# Test
curl http://localhost:8500/health
\`\`\`

## Building Docker Image

\`\`\`bash
docker build -t portal-router:latest .
\`\`\`

## Testing

\`\`\`bash
# Test with mock headers
curl -H "X-Auth-Request-Email: test@example.com" \\
     -H "X-Auth-Request-User: testuser" \\
     -H "X-Auth-Request-Groups: hr" \\
     http://localhost:8500/
\`\`\`
EOF

echo "✅ Created: README.md"

echo ""
echo "📋 Files created:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ls -lh "$ROUTER_DIR"
echo ""
echo "Utils:"
ls -lh "$UTILS_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Validate Python syntax
echo "🧪 Validating Python syntax..."
python3 -m py_compile "$ROUTER_DIR/router.py" && echo "  ✅ router.py - Valid syntax"
python3 -m py_compile "$UTILS_DIR/auth.py" && echo "  ✅ utils/auth.py - Valid syntax"
python3 -m py_compile "$UTILS_DIR/logging_config.py" && echo "  ✅ utils/logging_config.py - Valid syntax"

echo ""
echo "✅ Step 8 Complete: Portal router application ready"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "What this does:"
echo "  • Validates authentication headers from OAuth2-Proxy"
echo "  • Extracts user roles from headers"
echo "  • Determines primary role based on precedence"
echo "  • Routes to appropriate dashboard"
echo "  • Proxies requests/responses transparently"
echo "  • Provides structured JSON logging"
echo "  • Includes health/readiness checks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next: Step 9 - Create dashboard applications (HR, IT, Sales, Admin)"
