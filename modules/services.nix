{ lib
, pkgs
, config
, ...
}:
let
  inherit (lib) mkIf;
  cfg = config.services.plane;
in
{
  config = mkIf cfg.enable {
    # Backend systemd services
    systemd.services = {
      # Database migration service (oneshot)
      plane-migrate = mkIf cfg.api.enable {
        description = "Plane database migration";
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.bash ];
        after = [ "network.target" ]
          ++ lib.optional cfg.database.local "postgresql.service"
          ++ lib.optional cfg.cache.local "redis-plane.service"
          ++ lib.optional cfg.rabbitmq.local "rabbitmq.service";
        requires = [ "network.target" ]
          ++ lib.optional cfg.database.local "postgresql.service"
          ++ lib.optional cfg.cache.local "redis-plane.service"
          ++ lib.optional cfg.rabbitmq.local "rabbitmq.service";
        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          Group = cfg.group;
          Environment = [
            "PLANE_LOG_DIR=${cfg.logDir}"
          ];
          EnvironmentFile = [
            "/etc/plane/plane.env"
            "/etc/plane/credentials.env"
          ];
          WorkingDirectory = "/tmp";
          ExecStart = "${cfg.package}/bin/plane migrate";
          Restart = "no";
        };
      };

      # API server
      plane-api = mkIf cfg.api.enable {
        description = "Plane API server";
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.bash ];
        after = [ "network.target" "plane-migrate.service" ]
          ++ lib.optional cfg.database.local "postgresql.service"
          ++ lib.optional cfg.cache.local "redis-plane.service"
          ++ lib.optional cfg.rabbitmq.local "rabbitmq.service"
          ++ lib.optional cfg.storage.local "minio.service";
        wants = [ "plane-migrate.service" ]
          ++ lib.optional cfg.storage.local "minio.service";
        requires = [ "network.target" ]
          ++ lib.optional cfg.database.local "postgresql.service"
          ++ lib.optional cfg.cache.local "redis-plane.service"
          ++ lib.optional cfg.rabbitmq.local "rabbitmq.service";
        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          Environment = [
            "PLANE_LOG_DIR=${cfg.logDir}"
          ];
          EnvironmentFile = [
            "/etc/plane/plane.env"
            "/etc/plane/credentials.env"
          ];
          WorkingDirectory = "/tmp";
          ExecStart = "${cfg.package}/bin/plane api --bind 127.0.0.1:${toString cfg.api.port}";
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };

      # Celery worker
      plane-worker = mkIf cfg.worker.enable {
        description = "Plane Celery worker";
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.bash ];
        after = [ "network.target" "plane-migrate.service" ]
          ++ lib.optional cfg.database.local "postgresql.service"
          ++ lib.optional cfg.cache.local "redis-plane.service"
          ++ lib.optional cfg.rabbitmq.local "rabbitmq.service"
          ++ lib.optional cfg.storage.local "minio.service";
        wants = [ "plane-migrate.service" ]
          ++ lib.optional cfg.storage.local "minio.service";
        requires = [ "network.target" ]
          ++ lib.optional cfg.database.local "postgresql.service"
          ++ lib.optional cfg.cache.local "redis-plane.service"
          ++ lib.optional cfg.rabbitmq.local "rabbitmq.service";
        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          Environment = [
            "PLANE_LOG_DIR=${cfg.logDir}"
          ];
          EnvironmentFile = [
            "/etc/plane/plane.env"
            "/etc/plane/credentials.env"
          ];
          WorkingDirectory = "/tmp";
          ExecStart = "${cfg.package}/bin/plane worker";
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };

      # Celery beat scheduler
      plane-beat = mkIf cfg.beat.enable {
        description = "Plane Celery beat scheduler";
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.bash ];
        after = [ "network.target" "plane-migrate.service" ]
          ++ lib.optional cfg.database.local "postgresql.service"
          ++ lib.optional cfg.cache.local "redis-plane.service"
          ++ lib.optional cfg.rabbitmq.local "rabbitmq.service";
        wants = [ "plane-migrate.service" ];
        requires = [ "network.target" ]
          ++ lib.optional cfg.database.local "postgresql.service"
          ++ lib.optional cfg.cache.local "redis-plane.service"
          ++ lib.optional cfg.rabbitmq.local "rabbitmq.service";
        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          Environment = [
            "PLANE_LOG_DIR=${cfg.logDir}"
          ];
          EnvironmentFile = [
            "/etc/plane/plane.env"
            "/etc/plane/credentials.env"
          ];
          WorkingDirectory = "/tmp";
          ExecStart = "${cfg.package}/bin/plane beat";
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };

      # Web interface service
      plane-web = mkIf cfg.web.enable {
        description = "Plane web interface";
        wantedBy = [ "multi-user.target" ];
        path = [ 
          pkgs.bash 
          # Add the frontend packages to PATH
          cfg.package
        ];
        after = [ "network.target" ] ++ lib.optional cfg.api.enable "plane-api.service";
        wants = lib.optional cfg.api.enable "plane-api.service";
        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          EnvironmentFile = [
            "/etc/plane/plane.env"
          ];
          WorkingDirectory = "/tmp";
          ExecStart = "${cfg.package}/bin/plane web --port ${toString cfg.web.port}";
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };

      # Admin frontend
      plane-admin = mkIf cfg.admin.enable {
        description = "Plane admin interface";
        wantedBy = [ "multi-user.target" ];
        path = [ 
          pkgs.bash 
          # Add the frontend packages to PATH
          cfg.package
        ];
        after = [ "network.target" ] ++ lib.optional cfg.api.enable "plane-api.service";
        wants = lib.optional cfg.api.enable "plane-api.service";
        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          EnvironmentFile = [
            "/etc/plane/plane.env"
          ];
          WorkingDirectory = "/tmp";
          ExecStart = "${cfg.package}/bin/plane admin --port ${toString cfg.admin.port}";
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };

      # Space frontend
      plane-space = mkIf cfg.space.enable {
        description = "Plane space interface";
        wantedBy = [ "multi-user.target" ];
        path = [ 
          pkgs.bash 
          # Add the frontend packages to PATH
          cfg.package
        ];
        after = [ "network.target" ] ++ lib.optional cfg.api.enable "plane-api.service";
        wants = lib.optional cfg.api.enable "plane-api.service";
        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          EnvironmentFile = [
            "/etc/plane/plane.env"
          ];
          WorkingDirectory = "/tmp";
          ExecStart = "${cfg.package}/bin/plane space --port ${toString cfg.space.port}";
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };

      # Live collaboration service
      plane-live = mkIf cfg.live.enable {
        description = "Plane live collaboration service";
        wantedBy = [ "multi-user.target" ];
        path = [ 
          pkgs.bash 
          # Add the frontend packages to PATH
          cfg.package
        ];
        after = [ "network.target" ] ++ lib.optional cfg.api.enable "plane-api.service";
        wants = lib.optional cfg.api.enable "plane-api.service";
        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          EnvironmentFile = [
            "/etc/plane/plane.env"
          ];
          WorkingDirectory = "/tmp";
          ExecStart = "${cfg.package}/bin/plane live --port ${toString cfg.live.port}";
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };
    };

    services.postgresql = mkIf cfg.database.local {
      enable = true;
      settings.port = cfg.database.port;
      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [
        {
          name = cfg.database.user;
          ensureDBOwnership = true;
        }
      ];
    };
    # Set the postgresql password on every start to ensure it's always in sync.
    # The password file is read at runtime to avoid storing the secret in the Nix store.
    systemd.services.postgresql = mkIf cfg.database.local {
      # Add these to the already created postgresql service
      serviceConfig = {
        ExecStartPost = [
          "+${pkgs.writeShellScript "postgresql-set-password" ''
            # Create a temporary, secure SQL script to avoid command-line injection.
            SQL_SCRIPT=$(${pkgs.coreutils}/bin/mktemp)

            # Build the SQL command in the script, escaping single quotes in the password.
            (
              ${pkgs.coreutils}/bin/echo -n "ALTER USER ${cfg.database.user} WITH PASSWORD '"
              ${pkgs.coreutils}/bin/cat ${cfg.database.passwordFile} | ${pkgs.gnused}/bin/sed "s/'/''''/g" | ${pkgs.coreutils}/bin/tr -d '\n'
              ${pkgs.coreutils}/bin/echo -n "';"
            ) > "$SQL_SCRIPT"

            # Execute the script as the postgres user.
            ${pkgs.sudo}/bin/sudo -u postgres ${pkgs.postgresql_16}/bin/psql -f "$SQL_SCRIPT"

            # Clean up the temporary script.
            ${pkgs.coreutils}/bin/rm "$SQL_SCRIPT"
          ''}"  # Note the + to make this execute as root, not the postgres user
        ];
      };
    };

    services.redis.servers = mkIf cfg.cache.local {
      plane = {
        enable = true;
        port = cfg.cache.port;
        bind = cfg.cache.host;
      };
    };

    services.rabbitmq = mkIf cfg.rabbitmq.local {
      enable = true;
      listenAddress = cfg.rabbitmq.host;
      port = cfg.rabbitmq.port;
    };

    services.minio = mkIf cfg.storage.local {
      enable = true;
      listenAddress = "${cfg.storage.host}:${toString cfg.storage.port}";
      dataDir = [ "/srv/plane/minio" ]; # Stores data within plane stateDir for organization
      configDir = "/var/lib/minio/config";
      rootCredentialsFile = cfg.storage.credentialsFile;
    };
  };
}