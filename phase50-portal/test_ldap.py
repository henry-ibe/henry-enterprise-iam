#!/usr/bin/env python3
"""
Quick LDAP connection test
"""
from ldap3 import Server, Connection, ALL

# Test LDAP connection
server = Server('ldap://localhost:389', get_info=ALL)
print("✓ LDAP server object created")

# Try to connect
try:
    conn = Connection(server, 
                     user='uid=sarah,cn=users,cn=accounts,dc=henry-iam,dc=internal',
                     password='password123',
                     auto_bind=True)
    print("✓ Successfully authenticated as sarah")
    
    # Search for user
    conn.search('cn=users,cn=accounts,dc=henry-iam,dc=internal',
               '(uid=sarah)',
               attributes=['uid', 'cn', 'mail', 'memberOf'])
    
    if conn.entries:
        print("✓ Found user sarah in LDAP")
        print(f"  Full name: {conn.entries[0].cn}")
        print(f"  Email: {conn.entries[0].mail if hasattr(conn.entries[0], 'mail') else 'N/A'}")
        if hasattr(conn.entries[0], 'memberOf'):
            print(f"  Groups: {len(conn.entries[0].memberOf)} groups")
    
    conn.unbind()
    print("\n✅ LDAP connection test PASSED!")
    
except Exception as e:
    print(f"\n❌ LDAP connection test FAILED: {e}")
