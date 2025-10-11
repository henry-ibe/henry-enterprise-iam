# Phase 60: OIDC-Protected Employee Portal

Production-grade employee portal with role-based access control using Keycloak OIDC authentication.

## Architecture

```
Browser → Traefik → OAuth2-Proxy → Portal Router → Role-Based Dashboard
                         ↓
                    Keycloak (OIDC)
```

## Quick Start

```bash
# Start all services
./start.sh

# Check status
./status.sh

# View logs
docker-compose logs -f [service-name]

# Stop all services
./stop.sh
```

## Access Points

- **Public Site**: http://henry-enterprise.local
- **Employee Portal**: http://portal.henry-enterprise.local
- **Keycloak Admin**: http://henry-enterprise.local:8080/auth/admin
  - Username: `admin`
  - Password: `SecureAdmin123!`
- **Traefik Dashboard**: http://traefik.henry-enterprise.local:8080
- **Prometheus**: http://localhost:9090

## Test Users

| Username | Password | Role | Dashboard |
|----------|----------|------|-----------|
| alice.hr | HRPass123! | hr | HR Portal |
| bob.it | ITPass123! | it_support | IT Portal |
| carol.sales | SalesPass123! | sales | Sales Portal |
| admin | AdminPass123! | admin | Admin Portal (all access) |

## Services

1. **traefik** - Reverse proxy and load balancer
2. **keycloak** - Identity provider (OIDC)
3. **keycloak-db** - PostgreSQL for Keycloak
4. **oauth2-proxy** - Authentication gateway
5. **redis** - Session storage
6. **portal-router** - Smart role-based routing
7. **hr-dashboard** - HR management portal
8. **it-dashboard** - IT support portal
9. **sales-dashboard** - Sales CRM portal
10. **admin-dashboard** - System administration
11. **public-site** - Public landing page
12. **prometheus** - Metrics collection

## Troubleshooting

### Check logs for a specific service
```bash
docker-compose logs -f keycloak
docker-compose logs -f oauth2-proxy
docker-compose logs -f portal-router
```

### Restart a service
```bash
docker-compose restart [service-name]
```

### Rebuild a service
```bash
docker-compose build [service-name]
docker-compose up -d [service-name]
```

### Access container shell
```bash
docker-compose exec [service-name] sh
```

## Directory Structure

```
phase60/
├── docker-compose.yml     # Main orchestration file
├── .env                   # Environment variables (DO NOT COMMIT)
├── start.sh              # Startup script
├── stop.sh               # Shutdown script
├── status.sh             # Status check script
├── traefik/              # Traefik configuration
├── keycloak/             # Keycloak realm configuration
├── oauth2-proxy/         # OAuth2-Proxy configuration
├── portal-router/        # Smart routing application
├── dashboards/           # Role-based dashboards
│   ├── hr/
│   ├── it/
│   ├── sales/
│   └── admin/
├── public-site/          # Public landing page
└── monitoring/           # Prometheus configuration
```

## Security Notes

- The `.env` file contains sensitive secrets - never commit to git
- Test users have simple passwords for development only
- In production, enforce strong password policies in Keycloak
- Enable MFA for admin users
- Use proper TLS certificates (not self-signed)

## Next Steps

1. Configure proper TLS certificates
2. Set up external database for production
3. Enable MFA in Keycloak
4. Configure backup strategy
5. Set up monitoring alerts
6. Implement log aggregation

## Documentation

- [Keycloak Docs](https://www.keycloak.org/documentation)
- [OAuth2-Proxy Docs](https://oauth2-proxy.github.io/oauth2-proxy/)
- [Traefik Docs](https://doc.traefik.io/traefik/)
- [Streamlit Docs](https://docs.streamlit.io/)
