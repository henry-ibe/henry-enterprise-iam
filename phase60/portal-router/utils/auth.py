import logging
import jwt

logger = logging.getLogger(__name__)

def extract_roles_from_token(id_token: str):
    if not id_token:
        logger.warning("No ID token provided for role extraction.")
        return []
    try:
        decoded = jwt.decode(
            id_token,
            options={"verify_signature": False},  # HTTP/dev only
            algorithms=["RS256"],
        )
        roles = decoded.get("realm_access", {}).get("roles", [])
        roles = [r.lower() for r in roles]
        logger.debug(f"Extracted roles from token: {roles}")
        return roles
    except Exception as e:
        logger.exception(f"Failed to decode/extract roles: {e}")
        return []

def get_primary_role(user_roles, precedence_order):
    if not user_roles:
        return None
    for role in precedence_order:
        if role in user_roles:
            return role
    return None

