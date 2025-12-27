#!/bin/bash
set -e

# Reusable Yarn setup script for CI/CD pipelines
# Usage: curl -sL <url>/yarn-setup.sh | bash -s -- [options]
#
# Options:
#   --skip-corepack    Skip corepack enable
#   --skip-install     Skip yarn install
#   --lint             Run yarn lint after install
#   --build            Run yarn build after install
#
# Required environment variable:
#   NPM_ACCESS_TOKEN   NPM token for private packages

# Parse arguments
SKIP_COREPACK=false
SKIP_INSTALL=false
RUN_LINT=false
RUN_BUILD=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-corepack) SKIP_COREPACK=true; shift ;;
    --skip-install) SKIP_INSTALL=true; shift ;;
    --lint) RUN_LINT=true; shift ;;
    --build) RUN_BUILD=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Enable corepack
if [ "$SKIP_COREPACK" = false ]; then
  echo "Enabling corepack..."
  corepack enable
fi

# Check for NPM token
if [ -z "$NPM_ACCESS_TOKEN" ]; then
  echo "Warning: NPM_ACCESS_TOKEN is not set. Private packages may fail to install."
fi

# Create .yarnrc.yml
echo "Configuring Yarn..."
cat > .yarnrc.yml <<YAML
enableTelemetry: false
nodeLinker: node-modules
npmScopes:
  orochi-network:
    npmRegistryServer: "https://registry.npmjs.org"
    npmAlwaysAuth: true
npmAuthToken: \${NPM_ACCESS_TOKEN}
YAML

# Install dependencies
if [ "$SKIP_INSTALL" = false ]; then
  echo "Installing dependencies..."
  yarn install
fi

# Run lint
if [ "$RUN_LINT" = true ]; then
  echo "Running lint..."
  yarn lint
fi

# Run build
if [ "$RUN_BUILD" = true ]; then
  echo "Running build..."
  yarn build
fi

echo "Yarn setup complete!"
