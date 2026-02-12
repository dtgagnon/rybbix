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

  # GeoLite2 database for IP geolocation
  geoDbDir = "${cfg.dataDir}/geolite2";
  geoCityPath = "${geoDbDir}/GeoLite2-City.mmdb";
  geoCityEtag = "${geoDbDir}/city.etag";
  geoCityUrl = "https://raw.githubusercontent.com/P3TERX/GeoLite.mmdb/download/GeoLite2-City.mmdb";

  geoUpdateScript = pkgs.writeShellScript "rybbit-geolite2-update" ''
    set -euo pipefail

    mkdir -p "${geoDbDir}"
    cd "${geoDbDir}"

    TMPFILE=$(mktemp)
    HTTP_CODE=$(${pkgs.curl}/bin/curl -sSL \
      --etag-compare "${geoCityEtag}" \
      --etag-save "${geoCityEtag}.new" \
      -o "$TMPFILE" \
      -w "%{http_code}" \
      "${geoCityUrl}")

    if [ "$HTTP_CODE" = "200" ]; then
      mv "$TMPFILE" "${geoCityPath}"
      mv "${geoCityEtag}.new" "${geoCityEtag}"
      chown ${cfg.user}:${cfg.group} "${geoCityPath}"
      chmod 0644 "${geoCityPath}"
      echo "GeoLite2-City updated"
    elif [ "$HTTP_CODE" = "304" ]; then
      rm -f "$TMPFILE" "${geoCityEtag}.new"
      echo "GeoLite2-City is up-to-date"
    else
      rm -f "$TMPFILE" "${geoCityEtag}.new"
      echo "Failed to check GeoLite2-City: HTTP $HTTP_CODE" >&2
      exit 1
    fi

    # Symlink into data dir so server finds it at process.cwd()
    ln -sf "${geoCityPath}" "${cfg.dataDir}/GeoLite2-City.mmdb"
  '';

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

  # Drizzle config for postgres schema migration
  drizzleConfig = pkgs.writeText "rybbit-drizzle.mjs" ''
    import { defineConfig } from "drizzle-kit";
    export default defineConfig({
      dialect: "postgresql",
      schema: "${cfg.package}/lib/rybbit-server/dist/db/postgres/schema.js",
      dbCredentials: {
        host: "${cfg.postgres.host}",
        port: ${toString cfg.postgres.port},
        database: "${cfg.postgres.database}",
        user: "${cfg.postgres.user}",
        ssl: false,
      },
    });
  '';

  postgresMigrateScript = pkgs.writeShellScript "rybbit-postgres-migrate" ''
    set -euo pipefail
    cd ${cfg.package}/lib/rybbit-server
    export NODE_PATH=${cfg.package}/lib/rybbit-server/node_modules
    ${pkgs.nodejs_20}/bin/node ./node_modules/.bin/drizzle-kit push \
      --config ${drizzleConfig}
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
        default = "/run/postgresql";
        description = ''
          PostgreSQL host. Use a directory path (e.g. /run/postgresql) for
          Unix socket connections with peer auth, or an IP address for TCP.
        '';
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
        Optional: CLICKHOUSE_PASSWORD, MAPBOX_TOKEN
        Only needed if using TCP postgres: POSTGRES_PASSWORD
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

    geolocation = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to download and manage the GeoLite2-City database for IP geolocation";
      };

      updateInterval = mkOption {
        type = types.str;
        default = "weekly";
        description = "How often to check for GeoLite2 database updates (systemd calendar format)";
        example = "daily";
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

      # Create the ClickHouse database before rybbit-server starts
      systemd.services.rybbit-clickhouse-init = {
        description = "Initialize ClickHouse database for Rybbit";
        after = [ "clickhouse.service" ];
        requires = [ "clickhouse.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "rybbit-clickhouse-init" ''
            ${pkgs.clickhouse}/bin/clickhouse-client \
              --query "CREATE DATABASE IF NOT EXISTS ${cfg.clickhouse.database}"
          '';
        };
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
      } // lib.optionalAttrs (! lib.hasPrefix "/" cfg.postgres.host) {
        # TCP auth - only needed when postgres.host is an IP, not a socket path
        authentication = lib.mkAfter ''
          host ${cfg.postgres.database} ${cfg.postgres.user} 127.0.0.1/32 scram-sha-256
          host ${cfg.postgres.database} ${cfg.postgres.user} ::1/128 scram-sha-256
        '';
      };

      # Push drizzle schema to postgres before server starts
      systemd.services.rybbit-postgres-migrate = {
        description = "Push Rybbit database schema to PostgreSQL";
        after = [ "postgresql.service" ];
        requires = [ "postgresql.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = cfg.user;
          Group = cfg.group;
          ExecStart = postgresMigrateScript;
        };
      };
    })

    # GeoLite2 database management
    (mkIf cfg.geolocation.enable {
      systemd.services.rybbit-geolite2-update = {
        description = "Update GeoLite2 City database for Rybbit geolocation";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];

        serviceConfig = {
          Type = "oneshot";
          ExecStart = geoUpdateScript;
        };
      };

      systemd.timers.rybbit-geolite2-update = {
        description = "Periodic GeoLite2-City database update for Rybbit";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.geolocation.updateInterval;
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
      };
    })

    # Rybbit Server (Backend API)
    {
      systemd.services.rybbit-server = {
        description = "Rybbit Analytics Backend Server";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network.target"
        ]
        ++ lib.optional cfg.clickhouse.enable "rybbit-clickhouse-init.service"
        ++ lib.optional cfg.postgres.enable "rybbit-postgres-migrate.service"
        ++ lib.optional cfg.geolocation.enable "rybbit-geolite2-update.service";
        wants = lib.optional cfg.geolocation.enable "rybbit-geolite2-update.service";
        requires =
          lib.optional cfg.clickhouse.enable "rybbit-clickhouse-init.service"
          ++ lib.optional cfg.postgres.enable "rybbit-postgres-migrate.service";

        environment = {
          NODE_ENV = "production";
          PORT = toString cfg.server.port;
          HOST = cfg.server.host;
          CLICKHOUSE_HOST = cfg.clickhouse.host;
          CLICKHOUSE_DB = cfg.clickhouse.database;
          POSTGRES_HOST = cfg.postgres.host;
          POSTGRES_PORT = toString cfg.postgres.port;
          POSTGRES_DB = cfg.postgres.database;
          POSTGRES_USER = cfg.postgres.user;
          BASE_URL = cfg.baseUrl;
          BETTER_AUTH_URL = cfg.baseUrl;
          DISABLE_SIGNUP = lib.boolToString cfg.settings.disableSignup;
          DISABLE_TELEMETRY = lib.boolToString cfg.settings.disableTelemetry;
        }
        // lib.optionalAttrs (cfg.settings.mapboxToken != null) {
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
        after = [
          "network.target"
          "rybbit-server.service"
        ];
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
      networking.firewall.allowedTCPPorts = [
        cfg.client.port
      ]
      ++ lib.optional cfg.nginx.enable 80
      ++ lib.optional cfg.nginx.enable 443;
    })
  ]);
}
