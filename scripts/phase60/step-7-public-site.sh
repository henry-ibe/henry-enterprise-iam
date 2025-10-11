#!/bin/bash
# scripts/phase60/step-7-public-site.sh - Create public website

set -e

PROJECT_ROOT="$(pwd)"
PHASE60_ROOT="$PROJECT_ROOT/phase60"
PUBLIC_DIR="$PHASE60_ROOT/public-site"
ENV_FILE="$PHASE60_ROOT/.env"

echo "=== Phase 60 Step 7: Public Website ==="
echo ""

# Check if .env exists
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Error: .env file not found"
    echo "Please run step-2-environment.sh first"
    exit 1
fi

# Load environment variables
source "$ENV_FILE"

echo "📝 Creating public website files..."
echo ""

# Create index.html
cat > "$PUBLIC_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="description" content="Henry Enterprise LLC - Enterprise solutions and employee portal">
    <title>Henry Enterprise LLC - Home</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.6;
            color: #333;
            background: #f5f5f5;
        }

        header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 1rem 0;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            position: sticky;
            top: 0;
            z-index: 1000;
        }

        nav {
            max-width: 1200px;
            margin: 0 auto;
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 0 2rem;
        }

        .logo {
            font-size: 1.8rem;
            font-weight: bold;
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }

        .nav-links {
            display: flex;
            gap: 2rem;
            list-style: none;
        }

        .nav-links a {
            color: white;
            text-decoration: none;
            transition: opacity 0.3s;
            font-weight: 500;
        }

        .nav-links a:hover {
            opacity: 0.8;
        }

        .hero {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 8rem 2rem;
            text-align: center;
        }

        .hero-content {
            max-width: 800px;
            margin: 0 auto;
        }

        .hero h1 {
            font-size: 3rem;
            margin-bottom: 1rem;
            animation: fadeInUp 1s;
        }

        .hero p {
            font-size: 1.3rem;
            margin-bottom: 2rem;
            opacity: 0.9;
            animation: fadeInUp 1s 0.2s both;
        }

        .cta-button {
            display: inline-block;
            background: white;
            color: #667eea;
            padding: 1rem 3rem;
            font-size: 1.2rem;
            font-weight: bold;
            text-decoration: none;
            border-radius: 50px;
            transition: transform 0.3s, box-shadow 0.3s;
            animation: fadeInUp 1s 0.4s both;
            box-shadow: 0 4px 15px rgba(0,0,0,0.2);
        }

        .cta-button:hover {
            transform: translateY(-3px);
            box-shadow: 0 6px 20px rgba(0,0,0,0.3);
        }

        .features {
            max-width: 1200px;
            margin: 4rem auto;
            padding: 0 2rem;
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 2rem;
        }

        .feature {
            text-align: center;
            padding: 2rem;
            border-radius: 10px;
            background: white;
            transition: transform 0.3s, box-shadow 0.3s;
            box-shadow: 0 2px 10px rgba(0,0,0,0.05);
        }

        .feature:hover {
            transform: translateY(-5px);
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
        }

        .feature-icon {
            font-size: 3rem;
            margin-bottom: 1rem;
        }

        .feature h3 {
            margin-bottom: 1rem;
            color: #667eea;
        }

        .about {
            background: white;
            padding: 4rem 2rem;
            text-align: center;
        }

        .about-content {
            max-width: 800px;
            margin: 0 auto;
        }

        .about h2 {
            font-size: 2.5rem;
            margin-bottom: 1rem;
            color: #667eea;
        }

        .stats {
            max-width: 1200px;
            margin: 4rem auto;
            padding: 0 2rem;
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 2rem;
        }

        .stat {
            text-align: center;
            padding: 2rem;
        }

        .stat-number {
            font-size: 3rem;
            font-weight: bold;
            color: #667eea;
            margin-bottom: 0.5rem;
        }

        .stat-label {
            font-size: 1rem;
            color: #666;
            text-transform: uppercase;
            letter-spacing: 1px;
        }

        footer {
            background: #2c3e50;
            color: white;
            text-align: center;
            padding: 2rem;
            margin-top: 4rem;
        }

        footer p {
            margin: 0.5rem 0;
        }

        footer a {
            color: #667eea;
            text-decoration: none;
        }

        footer a:hover {
            text-decoration: underline;
        }

        @keyframes fadeInUp {
            from {
                opacity: 0;
                transform: translateY(30px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }

        @media (max-width: 768px) {
            .hero h1 {
                font-size: 2rem;
            }

            .hero p {
                font-size: 1rem;
            }

            .nav-links {
                flex-direction: column;
                gap: 1rem;
            }

            nav {
                flex-direction: column;
                gap: 1rem;
            }
        }

        .badge {
            display: inline-block;
            background: rgba(255,255,255,0.2);
            padding: 0.25rem 0.75rem;
            border-radius: 20px;
            font-size: 0.9rem;
            margin-left: 0.5rem;
        }
    </style>
</head>
<body>
    <header>
        <nav>
            <div class="logo">
                🏢 Henry Enterprise LLC
            </div>
            <ul class="nav-links">
                <li><a href="#home">Home</a></li>
                <li><a href="#about">About</a></li>
                <li><a href="#services">Services</a></li>
                <li><a href="#contact">Contact</a></li>
            </ul>
        </nav>
    </header>

    <section class="hero" id="home">
        <div class="hero-content">
            <h1>Welcome to Henry Enterprise</h1>
            <p>Empowering businesses with innovative solutions since 2015</p>
            <a href="https://portal.henry-enterprise.local" class="cta-button">
                🔐 Employee Portal Login
            </a>
            <p style="margin-top: 1rem; font-size: 0.9rem; opacity: 0.7;">
                Secure access for authorized employees only
            </p>
        </div>
    </section>

    <section class="stats">
        <div class="stat">
            <div class="stat-number">500+</div>
            <div class="stat-label">Clients Worldwide</div>
        </div>
        <div class="stat">
            <div class="stat-number">25</div>
            <div class="stat-label">Countries</div>
        </div>
        <div class="stat">
            <div class="stat-number">10</div>
            <div class="stat-label">Years of Excellence</div>
        </div>
        <div class="stat">
            <div class="stat-number">99.9%</div>
            <div class="stat-label">Uptime SLA</div>
        </div>
    </section>

    <section class="features" id="services">
        <div class="feature">
            <div class="feature-icon">💼</div>
            <h3>Enterprise Solutions</h3>
            <p>Comprehensive business management tools designed for modern organizations</p>
        </div>
        <div class="feature">
            <div class="feature-icon">🔒</div>
            <h3>Secure Access</h3>
            <p>Bank-level security with SSO and role-based access control</p>
        </div>
        <div class="feature">
            <div class="feature-icon">📊</div>
            <h3>Real-time Analytics</h3>
            <p>Make data-driven decisions with powerful analytics and reporting</p>
        </div>
        <div class="feature">
            <div class="feature-icon">🚀</div>
            <h3>Cloud-Native</h3>
            <p>Scalable infrastructure built for the modern cloud</p>
        </div>
    </section>

    <section class="about" id="about">
        <div class="about-content">
            <h2>About Henry Enterprise</h2>
            <p>
                Founded in 2015, Henry Enterprise LLC has been at the forefront of 
                delivering innovative technology solutions to businesses worldwide. 
                Our mission is to empower organizations with secure, scalable, and 
                efficient tools that drive growth and success.
            </p>
            <p style="margin-top: 1rem;">
                With over 500 clients across 25 countries, we've built a reputation 
                for excellence, reliability, and customer satisfaction. Our employee 
                portal provides secure, role-based access to critical business tools 
                for HR, IT, Sales, and Administrative teams.
            </p>
        </div>
    </section>

    <footer id="contact">
        <p><strong>&copy; 2025 Henry Enterprise LLC. All rights reserved.</strong></p>
        <p>Email: <a href="mailto:info@henry-enterprise.local">info@henry-enterprise.local</a> | 
           Phone: (555) 123-4567</p>
        <p style="margin-top: 1rem; font-size: 0.9rem; opacity: 0.8;">
            Phase 60: OIDC-Protected Employee Portal Demo
        </p>
    </footer>
</body>
</html>
EOF

echo "✅ Created: index.html (main landing page)"
echo ""

# Create a simple favicon
cat > "$PUBLIC_DIR/favicon.ico" << 'EOF'
This is a placeholder for favicon.ico
EOF

echo "✅ Created: favicon.ico (placeholder)"
echo ""

# Create robots.txt
cat > "$PUBLIC_DIR/robots.txt" << EOF
# Robots.txt for Henry Enterprise
User-agent: *
Disallow: /portal/
Allow: /
EOF

echo "✅ Created: robots.txt"
echo ""

# Create a simple nginx.conf for testing (optional)
cat > "$PUBLIC_DIR/nginx.conf" << 'EOF'
server {
    listen 80;
    server_name _;
    
    root /usr/share/nginx/html;
    index index.html;
    
    # Security headers
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    location / {
        try_files $uri $uri/ =404;
    }
    
    # Cache static assets
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
        expires 7d;
        add_header Cache-Control "public, immutable";
    }
}
EOF

echo "✅ Created: nginx.conf (optional)"
echo ""

echo "📋 Files created:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ls -lh "$PUBLIC_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Count lines in index.html
lines=$(wc -l < "$PUBLIC_DIR/index.html")
echo "📊 Statistics:"
echo "  • index.html: $lines lines"
echo "  • Responsive design: Yes"
echo "  • Portal link: https://${PORTAL_DOMAIN}"
echo ""

echo "✅ Step 7 Complete: Public website created"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Website features:"
echo "  • Modern, professional design"
echo "  • Responsive layout (mobile-friendly)"
echo "  • Animated hero section"
echo "  • Feature showcase grid"
echo "  • Company statistics"
echo "  • Employee portal call-to-action"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🌐 Website will be accessible at:"
echo "   http://${DOMAIN}"
echo "   https://${DOMAIN}"
echo ""
echo "Next: Step 8 - Create portal-router application"
