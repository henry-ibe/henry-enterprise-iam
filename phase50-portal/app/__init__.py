from flask import Flask
from flask_session import Session
from config import Config
import os

def create_app(config_class=Config):
    app = Flask(__name__, template_folder='../templates', static_folder='../static')
    app.config.from_object(config_class)
    Session(app)
    os.makedirs(app.config['SESSION_FILE_DIR'], exist_ok=True)
    os.makedirs('logs', exist_ok=True)
    from app.routes import main_bp
    app.register_blueprint(main_bp)
    return app
