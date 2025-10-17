#!/usr/bin/env python3
from app import create_app
from dotenv import load_dotenv
import os

load_dotenv()
app = create_app()

if __name__ == '__main__':
    host = os.environ.get('APP_HOST', '0.0.0.0')
    port = int(os.environ.get('APP_PORT', 5000))
    debug = os.environ.get('FLASK_ENV', 'production') == 'development'
    
    print("=" * 60)
    print("🏢 Henry Enterprise Portal Starting...")
    print("=" * 60)
    print(f"Host: {host}")
    print(f"Port: {port}")
    print(f"Debug: {debug}")
    print("=" * 60)
    
    app.run(host=host, port=port, debug=debug)
