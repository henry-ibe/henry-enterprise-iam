import os
from datetime import timedelta

class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'henry-enterprise-secret-key-change-in-production'
    SESSION_TYPE = 'filesystem'
    SESSION_PERMANENT = True
    PERMANENT_SESSION_LIFETIME = timedelta(hours=8)
    SESSION_FILE_DIR = '/tmp/flask_sessions'
    
    LDAP_HOST = 'ldap://localhost:389'
    LDAP_BASE_DN = 'dc=henry-iam,dc=internal'
    LDAP_USER_BASE = 'cn=users,cn=accounts,dc=henry-iam,dc=internal'
    LDAP_GROUP_BASE = 'cn=groups,cn=accounts,dc=henry-iam,dc=internal'
    
    DEPARTMENT_GROUPS = {
        'HR': 'hr',
        'IT Support': 'it_support',
        'Sales': 'sales',
        'Admin': 'admins'
    }
    
    DEPARTMENT_DASHBOARDS = {
        'HR': '/hr/dashboard',
        'IT Support': '/it/dashboard',
        'Sales': '/sales/dashboard',
        'Admin': '/admin/dashboard'
    }
    
    LOG_FILE = 'logs/access.log'
    DEBUG = True
    TESTING = False
