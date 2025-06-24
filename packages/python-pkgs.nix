{ pkgs, python ? pkgs.python312 }:

let
  inherit (python.pkgs) buildPythonPackage fetchPypi;
in
{
  # Django-crum: Django utilities for handling current request/user
  # Using minimal implementation to avoid build issues with upstream package
  django-crum = buildPythonPackage rec {
    pname = "django-crum";
    version = "0.7.9";
    
    # Create a minimal implementation instead of using upstream source
    src = pkgs.writeText "django-crum-setup.py" ''
      from setuptools import setup, find_packages
      
      setup(
          name="django-crum",
          version="0.7.9",
          packages=["crum"],
          install_requires=["Django"],
      )
    '';
    
    # Copy source file creation to build phase  
    unpackPhase = ''
      mkdir -p django-crum/crum
      cd django-crum
      
      # Create __init__.py with minimal crum functionality
      cat > crum/__init__.py << 'EOF'
"""
Minimal django-crum implementation for Plane
"""
import threading
from typing import Optional
from django.contrib.auth.models import AnonymousUser

_current_request = threading.local()

def get_current_request():
    """Get the current request from thread local storage"""
    return getattr(_current_request, 'request', None)

def get_current_user():
    """Get the current user from the current request"""
    request = get_current_request()
    if request and hasattr(request, 'user'):
        return request.user
    return None

def set_current_request(request):
    """Set the current request in thread local storage"""
    _current_request.request = request

class CurrentRequestUserMiddleware:
    """Django middleware to track current request"""
    
    def __init__(self, get_response):
        self.get_response = get_response
        
    def __call__(self, request):
        set_current_request(request)
        try:
            response = self.get_response(request)
        finally:
            set_current_request(None)
        return response
EOF
      
      # Create setup.py 
      cp ${src} setup.py
    '';
    
    propagatedBuildInputs = with python.pkgs; [
      django
    ];
    
    # Skip tests 
    doCheck = false;
    
    meta = with pkgs.lib; {
      description = "Minimal django-crum implementation for Plane";
      license = licenses.bsd3;
      maintainers = [ ];
    };
  };
  
  # Scout APM: Application Performance Monitoring for Python
  # Using a minimal stub since scout-apm version issues and it's optional for core functionality
  scout-apm = buildPythonPackage rec {
    pname = "scout-apm";
    version = "3.1.0";
    
    # Create a minimal stub implementation
    src = pkgs.writeText "scout-apm-setup.py" ''
      from setuptools import setup, find_packages
      
      setup(
          name="scout-apm",
          version="3.1.0",
          packages=["scout_apm", "scout_apm.django"],
          install_requires=["requests", "psutil"],
      )
    '';
    
    unpackPhase = ''
      mkdir -p scout-apm/scout_apm/django
      cd scout-apm
      
      # Create __init__.py with minimal scout functionality
      cat > scout_apm/__init__.py << 'EOF'
      """
      Minimal scout-apm stub implementation for Plane
      """
      # Minimal stubs for scout-apm to prevent import errors
      class Config:
          def __init__(self, **kwargs):
              for k, v in kwargs.items():
                  setattr(self, k, v)

      def install(config=None):
          """Stub install function"""
          pass

      __version__ = "3.1.0"
      EOF

            # Create Django integration stub
            cat > scout_apm/django/__init__.py << 'EOF'
      """
      Minimal scout-apm Django integration stub
      """
      # This is a stub to prevent Django from crashing when scout_apm.django is in INSTALLED_APPS
      # but scout APM is not actually configured or needed
      EOF
      
      # Create setup.py 
      cp ${src} setup.py
    '';
    
    propagatedBuildInputs = with python.pkgs; [
      requests
      psutil
    ];
    
    # Skip tests 
    doCheck = false;
    
    meta = with pkgs.lib; {
      description = "Minimal scout-apm stub implementation for Plane";
      license = licenses.mit;
      maintainers = [ ];
    };
  };

  # Jsonmodels - lightweight JSON data models; pull directly from PyPI
  jsonmodels = buildPythonPackage rec {
    pname = "jsonmodels";
    version = "2.7.0";

    src = fetchPypi {
      inherit pname version;
      sha256 = "sha256-jAGb8b0lKsPkARJ1B9c16g/WzjCSGAK1/Fx2HNQaGLs=";
    };

    propagatedBuildInputs = with python.pkgs; [];
    doCheck = false;
    meta = with pkgs.lib; {
      description = "Data validation and modelling based on Python dataclasses with JSON serialization";
      license = licenses.mit;
      maintainers = [];
    };
  };

  # PostHog analytics client - minimal stub to satisfy Plane import
  posthog = buildPythonPackage rec {
    pname = "posthog";
    version = "3.4.0";

    # Create a minimal stub implementation
    src = pkgs.writeText "posthog-setup.py" ''
      from setuptools import setup, find_packages

      setup(
          name="posthog",
          version="3.4.0",
          packages=["posthog"],
          install_requires=["requests"],
      )
    '';

    unpackPhase = ''
      mkdir -p posthog/posthog
      cd posthog

      # Provide extremely small API surface just to avoid import errors
      cat > posthog/__init__.py << 'EOF'
"""
Minimal PostHog analytics stub for Plane
Provides a Posthog object with no-op capture/flush methods.
"""

def Posthog(*args, **kwargs):
    class _Stub:
        def capture(self, *args, **kwargs):
            pass
        def flush(self):
            pass
    return _Stub()
EOF

      # Copy stub setup.py
      cp ${src} setup.py
    '';

    propagatedBuildInputs = with python.pkgs; [
      requests
    ];

    doCheck = false;

    meta = with pkgs.lib; {
      description = "Minimal PostHog stub implementation for Plane";
      license = licenses.mit;
      maintainers = [ ];
    };
  };
}