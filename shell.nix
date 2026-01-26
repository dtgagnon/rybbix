{ pkgs, ... }:

pkgs.mkShell {
  packages = with pkgs; [
    # Node.js runtime
    nodejs_20

    # Database clients
    postgresql_16

    # Puppeteer runtime dependency
    chromium

    # Useful dev tools
    jq
  ];

  shellHook = ''
    # Puppeteer configuration
    export PUPPETEER_EXECUTABLE_PATH="${pkgs.chromium}/bin/chromium"
    export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1

    # Ensure node_modules/.bin is in PATH for local tooling
    export PATH="$PWD/node_modules/.bin:$PWD/client/node_modules/.bin:$PWD/server/node_modules/.bin:$PATH"
  '';
}
