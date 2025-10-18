Project Sentinel: Henry Enterprise Cloud IAM & Zero-Trust Identity Platform
Overview

Project Sentinel is a production-grade, cloud-ready Identity and Access Management (IAM) framework developed by Henry Enterprise LLC.
It simulates how a modern enterprise implements centralized identity, Zero Trust principles, multi-factor authentication (MFA), and role-based access control (RBAC) across multiple departments in a secure and auditable environment.

The project is deployed step-by-step on a Red Hat Enterprise Linux 9 (RHEL 9) EC2 instance using the AWS Free Tier.
Each phase is automated using modular shell scripts that can be reused, extended, or integrated into enterprise pipelines.

The target use case is an internal employee portal serving multiple departments—HR, IT Support, Sales, and Admin—each with its own secure dashboard. Unauthorized users cannot access or even view protected routes.
Every authentication event, successful or failed, is logged and visualized through AWS CloudWatch, Prometheus, and Grafana.

Vision

Secure. Auditable. Role-Based. Cloud-Ready.

Project Sentinel was designed to demonstrate enterprise IAM concepts in a real-world, reproducible environment.
The focus is on:

Zero Trust security model

LDAP-backed user management

OIDC-based Single Sign-On (SSO)

Multi-Factor Authentication (TOTP/Google Authenticator)

Centralized access logging and monitoring

Core Technologies
Component	Purpose	Key Features
FreeIPA	LDAP + Kerberos backend	Centralized directory and group management
Keycloak	OIDC Identity Provider	LDAP federation, MFA (TOTP), realm-based roles
Flask + Apache (httpd)	Employee portal and reverse proxy	Role-based access control, secure web routing
Podman / Docker	Container runtime	Isolated Keycloak and service environments
Prometheus + Grafana	Monitoring stack	Real-time metrics, dashboards, and audit visualization
AWS CloudWatch	Centralized logging	Authentication events and system metrics
RHEL 9 EC2	Secure host	SELinux enforcement, chronyd time sync, systemd services
Phase 1 — System Prerequisite Check

Script: scripts/00-prereqs-check.sh

Ensures the EC2 instance meets all requirements before any automation is executed.
The script verifies:

Operating system (RHEL 9)

User privileges (ec2-user with sudo)

Availability of essential tools (sudo, curl, ping)

Outbound network connectivity

Hostname configuration

Time synchronization via chronyd (critical for Kerberos)

SELinux status

DNS resolution

Outcome:
System ready for IAM bootstrap, all pre-checks passed.

Phase 2 — FreeIPA Bootstrap (With Auto Password Generation)

Script: scripts/20-freeipa.sh

Deploys and configures FreeIPA as the central LDAP/Kerberos identity backend.

Tasks

Auto-install FreeIPA in integrated mode

Initialize domain: henry-iam.internal

Create groups: hr, it_support, sales, admins

Create demo users with random secure passwords

Save credentials to /etc/henry-portal/freeipa-users.txt

Outcome:
FreeIPA web interface accessible at https://ipa1.henry-iam.internal, all users and groups visible.

Phase 3 — Keycloak Setup (OIDC + LDAP + TOTP)

Script: scripts/30-keycloak.sh

Deploys a containerized Keycloak instance connected to FreeIPA through LDAP federation and enables TOTP-based MFA.

Tasks

Pull Keycloak image (v23+) using Podman

Generate admin credentials automatically

Configure LDAP bind to FreeIPA

Enable TOTP authentication (Google Authenticator compatible)

Create realm: security-project-1

Create OIDC client: employee-portal

Outcome:
Keycloak admin console available at http://<host>:8180/.
LDAP users can now authenticate via MFA.

Phase 4 — Automated Realm, Roles, and Clients Setup

Script: scripts/40-keycloak-init.sh

Automates Keycloak configuration using kcadm.sh CLI tools.

Tasks

Create realm: henry-enterprise

Define roles: HR, IT Support, Sales, Admin

Create OIDC clients: employee-portal, hr-portal

Configure:

Token lifespans and session settings

Secure redirect URIs

Role mappings to JWT claims

CORS and WebAuthn configuration

Outcome:
Keycloak realm and clients are provisioned automatically with mapped roles ready for OIDC-based authentication.

Phase 5 — Direct LDAP Authentication Portal (Apache + Flask)

Script: scripts/50-portal.sh

Implements the first version of the employee login portal using direct LDAP authentication through FreeIPA.

Tasks

Deploy Flask web application under /employee/

Configure Apache reverse proxy and systemd service

Create role-based views for:

/hr

/it

/sales

/admin

Log all access attempts to /var/log/henry-portal/access.log

Outcome:
Local LDAP authentication working for all user groups. Logs available for auditing.

Phase 6 — OIDC-Protected Employee Portal (/portal)

Script: scripts/60-portal-oidc.sh

Integrates the employee portal with Keycloak OIDC authentication and role-based routing.

Behavior

User visits the company landing page.

Clicking “Employee Portal” redirects them to Keycloak for login.

Upon authentication and MFA verification, users are routed to their specific dashboard based on role mapping.

Realm Role	Portal View
hr	HR Dashboard (Employee data)
it_support	IT Dashboard (Tickets, logs)
sales	Sales Dashboard (Leads, CRM)
admins	Admin Dashboard (User management, full access)

Outcome:
Each user experiences a distinct, role-based portal with MFA-protected access. Unauthorized access attempts are blocked and logged.

Phase 7 — Observability and Audit Visualization

Script: scripts/70-monitoring.sh

Adds full observability using Prometheus and Grafana, with optional integration into AWS CloudWatch.

Metrics Tracked

Failed login attempts

Invalid TOTP codes

Unauthorized role access

Login latency

Successful authentication count

Login activity by department

Outcome:
Real-time dashboards display authentication trends, performance metrics, and security analytics.

Core Security Principles Demonstrated
Control	Implementation
Zero Trust	Every request authenticated; no implicit trust.
Least Privilege	Role-based route enforcement for all users.
Multi-Factor Authentication	TOTP integration via Keycloak.
Auditable Access	Logs ingested into CloudWatch, Prometheus, and Grafana.
Centralized Identity	FreeIPA (LDAP/Kerberos) integrated with Keycloak (OIDC).
Defense in Depth	Apache reverse proxy, SELinux enforcement, SSL/TLS readiness.
Outcome Summary

Project Sentinel demonstrates the end-to-end lifecycle of a secure, cloud-native IAM system.
It delivers:

Centralized identity management

MFA-enabled OIDC authentication

Department-based role routing

Full audit and monitoring visibility

Cloud-ready automation with reusable scripts

Author

Henry Ibe
Founder, Henry Enterprise LLC
Cloud & Infrastructure Security Engineer
