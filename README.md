# Rybbix - Nix Packaging for Rybbit

Nix flake providing packages and NixOS module for [Rybbit](https://github.com/rybbit-io/rybbit), a privacy-focused analytics platform.

## Features

- **Packages**: `rybbit-client`, `rybbit-server`, `rybbit-shared`, and combined `default` package
- **NixOS Module**: Declarative service configuration with ClickHouse and PostgreSQL integration
- **Auto-sync**: GitHub Actions automatically updates when upstream releases new versions

## Quick Start

### NixOS Module

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rybbit.url = "github:dtgagnon/rybbix";
  };

  outputs = { nixpkgs, rybbit, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        rybbit.nixosModules.default
        {
          services.rybbit = {
            enable = true;
            domain = "analytics.example.com";
            secretsFile = "/run/secrets/rybbit"; # Must contain BETTER_AUTH_SECRET
            settings.disableSignup = true;
            nginx.enable = true;
          };
        }
      ];
    };
  };
}
```

### Secrets File

The `secretsFile` should contain environment variables:

```bash
BETTER_AUTH_SECRET=your-random-secret-here
# Optional:
CLICKHOUSE_PASSWORD=your-clickhouse-password
POSTGRES_PASSWORD=your-postgres-password
MAPBOX_TOKEN=your-mapbox-token
```

### Standalone Package

```bash
# Run directly
nix run github:dtgagnon/rybbix

# Build
nix build github:dtgagnon/rybbix

# Enter dev shell
nix develop github:dtgagnon/rybbix
```

## Module Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable Rybbit service |
| `domain` | string | `null` | Public domain name |
| `secretsFile` | path | required | Path to secrets file |
| `server.port` | int | `3001` | Backend API port |
| `client.port` | int | `3002` | Frontend port |
| `clickhouse.enable` | bool | `true` | Enable local ClickHouse |
| `postgres.enable` | bool | `true` | Enable local PostgreSQL |
| `settings.disableSignup` | bool | `false` | Disable new registrations |
| `settings.disableTelemetry` | bool | `true` | Disable telemetry |
| `nginx.enable` | bool | `false` | Configure nginx reverse proxy |
| `openFirewall` | bool | `false` | Open firewall ports |

## Development

```bash
# Update to latest upstream release
nix run .#update

# Build and test
nix build
nix flake check
```

## License

This Nix packaging is provided under the same license as Rybbit (AGPL-3.0).
