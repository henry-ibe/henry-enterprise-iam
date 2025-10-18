"""
Prometheus Metrics for Henry Enterprise Portal
Security and authentication metrics for monitoring and alerting
"""

from prometheus_client import Counter, Histogram, Gauge, Info
import time

# ============================================================================
# Authentication Metrics
# ============================================================================

# Counter for login attempts
login_attempts_total = Counter(
    'henry_portal_login_attempts_total',
    'Total number of login attempts',
    ['status', 'department', 'username']
)

# Counter for LDAP authentication
ldap_auth_total = Counter(
    'henry_portal_ldap_auth_total',
    'Total LDAP authentication attempts',
    ['status', 'username']
)

# Counter for TOTP verification
totp_verification_total = Counter(
    'henry_portal_totp_verification_total',
    'Total TOTP verification attempts',
    ['status', 'username']
)

# Counter for unauthorized department access attempts
unauthorized_access_attempts_total = Counter(
    'henry_portal_unauthorized_access_total',
    'Unauthorized department access attempts',
    ['username', 'requested_department', 'actual_groups']
)

# Counter for invalid credentials
invalid_credentials_total = Counter(
    'henry_portal_invalid_credentials_total',
    'Failed login attempts with invalid credentials',
    ['username']
)

# Counter for successful authentications
successful_auth_total = Counter(
    'henry_portal_successful_auth_total',
    'Successful complete authentications',
    ['username', 'department']
)

# Counter for logouts
logout_total = Counter(
    'henry_portal_logout_total',
    'User logout events',
    ['username']
)

# ============================================================================
# Performance Metrics
# ============================================================================

# Histogram for LDAP response times
ldap_response_time = Histogram(
    'henry_portal_ldap_response_seconds',
    'LDAP authentication response time in seconds',
    ['username']
)

# Histogram for TOTP validation times
totp_validation_time = Histogram(
    'henry_portal_totp_validation_seconds',
    'TOTP validation response time in seconds',
    ['username']
)

# Histogram for overall authentication time
auth_duration = Histogram(
    'henry_portal_auth_duration_seconds',
    'Complete authentication duration in seconds',
    ['status']
)

# ============================================================================
# Session Metrics
# ============================================================================

# Gauge for active sessions
active_sessions = Gauge(
    'henry_portal_active_sessions',
    'Number of active user sessions',
    ['department']
)

# Gauge for pending TOTP verifications
pending_totp_verifications = Gauge(
    'henry_portal_pending_totp_verifications',
    'Number of users waiting for TOTP verification'
)

# ============================================================================
# Application Info
# ============================================================================

# Info metric for application version
app_info = Info(
    'henry_portal_app',
    'Henry Enterprise Portal application information'
)

app_info.info({
    'version': '2.0',
    'features': '2FA-TOTP,LDAP,RBAC',
    'environment': 'production'
})

# ============================================================================
# Helper Functions
# ============================================================================

def track_login_attempt(username: str, department: str, status: str):
    """Track a login attempt"""
    login_attempts_total.labels(
        status=status,
        department=department,
        username=username
    ).inc()

def track_ldap_auth(username: str, success: bool, duration: float = 0):
    """Track LDAP authentication"""
    status = 'success' if success else 'failed'
    ldap_auth_total.labels(status=status, username=username).inc()
    if duration > 0:
        ldap_response_time.labels(username=username).observe(duration)

def track_totp_verification(username: str, success: bool, duration: float = 0):
    """Track TOTP verification"""
    status = 'success' if success else 'failed'
    totp_verification_total.labels(status=status, username=username).inc()
    if duration > 0:
        totp_validation_time.labels(username=username).observe(duration)

def track_unauthorized_access(username: str, requested_dept: str, user_groups: list):
    """Track unauthorized department access attempt"""
    unauthorized_access_attempts_total.labels(
        username=username,
        requested_department=requested_dept,
        actual_groups=','.join(user_groups)
    ).inc()

def track_invalid_credentials(username: str):
    """Track failed login with invalid credentials"""
    invalid_credentials_total.labels(username=username).inc()

def track_successful_auth(username: str, department: str):
    """Track successful complete authentication"""
    successful_auth_total.labels(
        username=username,
        department=department
    ).inc()

def track_logout(username: str):
    """Track user logout"""
    logout_total.labels(username=username).inc()

def update_active_sessions(department: str, count: int):
    """Update active sessions gauge"""
    active_sessions.labels(department=department).set(count)

def update_pending_totp(count: int):
    """Update pending TOTP verifications"""
    pending_totp_verifications.set(count)

# ============================================================================
# Context Managers for Timing
# ============================================================================

class timer:
    """Context manager for timing operations"""
    def __init__(self):
        self.start = None
        self.duration = 0
    
    def __enter__(self):
        self.start = time.time()
        return self
    
    def __exit__(self, *args):
        self.duration = time.time() - self.start
