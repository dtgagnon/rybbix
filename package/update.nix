# Script to update version, rev, hash, and npm dependency hashes
# Run with: nix run .#update
{
  writeShellScript,
  prefetch-npm-deps,
  nix-prefetch-github,
  gnused,
  curl,
  jq,
}:

{
  type = "app";
  program = toString (writeShellScript "update-rybbit" ''
    set -euo pipefail
    cd "$(git rev-parse --show-toplevel)"

    echo "Fetching latest release from GitHub..."
    LATEST=$(${curl}/bin/curl -s https://api.github.com/repos/rybbit-io/rybbit/releases/latest | ${jq}/bin/jq -r '.tag_name')

    if [ -z "$LATEST" ] || [ "$LATEST" = "null" ]; then
      echo "Error: Could not fetch latest release"
      exit 1
    fi

    echo "Latest release: $LATEST"

    # Get current version from package/default.nix
    CURRENT=$(grep 'version = "' package/default.nix | head -1 | sed 's/.*version = "\([^"]*\)".*/\1/')
    echo "Current version: $CURRENT"

    if [ "v$CURRENT" = "$LATEST" ]; then
      echo "Already up to date!"
      exit 0
    fi

    NEW_VERSION=''${LATEST#v}
    echo "Updating to version: $NEW_VERSION"

    echo "Prefetching source..."
    PREFETCH=$(${nix-prefetch-github}/bin/nix-prefetch-github rybbit-io rybbit --rev "$LATEST")
    NEW_REV=$(echo "$PREFETCH" | ${jq}/bin/jq -r '.rev')
    NEW_HASH=$(echo "$PREFETCH" | ${jq}/bin/jq -r '.hash')

    echo "  rev: $NEW_REV"
    echo "  hash: $NEW_HASH"

    # Update version, rev, and hash in package/default.nix
    ${gnused}/bin/sed -i \
      -e "s|version = \".*\";|version = \"$NEW_VERSION\";|" \
      -e "s|rev = \".*\";|rev = \"$NEW_REV\";|" \
      -e "s|hash = \"sha256-.*\";|hash = \"$NEW_HASH\";|" \
      package/default.nix

    echo "Fetching source to update npm hashes..."
    TMPDIR=$(mktemp -d)
    trap "rm -rf $TMPDIR" EXIT

    ${curl}/bin/curl -sL "https://github.com/rybbit-io/rybbit/archive/$LATEST.tar.gz" | tar -xz -C "$TMPDIR"
    SRCDIR="$TMPDIR/rybbit-$NEW_VERSION"

    echo "Prefetching npm hashes..."
    SHARED_HASH=$(${prefetch-npm-deps}/bin/prefetch-npm-deps "$SRCDIR/shared/package-lock.json" 2>/dev/null)
    CLIENT_HASH=$(${prefetch-npm-deps}/bin/prefetch-npm-deps "$SRCDIR/client/package-lock.json" 2>/dev/null)
    SERVER_HASH=$(${prefetch-npm-deps}/bin/prefetch-npm-deps "$SRCDIR/server/package-lock.json" 2>/dev/null)

    echo "  sharedHash: $SHARED_HASH"
    echo "  clientHash: $CLIENT_HASH"
    echo "  serverHash: $SERVER_HASH"

    # Update npm hashes
    ${gnused}/bin/sed -i \
      -e "s|sharedHash = \"sha256-.*\";|sharedHash = \"$SHARED_HASH\";|" \
      -e "s|clientHash = \"sha256-.*\";|clientHash = \"$CLIENT_HASH\";|" \
      -e "s|serverHash = \"sha256-.*\";|serverHash = \"$SERVER_HASH\";|" \
      package/default.nix

    echo ""
    echo "Updated package/default.nix to version $NEW_VERSION"
    echo "Please verify the build works: nix build"
    echo "Then commit: git add -A && git commit -m 'chore: update to v$NEW_VERSION'"
  '');
}
