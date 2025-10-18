from ldap3 import Server, Connection, ALL, SUBTREE
from ldap3.core.exceptions import LDAPException
import pyotp
import logging
from datetime import datetime
from config import Config
from app.models import User
from app.metrics import (
    track_ldap_auth, track_totp_verification, track_unauthorized_access,
    track_invalid_credentials, timer
)

logging.basicConfig(filename=Config.LOG_FILE, level=logging.INFO,
                   format='%(asctime)s | %(levelname)s | %(message)s',
                   datefmt='%Y-%m-%d %H:%M:%S')
logger = logging.getLogger(__name__)

class AuthenticationError(Exception):
    pass

def authenticate_ldap(username: str, password: str, selected_department: str):
    """
    Step 1: Authenticate username/password against LDAP and validate department.
    Returns user data dictionary (NOT User object) for session storage.
    Does NOT validate TOTP - that's done separately in verify_totp_code().
    Includes Prometheus metrics tracking for monitoring.
    """
    # Start timing for performance metrics
    with timer() as t:
        try:
            server = Server(Config.LDAP_HOST, get_info=ALL)
            user_dn = f'uid={username},{Config.LDAP_USER_BASE}'
            
            # Attempt LDAP bind with credentials
            conn = Connection(server, user=user_dn, password=password, auto_bind=True)
            
            if not conn.bind():
                logger.warning(f"FAILED | {username} | {selected_department} | Invalid credentials")
                # Track metrics: failed LDAP auth and invalid credentials
                track_ldap_auth(username, success=False, duration=t.duration)
                track_invalid_credentials(username)
                raise AuthenticationError("Invalid username or password")
            
            logger.info(f"LDAP_AUTH_SUCCESS | {username} | LDAP bind successful")
            
            # Search for user details
            search_filter = f'(uid={username})'
            conn.search(search_base=Config.LDAP_USER_BASE, search_filter=search_filter,
                       search_scope=SUBTREE, attributes=['uid', 'cn', 'mail', 'givenName', 'sn', 'memberOf'])
            
            if not conn.entries:
                logger.error(f"ERROR | {username} | User not found in LDAP")
                track_ldap_auth(username, success=False, duration=t.duration)
                raise AuthenticationError("User not found")
            
            entry = conn.entries[0]
            full_name = str(entry.cn) if hasattr(entry, 'cn') else username
            email = str(entry.mail) if hasattr(entry, 'mail') else f"{username}@henry-iam.internal"
            
            # Extract user groups
            user_groups = []
            if hasattr(entry, 'memberOf'):
                for group_dn in entry.memberOf:
                    group_name = str(group_dn).split(',')[0].split('=')[1]
                    user_groups.append(group_name)
            
            logger.info(f"USER_GROUPS | {username} | Groups: {', '.join(user_groups)}")
            
            # Validate department authorization
            required_group = Config.DEPARTMENT_GROUPS.get(selected_department)
            if not required_group:
                logger.error(f"ERROR | {username} | Invalid department: {selected_department}")
                track_ldap_auth(username, success=False, duration=t.duration)
                raise AuthenticationError("Invalid department selected")
            
            if required_group not in user_groups:
                logger.warning(f"DENIED | {username} | {selected_department} | Unauthorized access attempt | User groups: {', '.join(user_groups)}")
                # CRITICAL METRIC: Track unauthorized department access attempt
                # This is what shows up in your security dashboard!
                track_unauthorized_access(username, selected_department, user_groups)
                track_ldap_auth(username, success=False, duration=t.duration)
                raise AuthenticationError(f"Access denied: You are not authorized for {selected_department} department")
            
            logger.info(f"LDAP_VALIDATED | {username} | {selected_department} | Department authorization confirmed")
            
            conn.unbind()
            
            # Track successful LDAP authentication with timing
            track_ldap_auth(username, success=True, duration=t.duration)
            
            # Return user data as dictionary (for session storage)
            return {
                'username': username,
                'full_name': full_name,
                'email': email,
                'groups': user_groups,
                'timestamp': datetime.now().isoformat()
            }
            
        except LDAPException as e:
            logger.error(f"LDAP_ERROR | {username} | {str(e)}")
            track_ldap_auth(username, success=False, duration=t.duration)
            raise AuthenticationError(f"LDAP error: {str(e)}")
        except AuthenticationError:
            # Already tracked above, just re-raise
            raise
        except Exception as e:
            logger.error(f"ERROR | {username} | {str(e)}")
            track_ldap_auth(username, success=False, duration=t.duration)
            raise AuthenticationError(f"Authentication error: {str(e)}")

def verify_totp_code(username: str, totp_code: str):
    """
    Step 2: Verify TOTP code from authenticator app.
    This is called AFTER LDAP authentication succeeds.
    Validates the code against the user's TOTP secret.
    Raises AuthenticationError if TOTP is invalid.
    Includes Prometheus metrics tracking for TOTP verification attempts.
    """
    with timer() as t:
        try:
            if not totp_code:
                logger.warning(f"TOTP_FAILED | {username} | No TOTP code provided")
                track_totp_verification(username, success=False, duration=t.duration)
                raise AuthenticationError("TOTP code is required")
            
            # Remove any spaces or dashes
            totp_code = totp_code.strip().replace(' ', '').replace('-', '')
            
            # Validate format (6 digits)
            if not totp_code.isdigit() or len(totp_code) != 6:
                logger.warning(f"TOTP_FAILED | {username} | Invalid TOTP format: {totp_code}")
                track_totp_verification(username, success=False, duration=t.duration)
                raise AuthenticationError("TOTP code must be 6 digits")
            
            # Get user's TOTP secret from totp_secrets.py
            try:
                from totp_secrets import get_totp_secret
                totp_secret = get_totp_secret(username)
            except ImportError:
                logger.error(f"TOTP_ERROR | {username} | totp_secrets.py not found")
                track_totp_verification(username, success=False, duration=t.duration)
                raise AuthenticationError("TOTP system not configured. Please contact administrator.")
            
            if not totp_secret:
                logger.warning(f"TOTP_FAILED | {username} | No TOTP secret found for user")
                track_totp_verification(username, success=False, duration=t.duration)
                raise AuthenticationError("TOTP not enrolled for this user. Please enroll at /employee/enroll-totp")
            
            # Validate TOTP code using pyotp
            totp = pyotp.TOTP(totp_secret)
            
            # valid_window=1 allows codes from 30 seconds before/after current time
            # This accounts for minor time drift between server and phone
            if not totp.verify(totp_code, valid_window=1):
                logger.warning(f"TOTP_FAILED | {username} | Invalid TOTP code: {totp_code}")
                track_totp_verification(username, success=False, duration=t.duration)
                raise AuthenticationError("Invalid TOTP code. Please check your authenticator app and try again.")
            
            logger.info(f"TOTP_SUCCESS | {username} | TOTP code validated successfully")
            # Track successful TOTP verification with timing
            track_totp_verification(username, success=True, duration=t.duration)
            return True
            
        except AuthenticationError:
            # Already tracked above, just re-raise
            raise
        except Exception as e:
            logger.error(f"TOTP_ERROR | {username} | {str(e)}")
            track_totp_verification(username, success=False, duration=t.duration)
            raise AuthenticationError(f"TOTP validation error: {str(e)}")

def log_logout(username: str):
    """Log user logout event and track metrics"""
    from app.metrics import track_logout
    logger.info(f"LOGOUT | {username} | User logged out")
    track_logout(username)
