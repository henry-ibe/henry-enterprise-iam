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
