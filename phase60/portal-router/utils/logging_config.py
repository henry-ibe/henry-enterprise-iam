"""
Logging configuration for portal router
Provides structured JSON logging for easy parsing
"""

import logging
import json
import sys
from datetime import datetime

class JSONFormatter(logging.Formatter):
    """
    Format logs as JSON for easy parsing by log aggregators.
    """
    def format(self, record):
        log_data = {
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'level': record.levelname,
            'logger': record.name,
            'message': record.getMessage(),
            'module': record.module,
            'function': record.funcName,
            'line': record.lineno
        }
        
        # Add user context if available
        if hasattr(record, 'user_email'):
            log_data['user_email'] = record.user_email
        
        if hasattr(record, 'user_roles'):
            log_data['user_roles'] = record.user_roles
        
        # Add exception info if present
        if record.exc_info:
            log_data['exception'] = self.formatException(record.exc_info)
        
        return json.dumps(log_data)

def setup_logging():
    """
    Configure application logging with JSON formatter.
    """
    # Create handler
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JSONFormatter())
    
    # Configure root logger
    root_logger = logging.getLogger()
    root_logger.addHandler(handler)
    root_logger.setLevel(logging.INFO)
    
    # Set debug level for auth-related logs
    logging.getLogger('utils.auth').setLevel(logging.DEBUG)
    
    # Reduce noise from other libraries
    logging.getLogger('werkzeug').setLevel(logging.WARNING)
    logging.getLogger('urllib3').setLevel(logging.WARNING)
