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
