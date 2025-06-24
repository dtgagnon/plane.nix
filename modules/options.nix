{ lib, pkgs, planePackage ? null, ... }:

let
  inherit (lib) mkEnableOption mkOption types literalExpression;
in
{
  options.services.plane = {
    enable = mkEnableOption "Plane project management platform";

    package = mkOption {
      type = types.package;
      default = if planePackage != null 
               then planePackage 
               else pkgs.plane or (throw "plane package not found in pkgs");
      defaultText = literalExpression "planePackage or pkgs.plane";
      description = "The Plane package to use.";
    };

    domain = mkOption {
      type = types.str;
      description = "The domain to use for hosting Plane.";
      example = "plane.example.com";
    };

    user = mkOption {
      type = types.str;
      default = "plane";
      description = "The user to use for the Plane service.";
    };

    group = mkOption {
      type = types.str;
      default = "plane";
      description = "The group to use for the Plane service.";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/plane";
      description = "The state directory for the Plane service.";
    };

    logDir = mkOption {
      type = types.str;
      default = "/var/log/plane";
      description = "The log directory for the Plane service.";
    };

    secretKeyFile = mkOption {
      type = types.str;
      description = "Path to file containing the Django secret key for the Plane service.";
      example = "/run/secrets/plane-secret-key";
    };

    web = {
      enable = mkEnableOption "Plane web interface" // { default = true; };

      port = mkOption {
        type = types.port;
        default = 3101;
        description = "The port to use for the Plane web service.";
      };
    };

    admin = {
      enable = mkEnableOption "Plane admin interface" // { default = true; };

      port = mkOption {
        type = types.port;
        default = 3102;
        description = "The port to use for the Plane admin service.";
      };
    };

    api = {
      enable = mkEnableOption "Plane API backend" // { default = true; };

      workers = mkOption {
        type = types.int;
        default = 1;
        description = "The number of workers to use for the Plane API service.";
      };

      port = mkOption {
        type = types.port;
        default = 3103;
        description = "The port to use for the Plane API service.";
      };
    };

    space = {
      enable = mkEnableOption "Plane public space interface" // { default = true; };

      port = mkOption {
        type = types.port;
        default = 3104;
        description = "The port to use for the Plane space service.";
      };
    };

    live = {
      enable = mkEnableOption "Plane live collaboration service" // { default = false; };

      port = mkOption {
        type = types.port;
        default = 3105;
        description = "The port to use for the Plane live service.";
      };
    };

    worker = {
      enable = mkEnableOption "Plane Celery worker" // { default = true; };
    };

    beat = {
      enable = mkEnableOption "Plane Celery beat scheduler" // { default = true; };
    };

    database = {
      local = mkEnableOption "local Plane PostgreSQL database";

      user = mkOption {
        type = types.str;
        default = "plane";
        description = "The user to use for the Plane database.";
      };

      passwordFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to file containing the password for the Plane database.";
        example = "/run/secrets/plane-db-password";
      };

      name = mkOption {
        type = types.str;
        default = "plane";
        description = "The name of the Plane database.";
      };

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "The host of the Plane database.";
      };

      port = mkOption {
        type = types.port;
        default = 5432;
        description = "The port of the Plane database.";
      };
    };

    storage = {
      local = mkEnableOption "local MinIO instance for file storage";

      region = mkOption {
        type = types.str;
        default = "us-east-1";
        description = "The region to use for the Plane storage.";
      };

      credentialsFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to file containing MinIO/S3 credentials (access key and secret key).";
        example = "/run/secrets/plane-storage-credentials";
      };

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "The host of the Plane storage service.";
      };

      port = mkOption {
        type = types.port;
        default = 9000;
        description = "The port of the Plane storage service.";
      };

      fileSizeLimit = mkOption {
        type = types.ints.positive;
        default = 5242880; # 5MB in bytes
        description = "Maximum file size limit for uploads in bytes.";
      };

      bucket = mkOption {
        type = types.str;
        default = "plane-uploads";
        description = "The name of the S3 bucket to use for file storage.";
      };

      protocol = mkOption {
        type = types.enum [ "http" "https" ];
        default = "http";
        description = "The protocol to use for the Plane storage.";
      };
    };

    cache = {
      local = mkEnableOption "local Redis instance for caching";

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "The host of the Plane cache service.";
      };

      port = mkOption {
        type = types.port;
        default = 6379;
        description = "The port of the Plane cache service.";
      };
    };

    rabbitmq = {
      local = mkEnableOption "local RabbitMQ instance for message queuing";

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "The host of the RabbitMQ service.";
      };

      port = mkOption {
        type = types.port;
        default = 5672;
        description = "The port of the RabbitMQ service.";
      };

      user = mkOption {
        type = types.str;
        default = "plane";
        description = "The user for RabbitMQ authentication.";
      };

      passwordFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to file containing the RabbitMQ password.";
        example = "/run/secrets/plane-rabbitmq-password";
      };

      vhost = mkOption {
        type = types.str;
        default = "plane";
        description = "The virtual host for RabbitMQ.";
      };
    };

    email = {
      enable = mkEnableOption "email service" // { default = true; };
      host = mkOption {
        type = types.str;
        default = "localhost";
        description = "The host of the email service.";
      };

      port = mkOption {
        type = types.port;
        default = 587;
        description = "The port of the email service.";
      };

      useTLS = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to use TLS for the email service.";
      };
    };

    acme = {
      enable = mkEnableOption "ACME certificates for Plane domain" // { default = true; };
    };

    nginx = {
      enable = mkEnableOption "nginx reverse proxy for Plane" // { default = true; };
    };
  };
}
