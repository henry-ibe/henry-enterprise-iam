import streamlit as st
import pandas as pd
from datetime import datetime, timedelta

def verify_auth():
    try:
        email = st.context.headers.get('X-User-Email') if hasattr(st, "context") else None
        roles_raw = st.context.headers.get('X-User-Roles', '') if hasattr(st, "context") else ''
        roles = [r.strip() for r in roles_raw.split(',') if r.strip()]

        if not email:
            st.error("🚫 Authentication Error")
            st.stop()
        if 'admin' not in roles:
            st.error("🚫 Unauthorized - Admin role required")
            st.stop()
        return email, roles
    except Exception:
        st.error("Authentication error")
        st.stop()

st.set_page_config(page_title="Admin Portal", page_icon="⚙️", layout="wide")

email, roles = verify_auth()

st.title("⚙️ Administrator Portal")
st.caption(f"Logged in as: {email} | Full System Access")

with st.sidebar:
    st.image("https://via.placeholder.com/150x50?text=Henry+Enterprise", width=150)
    st.divider()
    st.write("### Navigation")
    page = st.radio("", ["📊 Dashboard", "👥 Users", "🎭 Roles", "📋 Audit Log", "⚙️ System"])
    st.divider()
    st.write(f"**User:** {email}")
    st.write(f"**All Roles:** {', '.join(roles)}")
    st.divider()
    st.write("### Quick Links")
    if st.button("🔗 HR Portal"): st.info("Would navigate to HR Portal")
    if st.button("🔗 IT Portal"): st.info("Would navigate to IT Portal")
    if st.button("🔗 Sales Portal"): st.info("Would navigate to Sales Portal")

if page == "📊 Dashboard":
    st.subheader("System Overview")
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Total Users", "147", "+3")
    c2.metric("Active Sessions", "42", "+5")
    c3.metric("System Uptime", "99.98%", "0")
    c4.metric("Failed Logins (24h)", "3", "-2")
    st.divider()
    col1, col2 = st.columns(2)
    with col1:
        st.subheader("👥 Users by Role")
        role_dist = pd.DataFrame({'Role':['Sales','IT Support','HR','Admin','Other'],'Count':[45,32,12,8,50]}).set_index('Role')
        st.bar_chart(role_dist)
    with col2:
        st.subheader("📊 Login Activity (7 days)")
        days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun']
        activity = pd.DataFrame({'Day':days,'Logins':[145,152,148,156,143,45,38]}).set_index('Day')
        st.line_chart(activity)
    st.divider()
    st.subheader("⚠️ Recent Admin Actions")
    actions = pd.DataFrame({
        'Timestamp': [(datetime.now() - timedelta(hours=i)).strftime('%Y-%m-%d %H:%M') for i in range(5)],
        'Admin': [email]*5,
        'Action': ['User Created','Role Modified','Password Reset','User Disabled','Role Assigned'],
        'Target': ['john.doe','jane.smith','bob.jones','old.user','new.hire'],
        'Status': ['✅ Success']*5
    })
    st.dataframe(actions, use_container_width=True, hide_index=True)

elif page == "👥 Users":
    st.subheader("User Management")
    col1, col2, col3 = st.columns(3)
    with col1: st.multiselect("Filter by Role", ["admin","hr","it_support","sales"])
    with col2: st.selectbox("Status", ["All","Active","Inactive","Locked"])
    with col3: st.text_input("🔍 Search users")

    # Example list
    base_users = [
        ('alice.hr','alice@henry-enterprise.local','Alice Henderson','hr','Active'),
        ('bob.it','bob@henry-enterprise.local','Bob Technical','it_support','Active'),
        ('carol.sales','carol@henry-enterprise.local','Carol Seller','sales','Active'),
        ('admin','admin@henry-enterprise.local','System Admin','admin,hr,it_support,sales','Active'),
    ]
    # Add more synthetic users
    for i in range(5,16):
        role = ('sales' if i<=9 else ('it_support' if i<=12 else 'hr'))
        base_users.append((f'user{i}', f'user{i}@henry-enterprise.local', f'User {i}', role, 'Active' if i<14 else 'Inactive'))

    users = pd.DataFrame(base_users, columns=['Username','Email','Name','Roles','Status'])
    users['Last Login'] = [(datetime.now() - timedelta(hours=i)).strftime('%Y-%m-%d %H:%M') for i in range(len(users))]
    st.dataframe(users, use_container_width=True, hide_index=True, height=400)

    c1,c2,c3,c4 = st.columns(4)
    with c1:
        if st.button("➕ Create User"): st.info("User creation dialog")
    with c2:
        if st.button("✏️ Edit Selected"): st.info("Edit user dialog")
    with c3:
        if st.button("🔒 Lock/Unlock"): st.warning("User lock status changed")
    with c4:
        if st.button("🗑️ Delete Selected"): st.error("User deletion requires confirmation")

elif page == "🎭 Roles":
    st.subheader("Role Management")
    roles_df = pd.DataFrame({
        'Role':['admin','hr','it_support','sales'],
        'Description':['Full system access','Human resources management','IT support and system management','Sales and CRM access'],
        'Users':[8,12,32,45],
        'Permissions':['All','HR Portal, User View','IT Portal, System View, Ticket Management','Sales Portal, Lead Management']
    })
    st.dataframe(roles_df, use_container_width=True, hide_index=True)
    st.divider()
    st.subheader("🔐 Role Permissions Matrix")
    permissions = pd.DataFrame({
        'Resource':['User Management','HR Data','IT Systems','Sales Data','Audit Logs','System Config'],
        'admin':['✅','✅','✅','✅','✅','✅'],
        'hr':['❌','✅','❌','❌','❌','❌'],
        'it_support':['❌','❌','✅','❌','📖','📖'],
        'sales':['❌','❌','❌','✅','❌','❌']
    })
    st.dataframe(permissions, use_container_width=True, hide_index=True)
    st.caption("✅ Full Access | 📖 Read Only | ❌ No Access")
    if st.button("➕ Create New Role"): st.info("Role creation form")

elif page == "📋 Audit Log":
    st.subheader("Audit Log")
    c1,c2,c3 = st.columns(3)
    with c1: st.date_input("From Date", datetime.now() - timedelta(days=7))
    with c2: st.multiselect("Action Type", ["Login","Logout","User Created","Role Changed","Password Reset"])
    with c3: st.text_input("🔍 Search user")

    audit_entries = []
    for i in range(50):
        ts = datetime.now() - timedelta(hours=i, minutes=i*3)
        audit_entries.append({
            'Timestamp': ts.strftime('%Y-%m-%d %H:%M:%S'),
            'User': f'user{(i % 20) + 1}',
            'Action': ['Login','Logout','View Portal','Update Profile'][i % 4],
            'Resource': ['/portal/hr','/portal/it','/portal/sales','/portal/admin'][i % 4],
            'IP Address': f'192.168.1.{(i % 254) + 1}',
            'Status': 'Success' if i % 10 != 0 else 'Failed'
        })
    audit_df = pd.DataFrame(audit_entries)
    st.dataframe(audit_df, use_container_width=True, hide_index=True, height=400)
    csv = audit_df.to_csv(index=False)
    st.download_button("📥 Export Audit Log", csv, f"audit_log_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv", "text/csv")

else:
    st.subheader("⚙️ System Configuration")
    tab1, tab2, tab3 = st.tabs(["General","Security","Authentication"])
    with tab1:
        st.write("### General Settings")
        c1,c2 = st.columns(2)
        with c1:
            st.text_input("System Name", "Henry Enterprise Portal")
            st.text_input("Support Email", "support@henry-enterprise.local")
        with c2:
            st.selectbox("Timezone", ["America/New_York","America/Chicago","America/Denver","America/Los_Angeles"])
            st.selectbox("Date Format", ["YYYY-MM-DD","MM/DD/YYYY","DD/MM/YYYY"])
        if st.button("💾 Save General Settings"): st.success("Settings saved successfully")
    with tab2:
        st.write("### Security Settings")
        c1,c2 = st.columns(2)
        with c1:
            st.number_input("Session Timeout (minutes)", value=30, min_value=5, max_value=240)
            st.number_input("Max Failed Login Attempts", value=5, min_value=3, max_value=10)
            st.checkbox("Require MFA for Admins", value=True)
        with c2:
            st.number_input("Password Min Length", value=12, min_value=8, max_value=32)
            st.checkbox("Require Special Characters", value=True)
            st.checkbox("Require Number", value=True)
        if st.button("💾 Save Security Settings"): st.success("Security settings saved")
    with tab3:
        st.write("### Authentication Configuration")
        st.text_input("Keycloak Realm", "henry-enterprise", disabled=True)
        st.text_input("Client ID", "employee-portal", disabled=True)
        st.text_input("OIDC Issuer URL", "http://keycloak:8080/realms/henry-enterprise", disabled=True)
        st.divider()
        c1,c2 = st.columns(2)
        with c1:
            if st.button("🔄 Test Connection"): st.success("✅ Connection successful")
        with c2:
            if st.button("🔑 Rotate Client Secret"): st.warning("⚠️ This will invalidate all active sessions")

st.divider()
st.caption(f"Henry Enterprise LLC © 2025 | Admin Portal | {datetime.now().strftime('%Y-%m-%d %H:%M')}")
