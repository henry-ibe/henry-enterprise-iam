#!/usr/bin/env bash
# scripts/phase60/step-9-dashboards.sh
# Phase 60 - Step 9: Create all Streamlit dashboard applications (HR, IT, Sales, Admin)

set -euo pipefail

# -----------------------------
# Config & Paths
# -----------------------------
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
PHASE60_ROOT="${PHASE60_ROOT:-"$PROJECT_ROOT/phase60"}"
DASHBOARDS_DIR="${DASHBOARDS_DIR:-"$PHASE60_ROOT/dashboards"}"
ENV_FILE="${ENV_FILE:-"$PHASE60_ROOT/.env"}"

# -----------------------------
# Helpers
# -----------------------------
usage() {
  cat <<'USAGE'
Phase 60 - Step 9: Create Streamlit dashboards (HR, IT, Sales, Admin)

Usage:
  scripts/phase60/step-9-dashboards.sh

Env overrides (optional):
  PROJECT_ROOT=/path/to/repo
  PHASE60_ROOT=/path/to/repo/phase60
  DASHBOARDS_DIR=/path/to/repo/phase60/dashboards
  ENV_FILE=/path/to/repo/phase60/.env
USAGE
}

log()  { printf "%b\n" "[$(date +'%F %T')] $*"; }
fail() { printf "%b\n" "❌ $*" >&2; exit 1; }

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then usage; exit 0; fi

# Pretty banner
echo "=== Phase 60 • Step 9: Dashboard Applications (HR, IT, Sales, Admin) ==="
echo

# -----------------------------
# Preconditions (idempotent-friendly)
# -----------------------------
[[ -f "$ENV_FILE" ]] || fail "'.env' not found at: $ENV_FILE (run the earlier steps to create it)"
# shellcheck disable=SC1090
source "$ENV_FILE" || true

# Ensure base directories exist
mkdir -p "$DASHBOARDS_DIR"/{hr,it,sales,admin}

# -----------------------------
# Common files generator
# -----------------------------
create_common_files() {
  local dash_dir="$1"
  local dash_name="$2"

  # requirements.txt (idempotent overwrite)
  cat > "$dash_dir/requirements.txt" <<'EOF'
streamlit==1.29.0
pandas==2.1.4
plotly==5.18.0
EOF

  # Dockerfile (idempotent overwrite)
  cat > "$dash_dir/Dockerfile" <<'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install runtime deps needed for healthcheck
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

# Python deps
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# App
COPY app.py .

# Non-root
RUN useradd -m -u 1000 streamlit && chown -R streamlit:streamlit /app
USER streamlit

EXPOSE 8501

HEALTHCHECK CMD curl --fail http://localhost:8501/_stcore/health || exit 1

CMD ["streamlit", "run", "app.py", \
     "--server.port=8501", \
     "--server.address=0.0.0.0", \
     "--server.headless=true", \
     "--server.enableXsrfProtection=true", \
     "--server.enableCORS=false"]
EOF

  log "  ✅ Common files created for ${dash_name}"
}

# -----------------------------
# HR Dashboard
# -----------------------------
log "1) Creating HR dashboard…"
create_common_files "$DASHBOARDS_DIR/hr" "HR"

cat > "$DASHBOARDS_DIR/hr/app.py" <<'EOF'
import streamlit as st
import pandas as pd
from datetime import datetime, timedelta

# Security: Verify headers are present (assumes reverse proxy injects headers)
def verify_auth():
    try:
        # NOTE: In reverse-proxy deployments, headers can be accessed via st.context.headers
        email = st.context.headers.get('X-User-Email') if hasattr(st, "context") else None
        roles_raw = st.context.headers.get('X-User-Roles', '') if hasattr(st, "context") else ''
        roles = [r.strip() for r in roles_raw.split(',') if r.strip()]

        if not email:
            st.error("🚫 Authentication Error")
            st.stop()

        if 'hr' not in roles and 'admin' not in roles:
            st.error("🚫 Unauthorized - HR or Admin role required")
            st.stop()

        return email, roles
    except Exception as e:
        st.error(f"Authentication error: {str(e)}")
        st.stop()

st.set_page_config(page_title="HR Portal - Henry Enterprise", page_icon="👥", layout="wide", initial_sidebar_state="expanded")

email, roles = verify_auth()

st.title("👥 Human Resources Portal")
st.caption(f"Logged in as: {email}")

with st.sidebar:
    st.image("https://via.placeholder.com/150x50?text=Henry+Enterprise", width=150)
    st.divider()
    st.write("### Navigation")
    page = st.radio("", ["📊 Dashboard", "👥 Employees", "🏖️ Time Off", "📈 Reports"])
    st.divider()
    st.write(f"**User:** {email}")
    st.write(f"**Roles:** {', '.join(roles)}")
    st.divider()
    st.caption("HR Portal v1.0")

if page == "📊 Dashboard":
    col1, col2, col3, col4 = st.columns(4)
    col1.metric("Total Employees", "147", "+3")
    col2.metric("Open Positions", "8", "+2")
    col3.metric("Pending Leave", "12", "-4")
    col4.metric("New Hires (30d)", "6", "+6")
    st.divider()
    st.subheader("📋 Recent Activity")
    activities = pd.DataFrame({
        'Date': ['2025-10-10', '2025-10-09', '2025-10-08', '2025-10-07', '2025-10-06'],
        'Employee': ['John Smith', 'Sarah Johnson', 'Mike Wilson', 'Lisa Brown', 'Tom Davis'],
        'Action': ['PTO Request', 'New Hire Onboarding', 'Exit Interview', 'Performance Review', 'Benefits Enrollment'],
        'Status': ['Pending', 'In Progress', 'Completed', 'Scheduled', 'Completed']
    })
    st.dataframe(activities, use_container_width=True, hide_index=True)

elif page == "👥 Employees":
    st.subheader("Employee Directory")
    col1, col2, col3 = st.columns(3)
    with col1:
        st.multiselect("Department", ["IT", "Sales", "HR", "Finance", "Operations"])
    with col2:
        st.multiselect("Status", ["Active", "Inactive", "On Leave"])
    with col3:
        st.text_input("🔍 Search employees")
    employees = pd.DataFrame({
        'ID': range(1001, 1021),
        'Name': [f'Employee {i}' for i in range(1, 21)],
        'Department': ['IT', 'Sales', 'HR', 'Finance', 'Operations'] * 4,
        'Position': ['Engineer', 'Manager', 'Analyst', 'Director', 'Specialist'] * 4,
        'Start Date': [(datetime.now() - timedelta(days=365*i)).strftime('%Y-%m-%d') for i in range(20)],
        'Status': ['Active'] * 18 + ['On Leave'] * 2
    })
    st.dataframe(employees, use_container_width=True, hide_index=True, height=400)
    col1, col2 = st.columns(2)
    with col1:
        if st.button("➕ Add New Employee"):
            st.info("Employee creation form would open here")
    with col2:
        csv = employees.to_csv(index=False)
        st.download_button("📥 Export to CSV", csv, f"employees_{datetime.now().strftime('%Y%m%d')}.csv", "text/csv")

elif page == "🏖️ Time Off":
    st.subheader("Time Off Management")
    pending_requests = pd.DataFrame({
        'Employee': ['Alice Brown', 'Bob Chen', 'Carol Davis', 'Dave Evans', 'Eve Foster'],
        'Type': ['Vacation', 'Sick Leave', 'Personal', 'Vacation', 'Vacation'],
        'Start Date': ['2025-10-15', '2025-10-12', '2025-10-20', '2025-11-01', '2025-11-15'],
        'End Date': ['2025-10-19', '2025-10-12', '2025-10-22', '2025-11-05', '2025-11-22'],
        'Days': [5, 1, 3, 5, 8],
        'Status': ['Pending'] * 5
    })
    st.dataframe(pending_requests, use_container_width=True, hide_index=True)
    col1, col2, col3 = st.columns(3)
    with col1:
        if st.button("✅ Approve Selected"):
            st.success("Request approved!")
    with col2:
        if st.button("❌ Deny Selected"):
            st.error("Request denied!")
    with col3:
        if st.button("💬 Request Info"):
            st.info("Information requested from employee")

else:
    st.subheader("📈 HR Reports")
    tab1, tab2, tab3 = st.tabs(["Headcount", "Turnover", "Diversity"])
    with tab1:
        st.write("### Headcount by Department")
        chart_data = pd.DataFrame({
            'Department': ['IT', 'Sales', 'HR', 'Finance', 'Operations'],
            'Employees': [45, 32, 12, 18, 40]
        }).set_index('Department')
        st.bar_chart(chart_data)
    with tab2:
        st.write("### Turnover Rate (12 months)")
        c1, c2 = st.columns(2)
        c1.metric("Annual Turnover", "8.3%", "-2.1%")
        c2.metric("Voluntary Turnover", "6.1%", "-1.8%")
    with tab3:
        st.write("### Workforce Diversity Metrics")
        st.info("Diversity dashboard coming soon")

st.divider()
st.caption(f"Henry Enterprise LLC © 2025 | HR Portal | Session: {datetime.now().strftime('%Y-%m-%d %H:%M')}")
EOF

# -----------------------------
# IT Dashboard
# -----------------------------
log "2) Creating IT dashboard…"
create_common_files "$DASHBOARDS_DIR/it" "IT"

cat > "$DASHBOARDS_DIR/it/app.py" <<'EOF'
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
        if 'it_support' not in roles and 'admin' not in roles:
            st.error("🚫 Unauthorized - IT Support or Admin role required")
            st.stop()
        return email, roles
    except Exception:
        st.error("Authentication error")
        st.stop()

st.set_page_config(page_title="IT Support Portal", page_icon="💻", layout="wide")

email, roles = verify_auth()

st.title("💻 IT Support Portal")
st.caption(f"Logged in as: {email}")

with st.sidebar:
    st.image("https://via.placeholder.com/150x50?text=Henry+Enterprise", width=150)
    st.divider()
    st.write("### Navigation")
    page = st.radio("", ["📊 Dashboard", "🎫 Tickets", "🖥️ Systems", "🚨 Incidents"])
    st.divider()
    st.write(f"**User:** {email}")
    st.write(f"**Roles:** {', '.join(roles)}")

if page == "📊 Dashboard":
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Open Tickets", "23", "+5")
    c2.metric("Critical Issues", "2", "0")
    c3.metric("Avg Resolution", "2.4h", "-0.3h")
    c4.metric("System Uptime", "99.8%", "+0.1%")
    st.divider()
    st.subheader("🎫 Recent Tickets")
    tickets = pd.DataFrame({
        'ID': [f'TKT-10{n:02d}' for n in range(1,6)],
        'User': [f'user{i}@henry.local' for i in range(1,6)],
        'Issue': ['Password Reset', 'VPN Not Connecting', 'Printer Offline', 'Software Install', 'Email Issue'],
        'Priority': ['Low', 'High', 'Medium', 'Low', 'High'],
        'Status': ['In Progress', 'Open', 'In Progress', 'Resolved', 'Open'],
        'Created': ['2h ago', '30m ago', '1h ago', '4h ago', '15m ago']
    })
    st.dataframe(tickets, use_container_width=True, hide_index=True)

elif page == "🎫 Tickets":
    st.subheader("Ticket Management")
    col1, col2, col3 = st.columns(3)
    with col1:
        st.selectbox("Priority", ["All", "Critical", "High", "Medium", "Low"])
    with col2:
        st.selectbox("Status", ["All", "Open", "In Progress", "Resolved", "Closed"])
    with col3:
        st.text_input("🔍 Search tickets")
    all_tix = pd.DataFrame({
        'ID': [f'TKT-{1000+i}' for i in range(1, 21)],
        'User': [f'user{i}@henry.local' for i in range(1, 21)],
        'Subject': ['Password Reset', 'VPN Issue', 'Email Problem', 'Software Request'] * 5,
        'Priority': ['Low', 'High', 'Medium', 'Critical'] * 5,
        'Status': ['Open', 'In Progress', 'Resolved', 'Closed'] * 5,
        'Assigned To': ['IT Team'] * 20,
        'Created': [(datetime.now() - timedelta(hours=i)).strftime('%Y-%m-%d %H:%M') for i in range(1, 21)]
    })
    st.dataframe(all_tix, use_container_width=True, hide_index=True, height=400)

elif page == "🖥️ Systems":
    st.subheader("System Status")
    systems = pd.DataFrame({
        'System': ['Web Server 1', 'Web Server 2', 'DB Primary', 'DB Replica', 'File Server', 'Email Server'],
        'Status': ['🟢 Online', '🟢 Online', '🟢 Online', '🟢 Online', '🟡 Degraded', '🟢 Online'],
        'CPU': ['45%', '38%', '62%', '41%', '78%', '23%'],
        'Memory': ['6.2/16 GB', '5.8/16 GB', '28/32 GB', '24/32 GB', '14/16 GB', '4/8 GB'],
        'Uptime': ['45d 12h', '45d 12h', '120d 3h', '120d 3h', '89d 8h', '180d 2h']
    })
    st.dataframe(systems, use_container_width=True, hide_index=True)
    st.divider()
    col1, col2 = st.columns(2)
    with col1:
        st.subheader("⚠️ Recent Alerts")
        alerts = pd.DataFrame({
            'Time': ['10:45', '09:23', '08:15'],
            'System': ['File Server', 'Web Server 1', 'Database Primary'],
            'Message': ['Disk usage >75%', 'High response time', 'Connection spike detected']
        })
        st.dataframe(alerts, use_container_width=True, hide_index=True)
    with col2:
        st.subheader("📊 Performance Metrics")
        perf = pd.DataFrame({
            'Time': ['10:00', '10:15', '10:30', '10:45', '11:00', '11:15'],
            'CPU': [45, 52, 48, 55, 50, 47],
            'Memory': [60, 62, 65, 63, 68, 66]
        }).set_index('Time')
        st.line_chart(perf)

else:
    st.subheader("🚨 Incident Management")
    incidents = pd.DataFrame({
        'ID': ['INC-001', 'INC-002', 'INC-003'],
        'Title': ['Email Service Outage', 'VPN Gateway Failure', 'Database Slowdown'],
        'Severity': ['Critical', 'High', 'Medium'],
        'Status': ['Resolved', 'Investigating', 'Monitoring'],
        'Started': ['2025-10-09 14:23', '2025-10-10 08:45', '2025-10-10 11:15'],
        'Duration': ['2h 15m', '1h 30m', '45m']
    })
    st.dataframe(incidents, use_container_width=True, hide_index=True)
    if st.button("➕ Create New Incident"):
        st.info("Incident creation form would open here")

st.divider()
st.caption(f"Henry Enterprise LLC © 2025 | IT Support Portal | {datetime.now().strftime('%Y-%m-%d %H:%M')}")
EOF

# -----------------------------
# Sales Dashboard
# -----------------------------
log "3) Creating Sales dashboard…"
create_common_files "$DASHBOARDS_DIR/sales" "Sales"

cat > "$DASHBOARDS_DIR/sales/app.py" <<'EOF'
import streamlit as st
import pandas as pd
from datetime import datetime, timedelta
import random

def verify_auth():
    try:
        email = st.context.headers.get('X-User-Email') if hasattr(st, "context") else None
        roles_raw = st.context.headers.get('X-User-Roles', '') if hasattr(st, "context") else ''
        roles = [r.strip() for r in roles_raw.split(',') if r.strip()]

        if not email:
            st.error("🚫 Authentication Error")
            st.stop()
        if 'sales' not in roles and 'admin' not in roles:
            st.error("🚫 Unauthorized - Sales or Admin role required")
            st.stop()
        return email, roles
    except Exception:
        st.error("Authentication error")
        st.stop()

st.set_page_config(page_title="Sales Portal", page_icon="📈", layout="wide")

email, roles = verify_auth()

st.title("📈 Sales Portal")
st.caption(f"Logged in as: {email}")

with st.sidebar:
    st.image("https://via.placeholder.com/150x50?text=Henry+Enterprise", width=150)
    st.divider()
    st.write("### Navigation")
    page = st.radio("", ["📊 Dashboard", "👥 Leads", "💼 Opportunities", "📈 Reports"])
    st.divider()
    st.write(f"**User:** {email}")
    st.write(f"**Roles:** {', '.join(roles)}")

if page == "📊 Dashboard":
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Monthly Revenue", "$485K", "+12%")
    c2.metric("Active Leads", "67", "+8")
    c3.metric("Conversion Rate", "23%", "+3%")
    c4.metric("Avg Deal Size", "$15.2K", "+$1.2K")
    st.divider()
    col1, col2 = st.columns(2)
    with col1:
        st.subheader("📊 Monthly Sales Trend")
        sales = pd.DataFrame({'Month': ['May','Jun','Jul','Aug','Sep','Oct'],'Revenue':[380,420,455,430,468,485]}).set_index('Month')
        st.line_chart(sales)
    with col2:
        st.subheader("🎯 Pipeline by Stage")
        pipeline = pd.DataFrame({'Stage':['Prospecting','Qualification','Proposal','Negotiation','Closed'],'Count':[45,32,18,12,8]}).set_index('Stage')
        st.bar_chart(pipeline)
    st.divider()
    st.subheader("🔥 Hot Leads")
    hot = pd.DataFrame({
        'Company': ['Acme Corp','TechStart Inc','Global Solutions','Innovate LLC'],
        'Contact': ['John Smith','Sarah Johnson','Mike Chen','Lisa Brown'],
        'Value': ['$45K','$32K','$58K','$28K'],
        'Stage': ['Proposal','Negotiation','Qualification','Proposal'],
        'Last Contact': ['2 days ago','1 day ago','3 hours ago','1 day ago']
    })
    st.dataframe(hot, use_container_width=True, hide_index=True)

elif page == "👥 Leads":
    st.subheader("Lead Management")
    col1, col2, col3 = st.columns(3)
    with col1:  st.selectbox("Source", ["All","Website","Referral","Cold Call","Trade Show"])
    with col2:  st.selectbox("Status", ["All","New","Contacted","Qualified","Lost"])
    with col3:  st.text_input("🔍 Search leads")
    companies = ['Acme Corp','TechStart Inc','Global Solutions','Innovate LLC','NextGen Systems']
    sources = ['Website','Referral','Cold Call','Trade Show']
    statuses= ['New','Contacted','Qualified','Lost']
    leads = pd.DataFrame({
        'ID':[f'LEAD-{2000+i}' for i in range(1,21)],
        'Company':[random.choice(companies) for _ in range(20)],
        'Contact':[f'Contact {i}' for i in range(1,21)],
        'Email':[f'contact{i}@company.com' for i in range(1,21)],
        'Source':[random.choice(sources) for _ in range(20)],
        'Status':[random.choice(statuses) for _ in range(20)],
        'Value':[f'${random.randint(10,80)}K' for _ in range(20)],
        'Created':[(datetime.now()-timedelta(days=i)).strftime('%Y-%m-%d') for i in range(20)]
    })
    st.dataframe(leads, use_container_width=True, hide_index=True, height=400)
    col1, col2 = st.columns(2)
    with col1:
        if st.button("➕ Add New Lead"): st.info("Lead creation form")
    with col2:
        csv = leads.to_csv(index=False)
        st.download_button("📥 Export CSV", csv, f"leads_{datetime.now().strftime('%Y%m%d')}.csv", "text/csv")

elif page == "💼 Opportunities":
    st.subheader("Sales Opportunities")
    opp = pd.DataFrame({
        'ID':[f'OPP-{3000+i}' for i in range(1,11)],
        'Company':[random.choice(['Acme Corp','TechStart Inc','Global Solutions']) for _ in range(10)],
        'Title':['Enterprise License','Cloud Migration','Support Contract']*3+['Enterprise License'],
        'Value':[f'${random.randint(20,100)}K' for _ in range(10)],
        'Stage':[random.choice(['Prospecting','Qualification','Proposal','Negotiation']) for _ in range(10)],
        'Probability':[f'{random.randint(10,90)}%' for _ in range(10)],
        'Close Date':[(datetime.now()+timedelta(days=random.randint(10,90))).strftime('%Y-%m-%d') for _ in range(10)]
    })
    st.dataframe(opp, use_container_width=True, hide_index=True)

else:
    st.subheader("📊 Sales Reports")
    tab1, tab2 = st.tabs(["Performance", "Forecast"])
    with tab1:
        perf = pd.DataFrame({
            'Metric':['Calls Made','Emails Sent','Meetings Held','Deals Closed','Revenue Generated'],
            'This Month':[145,312,28,6,'$92K'],
            'Last Month':[132,289,24,5,'$78K']
        })
        st.dataframe(perf, use_container_width=True, hide_index=True)
    with tab2:
        forecast = pd.DataFrame({'Month':['Oct','Nov','Dec','Jan','Feb','Mar'],'Expected':[485,520,555,580,605,635]}).set_index('Month')
        st.line_chart(forecast)

st.divider()
st.caption(f"Henry Enterprise LLC © 2025 | Sales Portal | {datetime.now().strftime('%Y-%m-%d %H:%M')}")
EOF

# -----------------------------
# Admin Dashboard
# -----------------------------
log "4) Creating Admin dashboard…"
create_common_files "$DASHBOARDS_DIR/admin" "Admin"

cat > "$DASHBOARDS_DIR/admin/app.py" <<'EOF'
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
EOF

echo

# -----------------------------
# Summary + Syntax validation
# -----------------------------
log "Summary of created dashboards:"
echo "  • $DASHBOARDS_DIR/hr"
echo "  • $DASHBOARDS_DIR/it"
echo "  • $DASHBOARDS_DIR/sales"
echo "  • $DASHBOARDS_DIR/admin"
echo

log "🧪 Validating Python syntax…"
all_valid=true
for dash in hr it sales admin; do
  app_path="$DASHBOARDS_DIR/$dash/app.py"
  if python3 -m py_compile "$app_path" 2>/dev/null; then
    echo "  ✅ $dash/app.py - Valid syntax"
  else
    echo "  ❌ $dash/app.py - Syntax error"
    all_valid=false
  fi
done

echo
if $all_valid; then
  echo "✅ Step 9 Complete: All dashboard applications created and validated."
else
  echo "❌ Some dashboards have syntax errors (see above)."
  exit 1
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Dashboards created:"
echo "  1. HR Dashboard (port 8501)    -> $DASHBOARDS_DIR/hr"
echo "  2. IT Dashboard (port 8502)    -> $DASHBOARDS_DIR/it"
echo "  3. Sales Dashboard (port 8503) -> $DASHBOARDS_DIR/sales"
echo "  4. Admin Dashboard (port 8504) -> $DASHBOARDS_DIR/admin"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "Next: Step 10 — Create Docker Compose to orchestrate everything."

