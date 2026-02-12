{
  lib,
  fetchFromGitHub,
  buildNpmPackage,
  runCommand,
  nodejs_20,
  makeWrapper,
  chromium,
  postgresql,
  inter,
  python3,
  pkg-config,
  zstd,
  cmake,
  stdenv,
}:

let
  # Version info - updated by GitHub Actions on new releases
  version = "2.3.1";
  rev = "9a010c845a9fc4e8c02a64a8bb9a584266d08595";
  hash = "sha256-LFieiYEoOeqXr+J7LMcmZT9QUPZWNcQM/NAX2Cllxus=";

  # npm dependency hashes - updated by GitHub Actions
  sharedHash = "sha256-AtGuK17i1yH4QFl/D7svtnQjHvxV81FKxFsZ9CWUbvo=";
  clientHash = "sha256-hZ42myygvJtYwOPVEst3ukso1nk75ooqyeOxaa4CL1k=";
  serverHash = "sha256-xl2j7TRWXo2Uy4S0aL8/g9DFcdrUdhJ2JwclRQQvusE=";

  # Fetch source from GitHub
  src = fetchFromGitHub {
    owner = "rybbit-io";
    repo = "rybbit";
    inherit rev hash;
  };

  # Shared types package
  shared = buildNpmPackage {
    pname = "rybbit-shared";
    version = "1.0.0";

    inherit src;
    sourceRoot = "${src.name}/shared";

    npmDepsHash = sharedHash;

    buildPhase = ''
      runHook preBuild
      npm run build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r dist $out/
      cp package.json $out/
      runHook postInstall
    '';

    meta = {
      description = "Shared types for Rybbit analytics";
      license = lib.licenses.agpl3Only;
    };
  };

  # Next.js client
  client = buildNpmPackage {
    pname = "rybbit-client";
    inherit version src;

    sourceRoot = "${src.name}/client";

    patches = [ ./patches/use-local-fonts.patch ];

    npmDepsHash = clientHash;
    nodejs = nodejs_20;
    npmFlags = [
      "--legacy-peer-deps"
    ];
    makeCacheWritable = true;

    # Use pre-built shared package and copy fonts
    preBuild = ''
      chmod -R u+w ../shared
      rm -rf ../shared/dist
      cp -r ${shared}/dist ../shared/

      # Copy Inter font for local font loading
      mkdir -p src/app/fonts
      cp "${inter}/share/fonts/truetype/InterVariable.ttf" src/app/fonts/Inter.ttf
    '';

    buildPhase = ''
      runHook preBuild
      export NODE_ENV=production
      npm run build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r .next/standalone/* $out/
      cp -r .next/static $out/.next/
      cp -r public $out/ 2>/dev/null || true
      runHook postInstall
    '';

    meta = {
      description = "Rybbit analytics client (Next.js)";
      license = lib.licenses.agpl3Only;
    };
  };

  # Fastify server
  server = buildNpmPackage {
    pname = "rybbit-server";
    inherit version src;

    sourceRoot = "${src.name}/server";

    npmDepsHash = serverHash;
    nodejs = nodejs_20;
    nativeBuildInputs = [
      makeWrapper
      python3
      pkg-config
      cmake
      stdenv.cc
    ];
    buildInputs = [ zstd ];
    npmFlags = [
      "--legacy-peer-deps"
      "--ignore-scripts"
    ];
    makeCacheWritable = true;
    dontUseCmakeConfigure = true;

    # Use pre-built shared package and rebuild native addons
    preBuild = ''
      chmod -R u+w ../shared
      rm -rf ../shared/dist
      cp -r ${shared}/dist ../shared/

      # Build @mongodb-js/zstd native addon (skipped by --ignore-scripts during npm install)
      chmod -R u+w node_modules/@mongodb-js/zstd
      pushd node_modules/@mongodb-js/zstd
      substituteInPlace binding.gyp \
        --replace-fail "'<(module_root_dir)/deps/zstd/out/lib/libzstd.a'" "'-lzstd'" \
        --replace-fail '"<(module_root_dir)/deps/zstd/lib"' '"${zstd.dev}/include"'
      HOME=$TMPDIR node ${nodejs_20}/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js rebuild
      popd
    '';

    buildPhase = ''
      runHook preBuild
      export NODE_ENV=production
      export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1
      npm run build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/rybbit-server $out/bin $out/lib/shared
      cp -r dist $out/lib/rybbit-server/
      cp -r node_modules $out/lib/rybbit-server/
      cp package.json $out/lib/rybbit-server/

      # Copy shared package and fix symlink
      cp -r ${shared}/* $out/lib/shared/
      rm -f $out/lib/rybbit-server/node_modules/@rybbit/shared
      ln -s $out/lib/shared $out/lib/rybbit-server/node_modules/@rybbit/shared

      makeWrapper ${nodejs_20}/bin/node $out/bin/rybbit-server \
        --add-flags "$out/lib/rybbit-server/dist/index.js" \
        --set PUPPETEER_EXECUTABLE_PATH "${chromium}/bin/chromium" \
        --set PUPPETEER_SKIP_CHROMIUM_DOWNLOAD "1" \
        --prefix PATH : "${lib.makeBinPath [ postgresql ]}"

      runHook postInstall
    '';

    meta = {
      description = "Rybbit analytics server (Fastify)";
      license = lib.licenses.agpl3Only;
      mainProgram = "rybbit-server";
    };
  };
in
{
  inherit shared client server;

  # Combined package with both client and server
  default = runCommand "rybbit-${version}" {
    nativeBuildInputs = [ makeWrapper ];
    meta = {
      description = "Rybbit - Privacy-focused analytics platform";
      homepage = "https://github.com/rybbit-io/rybbit";
      license = lib.licenses.agpl3Only;
      mainProgram = "rybbit-server";
      platforms = lib.platforms.linux;
    };
  } ''
    mkdir -p $out/bin $out/lib

    # Copy client (Next.js standalone)
    cp -r ${client} $out/lib/client

    # Copy server
    cp -r ${server}/lib/* $out/lib/

    # Create server wrapper
    makeWrapper ${nodejs_20}/bin/node $out/bin/rybbit-server \
      --add-flags "$out/lib/rybbit-server/dist/index.js" \
      --set PUPPETEER_EXECUTABLE_PATH "${chromium}/bin/chromium" \
      --set PUPPETEER_SKIP_CHROMIUM_DOWNLOAD "1" \
      --prefix PATH : "${lib.makeBinPath [ postgresql ]}"

    # Create client wrapper
    makeWrapper ${nodejs_20}/bin/node $out/bin/rybbit-client \
      --add-flags "$out/lib/client/server.js" \
      --set PORT "3002" \
      --set HOSTNAME "0.0.0.0"
  '';
}
