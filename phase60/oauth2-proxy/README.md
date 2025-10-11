# OAuth2-Proxy Configuration

This directory contains the OAuth2-Proxy configuration for Phase 60.

## Configuration File

- **oauth2-proxy.cfg**: Main configuration file

## Key Settings

- **Provider**: Keycloak OIDC
- **Session Storage**: Redis (persistent sessions)
- **Cookie Lifetime**: 24 hours
- **Cookie Refresh**: 1 hour

## Environment Variables Used

The following variables from `.env` are used:
- `OAUTH2_PROXY_CLIENT_ID`
- `OAUTH2_PROXY_CLIENT_SECRET`
- `OAUTH2_PROXY_COOKIE_SECRET`
- `PORTAL_DOMAIN`
- `KEYCLOAK_REALM`

## Headers Forwarded to Applications

OAuth2-Proxy forwards these headers to upstream applications:
- `X-Auth-Request-Email`: User's email address
- `X-Auth-Request-User`: Username
- `X-Auth-Request-Groups`: User's groups/roles (comma-separated)
- `X-Auth-Request-Preferred-Username`: Preferred username

## Testing

After deployment, test authentication:
1. Access: https://portal.henry-enterprise.local
2. You should be redirected to Keycloak login
3. After login, headers should be passed to portal-router

## Troubleshooting

### Check OAuth2-Proxy logs
```bash
docker-compose logs -f oauth2-proxy
```

### Test OIDC discovery
```bash
curl http://keycloak:8080/realms/henry-enterprise/.well-known/openid-configuration
```

### Verify Redis connection
```bash
docker-compose exec redis redis-cli ping
```
