from flask import Blueprint, render_template, request, redirect, url_for, session, flash
from app.auth import authenticate_ldap, verify_totp_code, AuthenticationError, log_logout
from app.models import User
from functools import wraps
from config import Config
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST
from app.metrics import track_login_attempt, track_successful_auth

main_bp = Blueprint('main', __name__)

def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user' not in session:
            flash('Please log in to access this page', 'warning')
            return redirect(url_for('main.employee_login'))
        return f(*args, **kwargs)
    return decorated_function

def department_required(department):
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            if 'user' not in session:
                flash('Please log in to access this page', 'warning')
                return redirect(url_for('main.employee_login'))
            user = User.from_dict(session['user'])
            if not user.has_role(department):
                flash(f'Access denied: You are not authorized for {department} department', 'danger')
                return redirect(url_for('main.landing'))
            return f(*args, **kwargs)
        return decorated_function
    return decorator

@main_bp.route('/')
def landing():
    return render_template('landing.html')

@main_bp.route('/employee/login', methods=['GET', 'POST'])
def employee_login():
    # If already fully authenticated, redirect to dashboard
    if 'user' in session:
        user = User.from_dict(session['user'])
        dashboard_url = Config.DEPARTMENT_DASHBOARDS.get(user.department, '/')
        return redirect(dashboard_url)
    
    # Clear any pending auth session
    if 'pending_auth' in session:
        session.pop('pending_auth', None)
    
    if request.method == 'POST':
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '')
        department = request.form.get('department', '')
        
        if not all([username, password, department]):
            flash('Please fill in all required fields', 'danger')
            track_login_attempt(username, department, 'missing_fields')
            return render_template('login.html', departments=list(Config.DEPARTMENT_GROUPS.keys()),
                                 username=username, department=department)
        
        try:
            # STEP 1: Authenticate LDAP credentials and department
            user_data = authenticate_ldap(username, password, department)
            
            # Store pending authentication data in session (temporary)
            session['pending_auth'] = {
                'username': user_data['username'],
                'full_name': user_data['full_name'],
                'email': user_data['email'],
                'department': department,
                'groups': user_data['groups'],
                'timestamp': user_data['timestamp']
            }
            
            # Track login attempt - LDAP succeeded
            track_login_attempt(username, department, 'ldap_success')
            
            # STEP 2: Redirect to TOTP verification page
            flash('Credentials verified. Please enter your authenticator code.', 'info')
            return redirect(url_for('main.totp_verify'))
            
        except AuthenticationError as e:
            # Track failed login attempt
            track_login_attempt(username, department, 'ldap_failed')
            flash(str(e), 'danger')
            return render_template('login.html', departments=list(Config.DEPARTMENT_GROUPS.keys()),
                                 username=username, department=department)
    
    return render_template('login.html', departments=list(Config.DEPARTMENT_GROUPS.keys()))

@main_bp.route('/employee/totp', methods=['GET', 'POST'])
def totp_verify():
    # Must have pending authentication
    if 'pending_auth' not in session:
        flash('Session expired. Please log in again.', 'warning')
        return redirect(url_for('main.employee_login'))
    
    pending = session['pending_auth']
    
    if request.method == 'POST':
        totp_code = request.form.get('totp_code', '').strip()
        
        if not totp_code:
            flash('Please enter your authenticator code', 'danger')
            return render_template('totp_verify.html', username=pending['username'])
        
        try:
            # Verify TOTP code
            verify_totp_code(pending['username'], totp_code)
            
            # TOTP verified! Create full user session
            user = User(
                username=pending['username'],
                full_name=pending['full_name'],
                email=pending['email'],
                department=pending['department'],
                groups=pending['groups']
            )
            
            session.pop('pending_auth', None)  # Clear pending auth
            session['user'] = user.to_dict()
            session.permanent = True
            
            # Track successful complete authentication
            track_successful_auth(pending['username'], pending['department'])
            track_login_attempt(pending['username'], pending['department'], 'complete_success')
            
            flash(f'Welcome, {user.full_name}!', 'success')
            dashboard_url = Config.DEPARTMENT_DASHBOARDS.get(pending['department'], '/')
            return redirect(dashboard_url)
            
        except AuthenticationError as e:
            # Track TOTP failure
            track_login_attempt(pending['username'], pending['department'], 'totp_failed')
            flash(str(e), 'danger')
            return render_template('totp_verify.html', username=pending['username'])
    
    return render_template('totp_verify.html', username=pending['username'])

@main_bp.route('/employee/enroll-totp')
def enroll_totp():
    """Show QR codes for TOTP enrollment"""
    import pyotp
    import qrcode
    from io import BytesIO
    import base64
    from totp_secrets import TOTP_SECRETS
    
    # Generate QR codes for all users
    qr_codes = {}
    for username, secret in TOTP_SECRETS.items():
        totp = pyotp.TOTP(secret)
        uri = totp.provisioning_uri(
            name=username,
            issuer_name='Henry Enterprise Portal'
        )
        
        # Generate QR code
        qr = qrcode.QRCode(version=1, box_size=10, border=5)
        qr.add_data(uri)
        qr.make(fit=True)
        img = qr.make_image(fill_color="black", back_color="white")
        
        # Convert to base64
        buffer = BytesIO()
        img.save(buffer, format='PNG')
        img_str = base64.b64encode(buffer.getvalue()).decode()
        
        qr_codes[username] = {
            'qr_code': img_str,
            'secret': secret
        }
    
    return render_template('enroll_totp.html', qr_codes=qr_codes)

@main_bp.route('/metrics')
def metrics():
    """
    Prometheus metrics endpoint
    Exposes application metrics for scraping by Prometheus
    
    Metrics exposed:
    - henry_portal_login_attempts_total: Total login attempts by status, department, username
    - henry_portal_ldap_auth_total: LDAP authentication attempts
    - henry_portal_totp_verification_total: TOTP verification attempts
    - henry_portal_unauthorized_access_total: Unauthorized department access attempts
    - henry_portal_invalid_credentials_total: Failed login attempts with invalid credentials
    - henry_portal_successful_auth_total: Successful complete authentications
    - henry_portal_logout_total: User logout events
    - henry_portal_ldap_response_seconds: LDAP response time histogram
    - henry_portal_totp_validation_seconds: TOTP validation time histogram
    - henry_portal_auth_duration_seconds: Complete authentication duration
    - henry_portal_active_sessions: Number of active user sessions
    - henry_portal_pending_totp_verifications: Pending TOTP verifications
    - henry_portal_app_info: Application information
    
    Access this endpoint at: http://localhost:5000/metrics
    Prometheus will scrape this endpoint every 15 seconds
    """
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

@main_bp.route('/logout')
def logout():
    if 'user' in session:
        user = User.from_dict(session['user'])
        log_logout(user.username)
        session.pop('user', None)
    session.pop('pending_auth', None)  # Clear any pending auth
    flash('You have been logged out successfully', 'info')
    return redirect(url_for('main.landing'))

@main_bp.route('/hr/dashboard')
@department_required('HR')
def hr_dashboard():
    user = User.from_dict(session['user'])
    return render_template('hr_dashboard.html', user=user)

@main_bp.route('/it/dashboard')
@department_required('IT Support')
def it_dashboard():
    user = User.from_dict(session['user'])
    return render_template('it_dashboard.html', user=user)

@main_bp.route('/sales/dashboard')
@department_required('Sales')
def sales_dashboard():
    user = User.from_dict(session['user'])
    return render_template('sales_dashboard.html', user=user)

@main_bp.route('/admin/dashboard')
@department_required('Admin')
def admin_dashboard():
    user = User.from_dict(session['user'])
    audit_logs = []
    try:
        with open(Config.LOG_FILE, 'r') as f:
            audit_logs = f.readlines()[-50:]
            audit_logs.reverse()
    except FileNotFoundError:
        audit_logs = []
    return render_template('admin_dashboard.html', user=user, audit_logs=audit_logs)
