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
