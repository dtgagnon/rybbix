{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    mkMerge
    mkPackageOption
    types
    ;
  cfg = config.services.rybbit;

  # ClickHouse XML config - must be single root element
  clickhouseServerConfig = ''
    <clickhouse>
      <listen_host>0.0.0.0</listen_host>
      <settings>
        <enable_json_type>1</enable_json_type>
      </settings>
      <logger>
        <level>warning</level>
        <console>true</console>
      </logger>
      <query_thread_log remove="remove"/>
      <query_log remove="remove"/>
      <text_log remove="remove"/>
      <trace_log remove="remove"/>
      <metric_log remove="remove"/>
      <asynchronous_metric_log remove="remove"/>
      <session_log remove="remove"/>
      <part_log remove="remove"/>
      <latency_log remove="remove"/>
      <processors_profile_log remove="remove"/>
    </clickhouse>
  '';

  clickhouseUsersConfig = ''
    <clickhouse>
      <profiles>
        <default>
          <log_queries>0</log_queries>
          <log_query_threads>0</log_query_threads>
          <log_processors_profiles>0</log_processors_profiles>
        </default>
      </profiles>
    </clickhouse>
  '';
in
{
  options.services.rybbit = {
    enable = mkEnableOption "Rybbit privacy-focused analytics platform";

    package = mkPackageOption pkgs "rybbit" {
      default = null;
      extraDescription = ''
        The Rybbit package to use. If null, uses the flake's default package.
      '';
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/rybbit";
      description = "Directory to store Rybbit state and data";
    };

    user = mkOption {
      type = types.str;
      default = "rybbit";
      description = "User account under which Rybbit runs";
    };

    group = mkOption {
      type = types.str;
      default = "rybbit";
      description = "Group under which Rybbit runs";
    };

    domain = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "analytics.example.com";
      description = "Public domain name for the Rybbit instance";
    };

    baseUrl = mkOption {
      type = types.str;
      default =
        if cfg.domain != null then
          "https://${cfg.domain}"
        else
          "http://localhost:${toString cfg.server.port}";
      defaultText = lib.literalExpression ''"https://''${cfg.domain}" or "http://localhost:''${cfg.server.port}"'';
      description = "Base URL for the Rybbit instance";
    };

    server = {
      port = mkOption {
        type = types.port;
        default = 3001;
        description = "Port for the Rybbit backend API server";
      };

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Host address for the backend to bind to";
      };
    };

    client = {
      port = mkOption {
        type = types.port;
        default = 3002;
        description = "Port for the Rybbit client (Next.js frontend)";
      };

      host = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Host address for the client to bind to";
      };
    };

    clickhouse = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enable and configure ClickHouse locally";
      };

      host = mkOption {
        type = types.str;
        default = "http://127.0.0.1:8123";
        description = "ClickHouse HTTP endpoint";
      };

      database = mkOption {
        type = types.str;
        default = "analytics";
        description = "ClickHouse database name";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to a file containing the ClickHouse password.
          Recommended to use with sops-nix.
        '';
      };
    };

    postgres = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enable and configure PostgreSQL locally";
      };

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "PostgreSQL host";
      };

      port = mkOption {
        type = types.port;
        default = 5432;
        description = "PostgreSQL port";
      };

      database = mkOption {
        type = types.str;
        default = "rybbit";
        description = "PostgreSQL database name";
      };

      user = mkOption {
        type = types.str;
        default = "rybbit";
        description = "PostgreSQL user";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to a file containing the PostgreSQL password.
          Recommended to use with sops-nix.
        '';
      };
    };

    secretsFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/secrets/rybbit";
      description = ''
        Path to a file containing environment variables for secrets.
        Should contain at minimum: BETTER_AUTH_SECRET
        Can also contain: CLICKHOUSE_PASSWORD, POSTGRES_PASSWORD, MAPBOX_TOKEN
        Recommended to use with sops-nix.
      '';
    };

    settings = {
      disableSignup = mkOption {
        type = types.bool;
        default = false;
        description = "Disable new user registrations";
      };

      disableTelemetry = mkOption {
        type = types.bool;
        default = true;
        description = "Disable telemetry reporting to Rybbit developers";
      };

      mapboxToken = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Mapbox token for geographic visualizations (optional)";
      };
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open firewall ports for Rybbit";
    };

    nginx = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to configure nginx as a reverse proxy";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Base configuration
    {
      assertions = [
        {
          assertion = cfg.secretsFile != null;
          message = "services.rybbit.secretsFile must be set (should contain BETTER_AUTH_SECRET)";
        }
      ];

      users.users.${cfg.user} = {
        isSystemUser = true;
        group = cfg.group;
        home = cfg.dataDir;
        createHome = true;
      };

      users.groups.${cfg.group} = { };

      systemd.tmpfiles.rules = [
        "d '${cfg.dataDir}' 0750 ${cfg.user} ${cfg.group} - -"
        "d '${cfg.dataDir}/logs' 0750 ${cfg.user} ${cfg.group} - -"
      ];
    }

    # ClickHouse configuration
    (mkIf cfg.clickhouse.enable {
      services.clickhouse = {
        enable = true;
        extraServerConfig = clickhouseServerConfig;
        extraUsersConfig = clickhouseUsersConfig;
      };
    })

    # PostgreSQL configuration
    (mkIf cfg.postgres.enable {
      services.postgresql = {
        enable = true;
        ensureDatabases = [ cfg.postgres.database ];
        ensureUsers = [
          {
            name = cfg.postgres.user;
            ensureDBOwnership = true;
          }
        ];
        # Use peer auth for local connections, password for TCP
        authentication = lib.mkAfter ''
          host ${cfg.postgres.database} ${cfg.postgres.user} 127.0.0.1/32 scram-sha-256
          host ${cfg.postgres.database} ${cfg.postgres.user} ::1/128 scram-sha-256
        '';
      };
    })

    # Rybbit Server (Backend API)
    {
      systemd.services.rybbit-server = {
        description = "Rybbit Analytics Backend Server";
        wantedBy = [ "multi-user.target" ];
        after =
          [ "network.target" ]
          ++ lib.optional cfg.clickhouse.enable "clickhouse.service"
          ++ lib.optional cfg.postgres.enable "postgresql.service";
        requires =
          lib.optional cfg.clickhouse.enable "clickhouse.service"
          ++ lib.optional cfg.postgres.enable "postgresql.service";

        environment = {
          NODE_ENV = "production";
          CLICKHOUSE_HOST = cfg.clickhouse.host;
          CLICKHOUSE_DB = cfg.clickhouse.database;
          POSTGRES_HOST = cfg.postgres.host;
          POSTGRES_PORT = toString cfg.postgres.port;
          POSTGRES_DB = cfg.postgres.database;
          POSTGRES_USER = cfg.postgres.user;
          BASE_URL = cfg.baseUrl;
          DISABLE_SIGNUP = lib.boolToString cfg.settings.disableSignup;
          DISABLE_TELEMETRY = lib.boolToString cfg.settings.disableTelemetry;
        } // lib.optionalAttrs (cfg.settings.mapboxToken != null) {
          MAPBOX_TOKEN = cfg.settings.mapboxToken;
        };

        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          WorkingDirectory = cfg.dataDir;
          ExecStart = "${cfg.package}/bin/rybbit-server";
          Restart = "on-failure";
          RestartSec = "5s";

          # Load secrets from file
          EnvironmentFile = cfg.secretsFile;

          # Hardening
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [ cfg.dataDir ];
        };
      };
    }

    # Rybbit Client (Next.js Frontend)
    {
      systemd.services.rybbit-client = {
        description = "Rybbit Analytics Client (Next.js)";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" "rybbit-server.service" ];
        requires = [ "rybbit-server.service" ];

        environment = {
          NODE_ENV = "production";
          PORT = toString cfg.client.port;
          HOSTNAME = cfg.client.host;
          NEXT_PUBLIC_BACKEND_URL = cfg.baseUrl;
          NEXT_PUBLIC_DISABLE_SIGNUP = lib.boolToString cfg.settings.disableSignup;
        };

        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          WorkingDirectory = cfg.dataDir;
          ExecStart = "${cfg.package}/bin/rybbit-client";
          Restart = "on-failure";
          RestartSec = "5s";

          # Hardening
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [ cfg.dataDir ];
        };
      };
    }

    # Nginx reverse proxy
    (mkIf cfg.nginx.enable {
      services.nginx = {
        enable = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;

        virtualHosts.${cfg.domain} = {
          forceSSL = true;
          enableACME = true;

          locations."/" = {
            proxyPass = "http://${cfg.client.host}:${toString cfg.client.port}";
            proxyWebsockets = true;
          };

          locations."/api" = {
            proxyPass = "http://${cfg.server.host}:${toString cfg.server.port}";
            proxyWebsockets = true;
          };
        };
      };

      security.acme.acceptTerms = true;
    })

    # Firewall configuration
    (mkIf cfg.openFirewall {
      networking.firewall.allowedTCPPorts =
        [ cfg.client.port ]
        ++ lib.optional cfg.nginx.enable 80
        ++ lib.optional cfg.nginx.enable 443;
    })
  ]);
}
