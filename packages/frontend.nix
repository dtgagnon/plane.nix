{ pkgs, name, src, ... }:

# Simple wrapper for Plane frontend apps - development mode until proper build is implemented

let
  # Convert app name to binary name (e.g., "plane-web" -> "web")
  binName = builtins.replaceStrings ["plane-"] [""] name;

in pkgs.stdenv.mkDerivation {
  pname = name;
  version = "0.26.1";

  # Use the specific app source directory
  src = src;

  # Build inputs
  nativeBuildInputs = with pkgs; [
    nodejs_20   # modern Node.js for latest Next.js
    yarn
    jq          # JSON manipulation if needed
  ];

  # Don't run tests during build
  doCheck = false;

  # Configure phase - prepare build environment
  configurePhase = ''
    export HOME=$TMPDIR

    echo "Preparing build environment for ${name}..."

    # Copy source to working directory for isolation
    cp -r $src/* .

    # Ensure node_modules structure for @plane workspace packages
    mkdir -p node_modules/@plane
    for pkg in constants editor hooks i18n propel types ui utils; do
      if [ ! -d "node_modules/@plane/$pkg" ]; then
        echo "Creating stub package for @plane/$pkg"
        mkdir -p node_modules/@plane/$pkg
        cat > node_modules/@plane/$pkg/package.json << EOF
{
  "name": "@plane/$pkg",
  "version": "0.1.0",
  "main": "index.js"
}
EOF
        echo "// Stub for @plane/$pkg" > node_modules/@plane/$pkg/index.js
      fi
    done

    # Prevent Yarn from hitting the network during build
    echo "offline true" > .yarnrc
    touch yarn.lock || true
  '';

  # Build phase - prepare for standalone Next.js build
  buildPhase = ''
    echo "Preparing ${name} for production deployment..."

    # Create node_modules directory with stub packages for @plane/* dependencies
    mkdir -p node_modules/@plane

    # Create stub packages for all @plane/* dependencies
    for pkg in constants editor hooks i18n propel types ui utils; do
      echo "Creating stub package for @plane/$pkg"
      mkdir -p node_modules/@plane/$pkg
      # Create minimal package.json for the stub
      cat > node_modules/@plane/$pkg/package.json << EOF
{
  "name": "@plane/$pkg",
  "version": "0.1.0",
  "main": "index.js"
}
EOF
      # Create minimal index.js
      echo "// Stub for @plane/$pkg" > node_modules/@plane/$pkg/index.js
    done

    # Create yarn.lock file to prevent yarn from trying to fetch dependencies
    touch yarn.lock

    # Modify next.config.js to use standalone output if it exists
    if [ -f "$src/next.config.js" ]; then
      cp $src/next.config.js ./next.config.js.orig
      cat > next.config.js << EOF
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
  // Copy original settings
  reactStrictMode: true,
  swcMinify: true,
}

module.exports = nextConfig
EOF
    else
      echo "No next.config.js found, creating one"
      cat > next.config.js << EOF
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
  reactStrictMode: true,
  swcMinify: true,
}

module.exports = nextConfig
EOF
    fi

    echo "Building Next.js app in standalone mode..."
    export NODE_ENV=production
    ${pkgs.nodejs_20}/bin/npx --no-install next build || {
      echo "Initial build failed; attempting yarn install offline..."
      ${pkgs.yarn}/bin/yarn --offline --frozen-lockfile install || true
      ${pkgs.nodejs_20}/bin/npx --no-install next build
    }
  '';

  installPhase = ''
    # Create directory structure
    mkdir -p $out/bin $out/share/${name} $out/share/${name}-standalone

    # Copy the standalone build output (contains everything needed to run)
    if [ -d ".next/standalone" ]; then
      echo "Copying Next.js standalone build to $out/share/${name}-standalone/"
      cp -r .next/standalone/* $out/share/${name}-standalone/

      # Copy static assets and public files
      mkdir -p $out/share/${name}-standalone/public
      if [ -d ".next/static" ]; then
        mkdir -p $out/share/${name}-standalone/.next/static
        cp -r .next/static $out/share/${name}-standalone/.next/
      fi
      if [ -d "public" ]; then
        cp -r public/* $out/share/${name}-standalone/public/
      fi
    else
      echo "WARNING: No standalone build output found. Falling back to source copy."
      # Copy the source as fallback
      cp -r $src/* $out/share/${name}/

      # Copy node_modules if they exist
      if [ -d "node_modules" ]; then
        echo "Copying node_modules to $out/share/${name}/"
        cp -r node_modules $out/share/${name}/
      fi
    fi

    # Create startup script that runs the production server
    cat > $out/bin/plane-${binName} << EOF

#!/usr/bin/env bash
set -e

# Set default port based on app
case "${binName}" in
  "web")
    DEFAULT_PORT=3000
    ;;
  "space")
    DEFAULT_PORT=3002
    ;;
  "admin")
    DEFAULT_PORT=3001
    ;;
  "live")
    DEFAULT_PORT=3003
    ;;
  *)
    DEFAULT_PORT=3000
    ;;
esac

PORT="''${PORT:-$DEFAULT_PORT}"
export PORT

echo "Starting ${name} development server on port ''$PORT..."
echo "Source directory: $out/share/${name}/"

# Check if standalone build exists and use it
if [ -d "${builtins.toString "$out"}/share/${name}-standalone" ]; then
  echo "Starting production server for ${name} on port $PORT..."
  cd ${builtins.toString "$out"}/share/${name}-standalone/
  # Set port for Node.js server
  export PORT=$PORT
  # Run the standalone server
  exec ${pkgs.nodejs}/bin/node server.js
else
  echo "WARNING: Standalone build not found, falling back to development mode."
  # Navigate to source directory
  cd ${builtins.toString "$out"}/share/${name}/

  # Check if dependencies are installed
  if [ ! -d "node_modules" ]; then
    echo "Installing dependencies..."
    ${pkgs.yarn}/bin/yarn install --frozen-lockfile || {
      echo "Warning: Failed to install dependencies with --frozen-lockfile, trying without..."
      ${pkgs.yarn}/bin/yarn install
    }
  else
    echo "Node modules directory found, skipping dependency installation"
  fi

  # Fall back to dev server
  echo "Starting Next.js development server on port $PORT..."
  ${pkgs.nodejs}/bin/npx next dev --port $PORT
fi
EOF
    chmod +x $out/bin/plane-${binName}

    # Create compatibility symlink with short name
    ln -s $out/bin/plane-${binName} $out/bin/${binName}
  '';

  meta = with pkgs.lib; {
    description = "Plane ${name} Next.js frontend (source only)";
    homepage = "https://plane.so";
    license = licenses.agpl3Plus;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}
