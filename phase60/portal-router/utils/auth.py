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
