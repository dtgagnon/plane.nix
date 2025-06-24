{ lib
, config
, ...
}:
let
  inherit (lib) mkIf;
  cfg = config.services.plane;
in
{
  config = mkIf cfg.enable {
    # Nginx reverse proxy configuration
    services.nginx = mkIf cfg.nginx.enable {
      enable = true;

      # HTTP -> HTTPS redirection and ACME configuration
      virtualHosts = {
        ${cfg.domain} = {
          enableACME = cfg.acme.enable;
          forceSSL = cfg.acme.enable;

          locations = {
            # API backend
            "/api/" = mkIf cfg.api.enable {
              proxyPass = "http://127.0.0.1:${toString cfg.api.port}/";
              proxyWebsockets = true;
              extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
              '';
            };

            # Main web interface
            "/" = mkIf cfg.web.enable {
              proxyPass = "http://127.0.0.1:${toString cfg.web.port}";
              proxyWebsockets = true;
              extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
              '';
            };

            # Admin interface
            "/god-mode/" = mkIf cfg.admin.enable {
              proxyPass = "http://127.0.0.1:${toString cfg.admin.port}/";
              proxyWebsockets = true;
              extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
              '';
            };

            # Space interface
            "/spaces/" = mkIf cfg.space.enable {
              proxyPass = "http://127.0.0.1:${toString cfg.space.port}/";
              proxyWebsockets = true;
              extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
              '';
            };

            # Live collaboration interface
            "/live/" = mkIf cfg.live.enable {
              proxyPass = "http://127.0.0.1:${toString cfg.live.port}/";
              proxyWebsockets = true;
              extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
                # WebSocket specific settings
                proxy_http_version 1.1;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection "upgrade";
                proxy_read_timeout 86400;
              '';
            };
          };
        };
      };
    };
  };
}
