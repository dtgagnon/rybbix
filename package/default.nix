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
  version = "2.4.0";
  rev = "ac5b3a3343252e2bd48d7ac5345266287cd39980";
  hash = "sha256-ZwdQ4pz9CUajD/G+MEXPhRzpwkOWJ1rJLHKD6APOw0w=";

  # npm dependency hashes - updated by GitHub Actions
  sharedHash = "sha256-AtGuK17i1yH4QFl/D7svtnQjHvxV81FKxFsZ9CWUbvo=";
  clientHash = "sha256-aFFBmvSAcTHG9IoVQpiBqXfn1K4k8Na/KW+6PNWPgSg=";
  serverHash = "sha256-QSjq+xITDXDSxhdNDQwLju3vxtKujbihnSgrAHk8yKc=";

  # Fetch source from GitHub
  src = fetchFromGitHub {
    owner = "rybbit-io";
    repo = "rybbit";
    inherit rev hash;
  };

  # Shared types package
  shared = buildNpmPackage {
    pname = "rybbit-shared";
    version = "2.4.0";

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
      # Use /. instead of /* to include hidden dirs (.next from standalone)
      cp -r .next/standalone/. $out/
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

    postBuild = ''
      # Patch hardcoded server bind to read from PORT/HOST env vars
      substituteInPlace dist/index.js \
        --replace-fail \
          'await server.listen({ port: 3001, host: "0.0.0.0" })' \
          'await server.listen({ port: parseInt(process.env.PORT || "3001"), host: process.env.HOST || "0.0.0.0" })' \
        --replace-fail \
          'server.log.info("Server is listening on http://0.0.0.0:3001")' \
          'server.log.info("Server is listening on http://" + (process.env.HOST || "0.0.0.0") + ":" + (process.env.PORT || "3001"))'
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
        --set-default PUPPETEER_EXECUTABLE_PATH "${chromium}/bin/chromium" \
        --set-default PUPPETEER_SKIP_CHROMIUM_DOWNLOAD "1" \
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

    # Create server wrapper (use --set-default so module environment takes precedence)
    makeWrapper ${nodejs_20}/bin/node $out/bin/rybbit-server \
      --add-flags "$out/lib/rybbit-server/dist/index.js" \
      --set-default PUPPETEER_EXECUTABLE_PATH "${chromium}/bin/chromium" \
      --set-default PUPPETEER_SKIP_CHROMIUM_DOWNLOAD "1" \
      --prefix PATH : "${lib.makeBinPath [ postgresql ]}"

    # Create client wrapper (use --set-default so module environment takes precedence)
    # --chdir ensures Next.js finds .next/ relative to server.js
    makeWrapper ${nodejs_20}/bin/node $out/bin/rybbit-client \
      --add-flags "$out/lib/client/server.js" \
      --chdir "$out/lib/client" \
      --set-default PORT "3002" \
      --set-default HOSTNAME "0.0.0.0"
  '';
}
