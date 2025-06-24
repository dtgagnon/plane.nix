{ pkgs, system, dream2nix }:

# Top-level meta-package that bundles Plane backend, front-end bundles, and proxy config.

let
  # Use the repository root as workspace root for frontend builds
  workspaceRoot = ../..;
  
  # Backend using proper Python packaging
  backend = pkgs.callPackage ./backend.nix { src = ../../apiserver; };

  # Frontend builds using buildYarnPackage with vendored dependencies
  frontend-web = pkgs.callPackage ./frontend-yarn.nix {
    srcRoot = workspaceRoot;
    appDir  = "web";
    appName = "plane-web";
    inherit dream2nix;
  };
  
  frontend-space = pkgs.callPackage ./frontend-yarn.nix {
    srcRoot = workspaceRoot;
    appDir  = "space";
    appName = "plane-space";
    inherit dream2nix;
  };
  
  frontend-admin = pkgs.callPackage ./frontend-yarn.nix {
    srcRoot = workspaceRoot;
    appDir  = "admin";
    appName = "plane-admin";
    inherit dream2nix;
  };
  
  frontend-live = pkgs.callPackage ./frontend-yarn.nix {
    srcRoot = workspaceRoot;
    appDir  = "live";
    appName = "plane-live";
    inherit dream2nix;
  };
  
  # Configuration files - minimal environment template only
  configFiles = pkgs.stdenvNoCC.mkDerivation {
    name = "plane-config";
    version = "0.26.1";
    
    # No source needed since we're generating files
    dontUnpack = true;
    
    installPhase = ''
      # Create config structure
      mkdir -p $out/share/plane/config
      
      # Create a clean environment configuration template
      cat > $out/share/plane/config/.env.example << 'EOF'
      # Plane Configuration for Native Deployment
      APP_DOMAIN=localhost
      WEB_URL=http://localhost:3000
      DEBUG=0
      CORS_ALLOWED_ORIGINS=http://localhost:3000

      # Database Settings (PostgreSQL)
      PGHOST=localhost
      PGDATABASE=plane
      POSTGRES_USER=plane
      POSTGRES_PASSWORD=plane
      POSTGRES_DB=plane
      POSTGRES_PORT=5432
      DATABASE_URL=postgresql://plane:plane@localhost:5432/plane

      # Redis Settings  
      REDIS_HOST=localhost
      REDIS_PORT=6379
      REDIS_URL=redis://localhost:6379

      # RabbitMQ Settings (for Celery)
      RABBITMQ_HOST=localhost
      RABBITMQ_PORT=5672
      RABBITMQ_USER=plane
      RABBITMQ_PASSWORD=plane
      RABBITMQ_VHOST=plane
      AMQP_URL=amqp://plane:plane@localhost:5672/plane

      # Secret Key (change this in production!)
      SECRET_KEY=change-this-secret-key-in-production

      # File Storage Settings
      USE_MINIO=0
      FILE_SIZE_LIMIT=5242880

      # For local file storage (when USE_MINIO=0)
      MEDIA_ROOT=/tmp/plane/media
      STATIC_ROOT=/tmp/plane/static

      # Gunicorn Workers
      GUNICORN_WORKERS=4

      # API rate limiting
      API_KEY_RATE_LIMIT=60/minute

      # Service URLs for frontend apps
      NEXT_PUBLIC_API_BASE_URL=http://localhost:8000
      NEXT_PUBLIC_WEB_BASE_URL=http://localhost:3000
      NEXT_PUBLIC_SPACE_BASE_URL=http://localhost:3002
      NEXT_PUBLIC_ADMIN_BASE_URL=http://localhost:3001
      EOF
    '';
  };
  
  # Clean CLI focused on service management only
  entrypoint = pkgs.writeScriptBin "plane" ''
    #!/usr/bin/env bash
    set -e

    PLANE_HOME="''${PLANE_HOME:-$HOME/.plane}"

    function show_usage() {
      echo "Plane - Open Source Project Management"
      echo ""
      echo "Usage: plane [command] [options]"
      echo ""
      echo "Backend Services:"
      echo "  api           Start the Plane API server (port 8000)"
      echo "  worker        Start the Celery worker" 
      echo "  beat          Start the Celery beat scheduler"
      echo "  migrate       Run database migrations"
      echo ""
      echo "Frontend Services:"
      echo "  web           Start the main web interface (port 3000)"
      echo "  space         Start the public space interface (port 3002)"
      echo "  admin         Start the admin interface (port 3001)"
      echo "  live          Start the real-time collaboration service (port 3003)"
      echo ""
      echo "Utilities:"
      echo "  setup         Copy configuration template to PLANE_HOME"
      echo "  help          Show this help message"
      echo ""
      echo "Environment Variables:"
      echo "  PLANE_HOME    Configuration directory (default: ~/.plane)"
      echo ""
    }

    if [ $# -eq 0 ] || [ "$1" == "help" ]; then
      show_usage
      exit 0
    fi

    # Setup command creates initial configuration
    if [ "$1" == "setup" ]; then
      if [ -d "$PLANE_HOME" ]; then
        echo "Configuration directory already exists at $PLANE_HOME"
        echo "To reconfigure, remove this directory first or use a different PLANE_HOME."
        exit 1
      fi
      
      echo "Creating Plane configuration in $PLANE_HOME..."
      mkdir -p "$PLANE_HOME"
      cp ${configFiles}/share/plane/config/.env.example "$PLANE_HOME/"
      
      echo ""
      echo "✓ Configuration template copied to $PLANE_HOME/.env.example"
      echo ""
      echo "Next steps:"
      echo "1. Copy $PLANE_HOME/.env.example to $PLANE_HOME/.env and edit it"
      echo "2. Set up PostgreSQL, Redis, and RabbitMQ"
      echo "3. Run 'plane migrate' to set up the database"
      echo "4. Start services with 'plane api', 'plane web', etc."
      echo ""
      exit 0
    fi

    # Route to appropriate service binary
    case "$1" in
      api)
        exec "${backend}/bin/plane-api" "''${@:2}"
        ;;
      worker) 
        exec "${backend}/bin/plane-worker" "''${@:2}"
        ;;
      beat)
        exec "${backend}/bin/plane-beat" "''${@:2}"
        ;;
      migrate)
        exec "${backend}/bin/plane-migrate" "''${@:2}"
        ;;
      web)
        exec "${frontend-web}/bin/plane-web" "''${@:2}"
        ;;
      space)
        exec "${frontend-space}/bin/plane-space" "''${@:2}"
        ;;
      admin)
        exec "${frontend-admin}/bin/plane-admin" "''${@:2}"
        ;;
      live)
        exec "${frontend-live}/bin/plane-live" "''${@:2}"
        ;;
      *)
        echo "Unknown command: $1"
        echo ""
        show_usage
        exit 1
        ;;
    esac
  '';
  
  # Final meta-package that bundles everything
  finalPackage = pkgs.symlinkJoin {
    name = "plane";
    version = "0.26.1";
    paths = [ 
      backend 
      frontend-web 
      frontend-space 
      frontend-admin 
      frontend-live 
      configFiles
      entrypoint
    ];
    
    meta = with pkgs.lib; {
      description = "Plane - Open Source Project Management Platform";
      longDescription = ''
        Plane is an open-source project management tool that helps teams track issues, 
        run cycles, and manage product roadmaps. This package includes:
        
        - Django backend API with Celery workers
        - Next.js web interface
        - Public space interface  
        - Admin interface
        - Real-time collaboration service
        - Configuration templates and setup tools
      '';
      homepage = "https://plane.so";
      license = licenses.agpl3Plus;
      maintainers = [ ];
      platforms = platforms.linux;
      mainProgram = "plane";
    };
    
    passthru = {
      inherit backend frontend-web frontend-space frontend-admin frontend-live configFiles;
      
      # Provide individual components for advanced usage
      components = {
        api = "${backend}/bin/plane-api";
        worker = "${backend}/bin/plane-worker"; 
        beat = "${backend}/bin/plane-beat";
        migrate = "${backend}/bin/plane-migrate";
        web = "${frontend-web}/bin/plane-web";
        space = "${frontend-space}/bin/plane-space";
        admin = "${frontend-admin}/bin/plane-admin";
        live = "${frontend-live}/bin/plane-live";
      };
    };
  };

in finalPackage
