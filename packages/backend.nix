{ pkgs, lib ? pkgs.lib, src ? ../apiserver }:

# Plane backend derivation using buildPythonApplication for proper dependency management

let
  python = pkgs.python312;
  customPythonPkgs = pkgs.callPackage ./python-pkgs.nix { inherit python; };
  
in python.pkgs.buildPythonApplication rec {
  pname = "plane-backend";
  version = "0.26.1"; # Match version from root package.json
  inherit src;
  
  format = "other";  # We don't have a setup.py
  
  # Build inputs for native dependencies
  nativeBuildInputs = with pkgs; [
    pkg-config
  ];
  
  buildInputs = with pkgs; [
    libxml2
    libxslt
    postgresql
    xmlsec
    libffi
    openssl
  ];

  # Python dependencies based on requirements/base.txt and requirements/production.txt
  propagatedBuildInputs = with python.pkgs; [
    # Django core
    django
    djangorestframework
    
    # Database
    psycopg
    dj-database-url
    
    # Redis
    redis
    django-redis
    
    # CORS
    django-cors-headers
    
    # Celery
    celery
    django-celery-beat
    django-celery-results
    python-json-logger # For JSON formatting in Celery logs
    customPythonPkgs.jsonmodels
    slack-sdk
    zxcvbn
    opentelemetry-api
    opentelemetry-sdk
    opentelemetry-instrumentation-django
    opentelemetry-exporter-otlp
    
    # File serving
    whitenoise
    
    # Web server
    gunicorn
    uvicorn
    
    # Utilities
    faker
    django-filter
    django-storages
    
    # Django utilities
    customPythonPkgs.django-crum
    
    # Communication
    channels
    
    # Integrations
    openai
    
    # File processing
    openpyxl
    beautifulsoup4
    lxml
    
    # Cloud storage
    boto3
    
    # Security & crypto
    cryptography
    pyjwt
    
    # Timezone
    pytz
    
    # Core dependencies
    requests
    pillow
    setuptools
    wheel
    pip
    
    # Custom packages (not in nixpkgs)
    customPythonPkgs.scout-apm
    customPythonPkgs.posthog
  ];

  # Don't run tests during build
  doCheck = false;
  
  # Build phase: prepare the Django application
  buildPhase = ''
    # Nothing to build for Django app
    true
  '';
  
  # Use preFixup phase to patch Django settings after all files are installed
  preFixup = ''
    echo "Patching Django settings to use PLANE_LOG_DIR environment variable"
    settingsFile="$out/share/plane/backend/plane/settings/production.py"
    if [ -f "$settingsFile" ]; then
      # Create backup
      cp "$settingsFile" "$settingsFile.bak"
      
      # Replace the entire file with our patched version
      cat > "$settingsFile" << 'EOF'
"""Production settings"""

import os
import logging

from .common import *  # noqa

# SECURITY WARNING: don't run with debug turned on in production!
DEBUG = int(os.environ.get("DEBUG", 0)) == 1

# Honor the 'X-Forwarded-Proto' header for request.is_secure()
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

# Only add scout_apm if available
try:
    import scout_apm.django
    INSTALLED_APPS += ("scout_apm.django",)  # noqa
except ImportError:
    pass  # scout_apm not available, continue without it


# Scout Settings
SCOUT_MONITOR = os.environ.get("SCOUT_MONITOR", False)
SCOUT_KEY = os.environ.get("SCOUT_KEY", "")
SCOUT_NAME = "Plane"

# Redis URL configuration - provide fallback if not set
REDIS_URL = os.environ.get("REDIS_URL", "redis://127.0.0.1:6379/0")

# Database URL configuration - provide fallback if not set
DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://plane@localhost:5432/plane")

# Log directory configuration with robust fallback
def get_log_dir():
    """Get the log directory with proper fallback logic"""
    # Try PLANE_LOG_DIR first
    plane_log_dir = os.environ.get("PLANE_LOG_DIR")
    if plane_log_dir:
        # Check if we can write to the specified directory
        try:
            if not os.path.exists(plane_log_dir):
                # Try to create the directory
                os.makedirs(plane_log_dir, exist_ok=True)
            # Test write permissions
            test_file = os.path.join(plane_log_dir, '.write_test')
            with open(test_file, 'w') as f:
                f.write('test')
            os.remove(test_file)
            return plane_log_dir
        except (OSError, IOError, PermissionError) as e:
            logging.warning(f"Cannot use PLANE_LOG_DIR {plane_log_dir}: {e}")
    
    # Fall back to /tmp/plane-logs
    fallback_dir = "/tmp/plane-logs"
    try:
        os.makedirs(fallback_dir, exist_ok=True)
        return fallback_dir
    except (OSError, IOError) as e:
        logging.warning(f"Cannot create fallback log directory {fallback_dir}: {e}")
        # Final fallback to /tmp
        return "/tmp"

LOG_DIR = get_log_dir()

# Logging configuration with better error handling
def get_logging_config():
    """Get logging configuration with error handling for file handlers"""
    config = {
        "version": 1,
        "disable_existing_loggers": True,
        "formatters": {
            "verbose": {
                "format": "%(asctime)s [%(process)d] %(levelname)s %(name)s: %(message)s"
            },
            "json": {
                "()": "pythonjsonlogger.jsonlogger.JsonFormatter",
                "fmt": "%(levelname)s %(asctime)s %(module)s %(name)s %(message)s",
            },
        },
        "handlers": {
            "console": {
                "class": "logging.StreamHandler",
                "formatter": "json",
                "level": "INFO",
            },
        },
        "loggers": {
            "plane.api.request": {
                "level": "DEBUG" if DEBUG else "INFO",
                "handlers": ["console"],
                "propagate": False,
            },
            "plane.api": {
                "level": "DEBUG" if DEBUG else "INFO",
                "handlers": ["console"],
                "propagate": False,
            },
            "plane.worker": {
                "level": "DEBUG" if DEBUG else "INFO",
                "handlers": ["console"],
                "propagate": False,
            },
            "plane.exception": {
                "level": "DEBUG" if DEBUG else "ERROR",
                "handlers": ["console"],
                "propagate": False,
            },
            "plane.external": {
                "level": "INFO",
                "handlers": ["console"],
                "propagate": False,
            },
        },
    }
    
    # Try to add file handler if possible
    try:
        log_filename = os.path.join(LOG_DIR, "plane-debug.log" if DEBUG else "plane-error.log")
        # Test if we can write to the log file
        with open(log_filename, 'a') as f:
            pass  # Just test if we can open for writing
        
        config["handlers"]["file"] = {
            "class": "plane.utils.logging.SizedTimedRotatingFileHandler",
            "filename": log_filename,
            "when": "s",
            "maxBytes": 1024 * 1024 * 1,
            "interval": 1,
            "backupCount": 5,
            "formatter": "json",
            "level": "DEBUG" if DEBUG else "ERROR",
        }
        
        # Add file handler to exception logger
        config["loggers"]["plane.exception"]["handlers"].append("file")
        
    except (OSError, IOError, PermissionError) as e:
        logging.warning(f"Cannot set up file logging: {e}")
        # Continue without file logging
    
    return config

LOGGING = get_logging_config()
EOF
      echo "Settings patched successfully"
    else
      echo "Warning: Could not find settings file at $settingsFile"
    fi
  '';

  installPhase = ''
    # Create directory structure
    mkdir -p $out/bin $out/share/plane/backend $out/share/plane/settings
    
    # Copy Django application source
    cp -r $src/* $out/share/plane/backend/
    
    # Create custom settings override for logs
    cat > $out/share/plane/settings/logs_override.py << 'EOF'
"""Settings override for logs"""

import os
import logging

LOG_DIR = os.environ.get("PLANE_LOG_DIR", os.path.join(os.environ.get("HOME", "/tmp"), ".plane/logs"))

# Only create the directory if we have write permissions
if not os.path.exists(LOG_DIR) and os.access(os.path.dirname(LOG_DIR), os.W_OK):
    try:
        os.makedirs(LOG_DIR)
    except Exception as e:
        logging.warning(f"Could not create log directory {LOG_DIR}: {e}")
        # Fall back to /tmp for logs
        LOG_DIR = "/tmp"
EOF
    
    # Create wrapper scripts for different services
    cat > $out/bin/plane-api << EOF
#!/usr/bin/env bash
set -e
cd $out/share/plane/backend
export PYTHONPATH=$out/share/plane/backend:${python.pkgs.makePythonPath propagatedBuildInputs}:\$PYTHONPATH


# Wait for database
${python}/bin/python manage.py wait_for_db

# Wait for migrations  
${python}/bin/python manage.py wait_for_migrations

# Generate machine signature
HOSTNAME=\$(hostname)
MAC_ADDRESS=\$(ip link show 2>/dev/null | awk '/ether/ {print \$2}' | head -n 1 || echo "unknown")
CPU_INFO=\$(cat /proc/cpuinfo 2>/dev/null || echo "unknown")
MEMORY_INFO=\$(free -h 2>/dev/null || echo "unknown")
DISK_INFO=\$(df -h 2>/dev/null || echo "unknown")

SIGNATURE=\$(echo "\$HOSTNAME\$MAC_ADDRESS\$CPU_INFO\$MEMORY_INFO\$DISK_INFO" | sha256sum | awk '{print \$1}')
export MACHINE_SIGNATURE=\$SIGNATURE

# Register instance
${python}/bin/python manage.py register_instance "\$MACHINE_SIGNATURE"

# Configure instance
${python}/bin/python manage.py configure_instance

# Create default bucket
${python}/bin/python manage.py create_bucket

# Clear cache
${python}/bin/python manage.py clear_cache

# Start gunicorn server
exec ${python.pkgs.gunicorn}/bin/gunicorn \\
  -w "\$\{GUNICORN_WORKERS:-4\}" \\
  -k uvicorn.workers.UvicornWorker \\
  plane.asgi:application \\
  --bind 0.0.0.0:"\$\{PORT:-8000\}" \\
  --max-requests 1200 \\
  --max-requests-jitter 1000 \\
  --access-logfile -
EOF
    chmod +x $out/bin/plane-api

    cat > $out/bin/plane-worker << EOF
#!/usr/bin/env bash
set -e
cd $out/share/plane/backend
export PYTHONPATH=$out/share/plane/backend:${python.pkgs.makePythonPath propagatedBuildInputs}:\$PYTHONPATH


exec ${python.pkgs.celery}/bin/celery \\
  -A plane.celery worker \\
  -l info \\
  --max-memory-per-child 200000
EOF
    chmod +x $out/bin/plane-worker

    cat > $out/bin/plane-beat << EOF
#!/usr/bin/env bash
set -e
cd $out/share/plane/backend
export PYTHONPATH=$out/share/plane/backend:${python.pkgs.makePythonPath propagatedBuildInputs}:\$PYTHONPATH


exec ${python.pkgs.celery}/bin/celery \\
  -A plane.celery beat \\
  -l info \\
  --scheduler django_celery_beat.schedulers:DatabaseScheduler
EOF
    chmod +x $out/bin/plane-beat

    cat > $out/bin/plane-migrate << EOF
#!/usr/bin/env bash
set -e
cd $out/share/plane/backend
export PYTHONPATH=$out/share/plane/backend:${python.pkgs.makePythonPath propagatedBuildInputs}:\$PYTHONPATH


echo "Running Django migrations..."

# Check Django installation
${python}/bin/python -c "import django; print(f'Django version: {django.get_version()}')"

# Run basic Django commands
${python}/bin/python manage.py check --deploy 2>/dev/null || ${python}/bin/python manage.py check

# Run migrations
${python}/bin/python manage.py migrate

echo "Migrations completed successfully"
EOF
    chmod +x $out/bin/plane-migrate

    # Create a unified plane command that dispatches to the specific scripts
    cat > $out/bin/plane << EOF
#!/usr/bin/env bash
set -e

COMMAND="\$1"
shift

case "\$COMMAND" in
  api)
    exec $out/bin/plane-api "\$@"
    ;;
  worker)
    exec $out/bin/plane-worker "\$@"
    ;;
  beat)
    exec $out/bin/plane-beat "\$@"
    ;;
  migrate)
    exec $out/bin/plane-migrate "\$@"
    ;;
  web)
    # Try to find plane-web in PATH
    if command -v plane-web >/dev/null 2>&1; then
      exec plane-web "\$@"
    else
      echo "Web interface command not available in PATH"
      echo "Please make sure plane-web is installed and in your PATH"
      exit 1
    fi
    ;;
  admin)
    # Try to find plane-admin in PATH
    if command -v plane-admin >/dev/null 2>&1; then
      exec plane-admin "\$@"
    else
      echo "Admin interface command not available in PATH"
      echo "Please make sure plane-admin is installed and in your PATH"
      exit 1
    fi
    ;;
  space)
    # Try to find plane-space in PATH
    if command -v plane-space >/dev/null 2>&1; then
      exec plane-space "\$@"
    else
      echo "Space interface command not available in PATH"
      echo "Please make sure plane-space is installed and in your PATH"
      exit 1
    fi
    ;;
  live)
    # Try to find plane-live in PATH
    if command -v plane-live >/dev/null 2>&1; then
      exec plane-live "\$@"
    else
      echo "Live collaboration command not available in PATH"
      echo "Please make sure plane-live is installed and in your PATH"
      exit 1
    fi
    ;;
  *)
    echo "Unknown command: \$COMMAND"
    echo "Available commands: api, worker, beat, migrate, web, admin, space, live"
    exit 1
    ;;
esac
EOF
    chmod +x $out/bin/plane

    # Create compatibility symlinks for old names
    ln -s $out/bin/plane-api $out/bin/api
    ln -s $out/bin/plane-worker $out/bin/worker  
    ln -s $out/bin/plane-beat $out/bin/beat
    ln -s $out/bin/plane-migrate $out/bin/migrate
  '';

  meta = with pkgs.lib; {
    description = "Plane backend (Django + Celery)";
    homepage = "https://plane.so";
    license = licenses.agpl3Plus;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}
