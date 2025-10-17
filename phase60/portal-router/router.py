#!/usr/bin/env python3
"""
Henry Enterprise IAM - Portal Router (Phase 70)
-----------------------------------------------
OIDC-enabled Flask router for Keycloak + FreeIPA + MFA (Google Authenticator).
Routes authenticated users to the correct dashboard based on Keycloak roles.

Author: Henry Enterprise IAM Project
"""

import os
import json
import logging
import requests
import jwt
from urllib.parse import urlencode
from flask import Flask, request, redirect, session, jsonify, Response
from dotenv import load_dotenv
from utils.logging_config import setup_logging

# ────────────────────────────────────────────────────────────────
# Flask Setup
# ────────────────────────────────────────────────────────────────
load_dotenv()
app = Flask(__name__)
setup_logging()
logger = logging.getLogger(__name__)

app.secret_key = os.getenv("FLASK_SECRET_KEY", "supersecretkey-change-me")

# ────────────────────────────────────────────────────────────────
# OIDC / Keycloak Configuration
# ────────────────────────────────────────────────────────────────
OIDC_ISSUER = os.getenv("OIDC_ISSUER", "http://keycloak:8080/realms/henry-enterprise")
OIDC_CLIENT_ID = os.getenv("OIDC_CLIENT_ID", "employee-portal")
OIDC_CLIENT_SECRET = os.getenv("OIDC_CLIENT_SECRET", "changeme")
OIDC_REDIRECT_URI = os.getenv("OIDC_REDIRECT_URI", "http://portal-router:5000/oidc/callback")

# ────────────────────────────────────────────────────────────────
# Role → Service Mapping
# ────────────────────────────────────────────────────────────────
ROLE_SERVICES = {
    "admin": "http://admin-dashboard:8504",
    "hr": "http://hr-dashboard:8501",
    "it_support": "http://it-dashboard:8502",
    "sales": "http://sales-dashboard:8503",
}
ROLE_PRECEDENCE = ["admin", "hr", "it_support", "sales"]

# ────────────────────────────────────────────────────────────────
# Health Endpoints
# ────────────────────────────────────────────────────────────────
@app.route("/healthz")
def health_check():
    return jsonify({"service": "portal-router", "status": "ok"}), 200

@app.route("/status")
def status_page():
    return "<h2>✅ Portal Router (OIDC) is running.</h2>", 200

# ────────────────────────────────────────────────────────────────
# OIDC Login Flow
# ────────────────────────────────────────────────────────────────
@app.route("/login")
def login():
    """Redirect user to Keycloak for login."""
    auth_url = f"{OIDC_ISSUER}/protocol/openid-connect/auth"
    params = {
        "client_id": OIDC_CLIENT_ID,
        "redirect_uri": OIDC_REDIRECT_URI,
        "response_type": "code",
        "scope": "openid profile email",
    }
    return redirect(f"{auth_url}?{urlencode(params)}")

@app.route("/oidc/callback")
def oidc_callback():
    """Handle redirect back from Keycloak and exchange code for tokens."""
    code = request.args.get("code")
    if not code:
        return Response("Missing authorization code", 400)

    token_url = f"{OIDC_ISSUER}/protocol/openid-connect/token"
    data = {
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": OIDC_REDIRECT_URI,
        "client_id": OIDC_CLIENT_ID,
        "client_secret": OIDC_CLIENT_SECRET,
    }

    r = requests.post(token_url, data=data)
    if r.status_code != 200:
        logger.error(f"Token exchange failed: {r.text}")
        return Response("Authentication failed", 401)

    tokens = r.json()
    id_token = tokens.get("id_token")
    access_token = tokens.get("access_token")

    # Decode token (Keycloak already enforces MFA before issuing)
    try:
        decoded = jwt.decode(
            id_token,
            options={"verify_signature": False},  # Disable for HTTP/dev only
            algorithms=["RS256"],
        )
    except Exception as e:
        logger.exception(f"Token decode failed: {e}")
        return Response("Invalid token", 401)

    session["id_token"] = id_token
    session["access_token"] = access_token
    session["userinfo"] = decoded

    logger.info(f"User {decoded.get('preferred_username')} authenticated via OIDC")
    return redirect("/")

@app.route("/logout")
def logout():
    session.clear()
    logout_url = f"{OIDC_ISSUER}/protocol/openid-connect/logout?client_id={OIDC_CLIENT_ID}&post_logout_redirect_uri={OIDC_REDIRECT_URI}"
    return redirect(logout_url)

# ────────────────────────────────────────────────────────────────
# Main Routing Logic
# ────────────────────────────────────────────────────────────────
@app.route("/", methods=["GET"])
def route_user():
    """Route authenticated users based on Keycloak roles."""
    if "userinfo" not in session:
        return redirect("/login")

    userinfo = session["userinfo"]
    roles = userinfo.get("realm_access", {}).get("roles", [])
    username = userinfo.get("preferred_username", "unknown")

    logger.info(f"Routing user={username}, roles={roles}")
    role = next((r for r in ROLE_PRECEDENCE if r in roles), None)

    if not role:
        logger.warning(f"No matching role for {username}")
        return Response("Forbidden: no matching role", 403)

    target = ROLE_SERVICES.get(role)
    if not target:
        logger.error(f"No configured service for role={role}")
        return Response("Role misconfiguration", 500)

    logger.info(f"Forwarding {username} ({role}) → {target}")
    try:
        resp = requests.get(target)
        return redirect(target)
    except Exception as e:
        logger.exception(f"Backend unreachable: {e}")
        return Response("Dashboard unreachable", 503)

# ────────────────────────────────────────────────────────────────
# Error Handlers
# ────────────────────────────────────────────────────────────────
@app.errorhandler(404)
def not_found(e):
    return jsonify({"error": "route not found", "path": request.path}), 404

@app.errorhandler(500)
def internal_error(e):
    logger.exception(f"Internal error: {e}")
    return jsonify({"error": "internal server error"}), 500

# ────────────────────────────────────────────────────────────────
# Entry Point
# ────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    logger.info("Starting Portal Router (OIDC) on 0.0.0.0:5000 ...")
    app.run(host="0.0.0.0", port=5000, debug=False)

