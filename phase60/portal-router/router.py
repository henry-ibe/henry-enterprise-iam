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
