# 🔐 Project Sentinel — Henry Enterprise Cloud IAM & Zero-Trust Identity Platform

> A production-grade, cloud-native Identity and Access Management (IAM) system built on RHEL 9 EC2, implementing Zero Trust security, FreeIPA LDAP, Keycloak OIDC, MFA, role-based access control, and full observability — built as a senior DevOps/Security Engineering portfolio piece.

[![Shell](https://img.shields.io/badge/Automation-Bash%20Scripts-4EAA25?logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![Keycloak](https://img.shields.io/badge/IAM-Keycloak%20v25-4B6EAF?logo=keycloak)](https://www.keycloak.org/)
[![FreeIPA](https://img.shields.io/badge/LDAP-FreeIPA-CC0000?logo=redhat)](https://www.freeipa.org/)
[![AWS](https://img.shields.io/badge/Cloud-AWS%20EC2-FF9900?logo=amazonaws)](https://aws.amazon.com/)
[![RHEL](https://img.shields.io/badge/OS-RHEL%209-EE0000?logo=redhat)](https://www.redhat.com/)

---

## 📌 What Is This Project?

Project Sentinel simulates how a modern enterprise secures its internal systems — the kind of IAM infrastructure you'd find at a bank, hospital, or government agency. It implements **Zero Trust principles** from the ground up: every request is authenticated, every user is authorized by role, and every access event is logged and visualized.

The system serves a multi-department employee portal where HR, IT Support, Sales, and Admin users each get role-specific dashboards — and unauthorized users can't even see what they don't have access to.

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Employee / Browser                           │
└──────────────────────────┬──────────────────────────────────────┘
                           │ HTTPS
┌──────────────────────────▼──────────────────────────────────────┐
│                    Traefik Reverse Proxy                        │
│              (Routing + TLS termination)                        │
└──────┬────────────────────────────────────────┬─────────────────┘
       │                                        │
┌──────▼──────────┐                  ┌──────────▼──────────────┐
│  OAuth2-Proxy   │◄────────────────►│  Keycloak (OIDC/SSO)   │
│  (Auth Gateway) │                  │  + FreeIPA LDAP         │
└──────┬──────────┘                  │  + TOTP MFA             │
       │                             └─────────────────────────┘
┌──────▼──────────────────────────────────────────────────────┐
│                    Portal Router                             │
│           (Smart role-based routing)                        │
└──────┬──────────┬──────────────┬──────────────┬────────────┘
       │          │              │              │
  ┌────▼───┐ ┌───▼────┐ ┌──────▼──┐ ┌────────▼──┐
  │   HR   │ │   IT   │ │  Sales  │ │   Admin   │
  │Portal  │ │Portal  │ │  Portal │ │  Portal   │
  └────────┘ └────────┘ └─────────┘ └───────────┘
       │
┌──────▼──────────────────────────────────────────────────────┐
│              Prometheus + Grafana + CloudWatch               │
│         (Auth events, login metrics, audit logs)            │
└─────────────────────────────────────────────────────────────┘
```

**Infrastructure:** RHEL 9 EC2 (AWS) · SELinux enforced · Podman containers · systemd services

---

## 🚀 Deployment Phases

### Phase 1 — System Prerequisites (`scripts/00-prereqs-check.sh`)
Validates the EC2 instance before any automation runs:
- OS verification (RHEL 9)
- sudo privileges check
- Network connectivity
- chronyd time sync (critical for Kerberos)
- SELinux status
- DNS resolution

### Phase 2 — FreeIPA Bootstrap (`scripts/20-freeipa.sh`)
Deploys centralized LDAP/Kerberos identity backend:
- Auto-installs FreeIPA in integrated mode
- Initializes domain: `henry-iam.internal`
- Creates department groups: `hr`, `it_support`, `sales`, `admins`
- Creates demo users with auto-generated secure passwords
- Web UI accessible at `https://ipa1.henry-iam.internal`

### Phase 3 — Keycloak Setup (`scripts/30-keycloak.sh`)
Deploys containerized Keycloak connected to FreeIPA:
- Keycloak v25 via Podman
- LDAP federation to FreeIPA
- TOTP MFA (Google Authenticator compatible)
- Realm: `henry-enterprise`
- OIDC client: `employee-portal`

### Phase 4 — Realm & Role Configuration (`scripts/40-keycloak-init.sh`)
Automates Keycloak setup via `kcadm.sh` CLI:
- Creates realm: `henry-enterprise`
- Defines roles: `HR`, `IT Support`, `Sales`, `Admin`
- Configures OIDC clients with secure redirect URIs
- Maps roles to JWT claims
- Sets token lifespans and session policies

### Phase 5 — Employee Portal (`scripts/50-portal-deploy.sh`)
Deploys the Flask-based employee portal:
- Apache reverse proxy + systemd service
- Role-based route enforcement
- Direct LDAP authentication (Phase 5a)
- OIDC authentication via Keycloak (Phase 5b)
- All access attempts logged to `/var/log/henry-portal/access.log`

### Phase 6 — Full OIDC Stack (`phase60/`)
Production-grade deployment with full service mesh:

| Service | Purpose |
|---|---|
| Traefik | Reverse proxy and load balancer |
| Keycloak | OIDC identity provider |
| OAuth2-Proxy | Authentication gateway |
| Redis | Session storage |
| Portal Router | Smart role-based routing |
| HR Dashboard | HR management portal |
| IT Dashboard | IT support and ticketing |
| Sales Dashboard | Sales CRM portal |
| Admin Dashboard | Full system access |
| Public Site | Unauthenticated landing page |
| Prometheus | Metrics collection |

**Role → Dashboard mapping:**

| Role | Portal | Access Level |
|---|---|---|
| `hr` | HR Dashboard | Employee data, leave management |
| `it_support` | IT Dashboard | Tickets, logs, system status |
| `sales` | Sales Dashboard | Leads, pipeline, CRM |
| `admins` | Admin Dashboard | Full access, user management |

### Phase 7 — Observability (`phase70-monitoring/`)
Full monitoring stack:
- Prometheus metrics collection
- Grafana dashboards
- AWS CloudWatch integration
- Metrics tracked: failed logins, invalid TOTP, unauthorized access, login latency, auth success by department

---

## 🛡️ Security Controls

| Control | Implementation |
|---|---|
| Zero Trust | Every request authenticated — no implicit trust |
| Least Privilege | Role-based route enforcement, no cross-role access |
| MFA | TOTP via Keycloak (Google Authenticator) |
| Centralized Identity | FreeIPA LDAP/Kerberos + Keycloak OIDC federation |
| Audit Logging | All auth events → CloudWatch + Prometheus + Grafana |
| Defense in Depth | Traefik → OAuth2-Proxy → Portal Router → Dashboard |
| Host Security | SELinux enforced, chronyd time sync, systemd isolation |
| Secret Management | Environment-based config, no hardcoded credentials |

---

## 🛠️ Tech Stack

| Category | Technology |
|---|---|
| Identity Provider | FreeIPA (LDAP + Kerberos) |
| SSO / OIDC | Keycloak v25 |
| Auth Gateway | OAuth2-Proxy |
| Reverse Proxy | Traefik |
| Session Storage | Redis |
| Portal | Python Flask + Apache httpd |
| Containers | Podman / Docker |
| Monitoring | Prometheus + Grafana + AWS CloudWatch |
| OS | RHEL 9 (SELinux enforced) |
| Cloud | AWS EC2 |
| Automation | Bash (fully idempotent scripts) |

---

## ⚡ Quick Start

```bash
# Clone the repo
git clone https://github.com/henry-ibe/henry-enterprise-iam.git
cd henry-enterprise-iam

# Set up environment
cp .env.example .env
# Edit .env with your values

# Deploy all phases in sequence
chmod +x master-deploy.sh
./master-deploy.sh

# Or deploy Phase 6 (full OIDC stack) standalone
cd phase60
./start.sh
./status.sh
```

**Prerequisites:** RHEL 9 EC2, sudo access, outbound internet, chronyd running

---

## 📁 Repository Structure

```
henry-enterprise-iam/
├── scripts/
│   ├── 00-prereqs-check.sh    # Pre-flight validation
│   ├── 20-freeipa.sh          # FreeIPA LDAP bootstrap
│   ├── 30-keycloak.sh         # Keycloak deployment
│   ├── 40-keycloak-init.sh    # Realm/role/client setup
│   ├── 50-portal-deploy.sh    # Employee portal
│   ├── 50-nginx-proxy.sh      # Nginx reverse proxy
│   └── 70-monitoring-deploy.sh # Observability stack
├── phase50-portal/            # Flask portal application
├── phase60/                   # Full OIDC stack (Docker Compose)
│   ├── traefik/               # Reverse proxy config
│   ├── keycloak/              # Realm configuration
│   ├── oauth2-proxy/          # Auth gateway config
│   ├── portal-router/         # Role-based routing app
│   ├── dashboards/            # HR/IT/Sales/Admin portals
│   ├── public-site/           # Unauthenticated landing page
│   ├── docker-compose.yml
│   ├── start.sh / stop.sh / status.sh
│   └── README.md
├── phase70-monitoring/        # Prometheus + Grafana setup
├── logs/                      # Deployment logs
├── master-deploy.sh           # One-command full deployment
├── deploy-all.sh              # Alternative deploy script
├── .env.example               # Environment template
└── Project Sentinel*.pdf      # Full architecture whitepaper
```

---

## 💡 What This Demonstrates

| Skill | How It's Demonstrated |
|---|---|
| Enterprise IAM | FreeIPA + Keycloak federation with LDAP/Kerberos |
| Zero Trust Architecture | Multi-layer auth: Traefik → OAuth2-Proxy → Portal Router |
| OIDC / SSO | Full OIDC flow with JWT role claims and session management |
| MFA Implementation | TOTP via Keycloak, Google Authenticator compatible |
| Infrastructure Automation | 7 fully idempotent bash scripts, one-command deployment |
| Observability | Auth event metrics, login dashboards, CloudWatch integration |
| Container Orchestration | 12-service Docker Compose stack with Podman |
| Linux Security | SELinux enforcement, systemd services, RHEL 9 hardening |
| Secret Management | Environment-based config with no hardcoded credentials |

---

## 📄 Architecture Whitepaper

Full design documentation available in `Project Sentinel_ Henry Enterprise Cloud IAM & Zero-Trust Identity Platform.pdf` — covers threat model, design decisions, and phase-by-phase implementation details.

---

## 👤 Author

**Henry Ibe** — Systems & Cloud Infrastructure Engineer
[![GitHub](https://img.shields.io/badge/GitHub-henry--ibe-181717?logo=github)](https://github.com/henry-ibe)

---

*This is a portfolio/lab project. Demo users and test credentials are for development only. Never use demo passwords in production.*
