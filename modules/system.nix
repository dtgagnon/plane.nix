{ lib
, config
, ...
}:
let
  inherit (lib) mkIf;
  cfg = config.services.plane;
  protocol = if cfg.acme.enable then "https" else "http";
  storageProtocol = cfg.storage.protocol;
in
{
  config = mkIf cfg.enable {
    # Assertions for required configuration
    assertions = [
      {
        assertion = cfg.domain != "";
        message = "services.plane.domain must be set";
      }
      {
        assertion = cfg.secretKeyFile != "";
        message = "services.plane.secretKeyFile must be set";
      }
      {
        assertion = cfg.database.local -> cfg.database.passwordFile != null;
        message = "services.plane.database.passwordFile must be set when using local database";
      }
      {
        assertion = cfg.rabbitmq.local -> cfg.rabbitmq.passwordFile != null;
        message = "services.plane.rabbitmq.passwordFile must be set when using local RabbitMQ";
      }
      {
        assertion = cfg.storage.local -> cfg.storage.credentialsFile != null;
        message = "services.plane.storage.credentialsFile must be set when using local storage";
      }
    ];

    # User and group management
    # Note: MinIO user/group creation is handled automatically by services.minio module
    users.users = mkIf (cfg.user == "plane") {
      plane = {
        isSystemUser = true;
        group = cfg.group;
        home = cfg.stateDir;
        createHome = true;
        description = "Plane service user";
      };
    };

    users.groups = mkIf (cfg.group == "plane") {
      plane = { };
    };

    # Directory structure
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/media 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/static 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.logDir} 0750 ${cfg.user} ${cfg.group} -"
      "d /etc/plane 0755 root root -"
    ];

    # Environment file generation
    environment.etc."plane/plane.env" = {
      mode = "0640";
      user = cfg.user;
      group = cfg.group;
      text = ''
        # Plane Configuration
        APP_DOMAIN=${cfg.domain}
        WEB_URL=${protocol}://${cfg.domain}
        DEBUG=0
        CORS_ALLOWED_ORIGINS=${protocol}://${cfg.domain}

        # Database Configuration
        PGHOST=${cfg.database.host}
        POSTGRES_PORT=${toString cfg.database.port}
        PGDATABASE=${lib.optionalString (!cfg.database.local) cfg.database.name}
        POSTGRES_DB=${cfg.database.name}
        PGDATA=/var/lib/postgresql/data

        # Redis Configuration
        REDIS_HOST=${cfg.cache.host}
        REDIS_PORT=${toString cfg.cache.port}

        # RabbitMQ Configuration
        RABBITMQ_HOST=${cfg.rabbitmq.host}
        RABBITMQ_PORT=${toString cfg.rabbitmq.port}
        RABBITMQ_USER=${cfg.rabbitmq.user}
        RABBITMQ_VHOST=${cfg.rabbitmq.vhost}

        # API Configuration
        GUNICORN_WORKERS=${toString cfg.api.workers}
        API_KEY_RATE_LIMIT=60/minute
        
        # Logging Configuration
        PLANE_LOG_DIR=${cfg.logDir}

        # Service URLs
        NEXT_PUBLIC_API_BASE_URL=${protocol}://${cfg.domain}/api
        NEXT_PUBLIC_WEB_BASE_URL=${protocol}://${cfg.domain}
        NEXT_PUBLIC_SPACE_BASE_URL=${protocol}://${cfg.domain}/spaces
        NEXT_PUBLIC_ADMIN_BASE_URL=${protocol}://${cfg.domain}/god-mode
        
        # Sentry (optional)
        SENTRY_DSN=""
        
        # Scout APM (optional)
        SCOUT_MONITOR=0
        SCOUT_KEY=""
      '' +
      ''
        # Data Storage Configuration
        USE_MINIO=${if cfg.storage.local then "1" else "0"}
        FILE_SIZE_LIMIT=${toString cfg.storage.fileSizeLimit}
        AWS_REGION=${cfg.storage.region}
        AWS_S3_ENDPOINT_URL=${storageProtocol}://${cfg.storage.host}:${toString cfg.storage.port}
        AWS_S3_BUCKET_NAME=${cfg.storage.bucket}
      '' +
      lib.optionalString cfg.email.enable ''
        EMAIL_HOST=${cfg.email.host}
        EMAIL_PORT=${toString cfg.email.port}
        EMAIL_USE_TLS=${if cfg.email.useTLS then "1" else "0"}
      '';
    };

    # Secret credentials environment file from secret files
    system.activationScripts.plane-credentials = ''
      # Create credentials environment file from secret files
      touch /etc/plane/credentials.env
      chmod 640 /etc/plane/credentials.env
      chown ${cfg.user}:${cfg.group} /etc/plane/credentials.env

      # Django secret key
      echo "SECRET_KEY=$(cat ${cfg.secretKeyFile})" > /etc/plane/credentials.env

      # Database password if configured
      ${lib.optionalString (cfg.database.passwordFile != null) ''
        echo "POSTGRES_USER=${cfg.database.user}" >> /etc/plane/credentials.env
        echo "POSTGRES_PASSWORD=$(cat ${cfg.database.passwordFile})" >> /etc/plane/credentials.env
        echo "DATABASE_URL=postgresql://${cfg.database.user}:$(cat ${cfg.database.passwordFile})@${cfg.database.host}:${toString cfg.database.port}/${cfg.database.name}" >> /etc/plane/credentials.env
      ''}
      
      # Storage credentials if configured
      ${lib.optionalString (cfg.storage.credentialsFile != null) ''
        echo "AWS_ACCESS_KEY_ID=$(grep MINIO_ROOT_USER ${cfg.storage.credentialsFile} | cut -d '=' -f2-)" >> /etc/plane/credentials.env
        echo "AWS_SECRET_ACCESS_KEY=$(grep MINIO_ROOT_PASSWORD ${cfg.storage.credentialsFile} | cut -d '=' -f2-)" >> /etc/plane/credentials.env
      ''}

      # RabbitMQ password if configured
      ${lib.optionalString (cfg.rabbitmq.passwordFile != null) ''
        echo "RABBITMQ_PASSWORD=$(cat ${cfg.rabbitmq.passwordFile})" >> /etc/plane/credentials.env
        echo "AMQP_URL=amqp://${cfg.rabbitmq.user}:$(cat ${cfg.rabbitmq.passwordFile})@${cfg.rabbitmq.host}:${toString cfg.rabbitmq.port}/${cfg.rabbitmq.vhost}" >> /etc/plane/credentials.env
      ''}
    '';
  };
}
