{ pkgs
, srcRoot        # workspace root containing package.json & yarn.lock
, appDir         # directory of the Next.js app relative to srcRoot
, appName        # e.g. "plane-web"
, version ? "0.26.1"
, dream2nix ? null  # Not used in this simplified version
}:

# Build a standalone Next.js app with buildNpmPackage.
# We directly use pkgs.buildNpmPackage which is available in nixpkgs-unstable.

let
  binName = builtins.replaceStrings ["plane-"] [""] appName;
  # Convenience: path to the app inside the build directory
  appPath = "${srcRoot}/${appDir}";

in pkgs.buildNpmPackage rec {
  pname       = appName;
  inherit version;
  src         = srcRoot;
  npmDepsHash = "";
  
  # Ensure modern Node.js for Next.js 14
  nativeBuildInputs = [ pkgs.nodejs_20 ];
  
  # Set up project-specific config
  NODE_ENV = "production";
  
  # Use nodejs_20 for building
  nodejs = pkgs.nodejs_20;
  
  # Set package workspaces directory to subdirectory
  workspaceDirectory = appDir;
  
  # Build Next.js standalone app
  buildPhase = ''
    export HOME=$TMPDIR
    cd "${appDir}"
    echo "Running next build for ${appName}..."
    npm run build
    
  '';
  
  # Custom installation to create a standalone Next.js app
  installPhase = ''
    # Create our output directory structure
    mkdir -p $out/share/${appName}-standalone
    mkdir -p $out/bin
    
    cd "${appDir}"
    
    if [ ! -d ".next/standalone" ]; then
      echo "ERROR: .next/standalone directory not found – ensure output='standalone' is set in next.config.js" >&2
      exit 1
    fi
    
    # Copy the standalone build and static assets
    cp -R .next/standalone/* $out/share/${appName}-standalone/
    
    # Copy additional static assets that standalone build expects at runtime
    if [ -d ".next/static" ]; then
      mkdir -p $out/share/${appName}-standalone/.next/
      cp -R .next/static $out/share/${appName}-standalone/.next/
    fi
  
    if [ -d "public" ]; then
      cp -R public $out/share/${appName}-standalone/
    fi
  
    # Create launcher script
    cat > $out/bin/plane-${binName} <<EOF
#!/usr/bin/env bash
set -euo pipefail
PORT="\${PORT:-3000}"
export PORT
cd $out/share/${appName}-standalone
exec ${pkgs.nodejs_20}/bin/node server.js
EOF
    chmod +x $out/bin/plane-${binName}
    ln -s $out/bin/plane-${binName} $out/bin/${binName}
  '';

  meta = with pkgs.lib; {
    description = "Plane ${appName} Next.js frontend (standalone build)";
    homepage    = "https://plane.so";
    license     = licenses.agpl3Plus;
    maintainers = [];
    platforms   = platforms.linux;
    mainProgram = "plane-${binName}";
  };
}
