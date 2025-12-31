#!/usr/bin/env bash
set -euo pipefail

# Default values
HOME_PATH="${HOME_PATH:-/home/ubuntu}"
NPM_ACCESS_TOKEN="${NPM_ACCESS_TOKEN:?Error: NPM_ACCESS_TOKEN is required}"

# Parse flags
SCOPES=()
while getopts "s:f:h" opt; do
  case $opt in
    s) HOME_PATH="$OPTARG" ;;
    f) SCOPES+=("$OPTARG") ;;
    h) echo "Usage: $0 [-s HOME_PATH] [-f SCOPE]..."
       echo "  -s: Set HOME_PATH (default: $HOME_PATH)"
       echo "  -f: Add scope (orochi-network, zkdb). Can repeat."
       echo "Examples:"
       echo "  $0 -s /custom/home -f orochi-network"
       echo "  $0 -f orochi-network -f zkdb"
       exit 0 ;;
    ?) echo "Invalid option -$OPTARG" >&2; exit 1 ;;
  esac
done

# Validate scopes if provided
if [ ${#SCOPES[@]} -eq 0 ]; then
  echo "Error: At least one scope required (-f orochi-network or -f zkdb)" >&2
  exit 1
fi

# Create .npmrc
echo "//registry.npmjs.org/:_authToken=${NPM_ACCESS_TOKEN}" > "${HOME_PATH}/.npmrc"

# Create .yarnrc.yml base
cat > "${HOME_PATH}/.yarnrc.yml" << EOF
enableTelemetry: false
nodeLinker: node-modules
npmScopes:
EOF

# Add scopes dynamically
for SCOPE in "${SCOPES[@]}"; do
  case "$SCOPE" in
    orochi-network|zkdb)
      cat >> "${HOME_PATH}/.yarnrc.yml" << EOF
  ${SCOPE}:
    npmRegistryServer: "https://registry.npmjs.org"
    npmAlwaysAuth: true
    npmAuthToken: "${NPM_ACCESS_TOKEN}"
EOF
      ;;
    *)
      echo "Error: Invalid scope '$SCOPE'. Use orochi-network or zkdb" >&2
      exit 1
      ;;
  esac
done

echo "✅ Configured ${HOME_PATH}/.npmrc and .yarnrc.yml for scopes: ${SCOPES[*]}"
