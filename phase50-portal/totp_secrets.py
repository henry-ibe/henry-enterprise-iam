"""
TOTP Secrets for Henry Enterprise Portal Users
===============================================
These are Time-based One-Time Password secrets for demo users.

In production, these would be stored securely in:
- FreeIPA OTP tokens
- A secure database with encryption
- A secrets management service (HashiCorp Vault, AWS Secrets Manager, etc.)

For this demo, we're using hardcoded secrets for simplicity.
Each user will scan their QR code with Google Authenticator.
"""

# TOTP Secrets - Base32 encoded strings
# These secrets are used to generate the QR codes and validate TOTP codes
TOTP_SECRETS = {
    'sarah': 'JBSWY3DPEHPK3PXP',      # HR Manager - Sarah Johnson
    'adam': 'JBSWY3DPEHPK3PXQ',       # IT Support - Adam Smith  
    'ivy': 'JBSWY3DPEHPK3PXR',        # Sales Representative - Ivy Chen
    'lucas': 'JBSWY3DPEHPK3PXS',      # Administrator - Lucas Martinez
}

def get_totp_secret(username):
    """
    Get TOTP secret for a specific user.
    
    Args:
        username (str): The username to look up
        
    Returns:
        str: Base32-encoded TOTP secret, or None if user not found
    """
    return TOTP_SECRETS.get(username)

def has_totp_enrolled(username):
    """
    Check if a user has TOTP enrolled.
    
    Args:
        username (str): The username to check
        
    Returns:
        bool: True if user has TOTP secret, False otherwise
    """
    return username in TOTP_SECRETS

def list_enrolled_users():
    """
    Get list of all users with TOTP enrolled.
    
    Returns:
        list: List of usernames with TOTP secrets
    """
    return list(TOTP_SECRETS.keys())
