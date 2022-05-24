{ config, pkgs, ... }:
let
  acmeUser = "example@user.com";
  fqdn = "${config.networking.hostName}.${config.networking.domain}";
in
{
  environment.systemPackages = [ pkgs.minio-client ];
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  security.acme = {
    acceptTerms = true;
    defaults.email = acmeUser;
    #email = acmeUser;
  };

  services = {
    minio = {
      enable = true;
      listenAddress = "127.0.0.1:9000";
      accessKey = "access_key";
      secretKey = "secret_key";
    };

    nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      clientMaxBodySize = "500M";

      sslCiphers = "AES256+EECDH:AES256+EDH:!aNULL";
      commonHttpConfig = ''
        # Add HSTS header with preloading to HTTPS requests.
        # Adding this header to HTTP requests is discouraged
        map $scheme $hsts_header {
            https   "max-age=31536000; includeSubdomains; preload";
        }
        add_header Strict-Transport-Security $hsts_header;

        # Enable CSP for your services.
        #add_header Content-Security-Policy "script-src 'self'; object-src 'none'; base-uri 'none';" always;

        # Minimize information leaked to other domains
        add_header 'Referrer-Policy' 'origin-when-cross-origin';

        # Disable embedding as a frame
        add_header X-Frame-Options DENY;

        # Prevent injection of code in other mime types (XSS Attacks)
        add_header X-Content-Type-Options nosniff;

        # Enable XSS protection of the browser.
        # May be unnecessary when CSP is configured properly (see above)
        add_header X-XSS-Protection "1; mode=block";

        # This might create errors
        proxy_cookie_path / "/; secure; HttpOnly; SameSite=strict";

        # To allow special characters in headers
        ignore_invalid_headers off;

        # To disable buffering
        proxy_buffering off;
      '';

      virtualHosts = {
        "${fqdn}" = {
          forceSSL = true;
          enableACME = true;

          locations."/" = {
            proxyPass = "http://127.0.0.1:9000";
            proxyWebsockets = true; # needed if you need to use WebSocket
            extraConfig = ''
              # required when the target is also TLS server with multiple hosts
              proxy_ssl_server_name on;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header Host $host;
	      proxy_set_header Connection "";
              proxy_pass_header Authorization;

	      proxy_connect_timeout 300;
	      chunked_transfer_encoding off;
            '';
          };
        };
      };
    };
  };
}
