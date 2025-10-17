"""
Logging configuration utility for portal-router
Provides consistent structured logging across all components.
"""

import logging
import sys

def setup_logging():
    """
    Sets up structured logging for the portal router.
    Logs go to stdout (for container compatibility).
    """
    handler = logging.StreamHandler(sys.stdout)
    formatter = logging.Formatter(
        "%(asctime)s [%(levelname)s] %(name)s - %(message)s"
    )
    handler.setFormatter(formatter)

    root_logger = logging.getLogger()
    root_logger.setLevel(logging.INFO)
    root_logger.addHandler(handler)

    # Reduce noise from third-party libraries (requests, flask, etc.)
    logging.getLogger("werkzeug").setLevel(logging.WARNING)
    logging.getLogger("urllib3").setLevel(logging.WARNING)

