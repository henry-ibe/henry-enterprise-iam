# Portal Router

Smart role-based routing application for Henry Enterprise Portal.

## Purpose

The portal router:
1. Receives authenticated requests from OAuth2-Proxy
2. Extracts user roles from HTTP headers
3. Routes users to appropriate dashboard based on role precedence
4. Proxies all requests/responses transparently

## Architecture

```
OAuth2-Proxy → Portal Router → Role-Specific Dashboard
              (validates headers)
              (determines role)
              (proxies request)
```

## Role Precedence

When a user has multiple roles, priority is:
1. **admin** - Full access (sees admin dashboard)
2. **hr** - HR dashboard
3. **it_support** - IT dashboard
4. **sales** - Sales dashboard

## Headers

### Input (from OAuth2-Proxy)
- `X-Auth-Request-Email`: User's email
- `X-Auth-Request-User`: Username
- `X-Auth-Request-Groups`: Comma-separated or JSON array of roles

### Output (to dashboards)
- `X-User-Email`: User's email
- `X-User-Roles`: All user roles (comma-separated)
- `X-Primary-Role`: The role used for routing

## Endpoints

- `GET /health`: Health check (always returns 200)
- `GET /ready`: Readiness check (tests dashboard connectivity)
- `GET /*`: All other requests are routed based on user role

## Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Run locally
python router.py

# Test
curl http://localhost:8500/health
```

## Building Docker Image

```bash
docker build -t portal-router:latest .
```

## Testing

```bash
# Test with mock headers
curl -H "X-Auth-Request-Email: test@example.com" \
     -H "X-Auth-Request-User: testuser" \
     -H "X-Auth-Request-Groups: hr" \
     http://localhost:8500/
```
