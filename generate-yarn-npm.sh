#!/usr/bin/env bash
set -euo pipefail

# Default values
HOME_PATH="${HOME_PATH:-/home/ubuntu}"
NPM_ACCESS_TOKEN="${NPM_ACCESS_TOKEN:?Error: NPM_ACCESS_TOKEN is required}"

# Parse flags
# SCOPES=() # TEMPORARILY DISABLED FOR GLOBAL SCOPE
while getopts "s:f:h" opt; do
  case $opt in
    s) HOME_PATH="$OPTARG" ;;
    # f) SCOPES+=("$OPTARG") ;; # TEMPORARILY DISABLED FOR GLOBAL SCOPE
    h) echo "Usage: $0 [-s HOME_PATH]"
       echo "  -s: Set HOME_PATH (default: $HOME_PATH)"
       # echo "  -f: Add scope (orochi-network, zkdb). Can repeat." # TEMPORARILY DISABLED
       echo "Examples:"
       echo "  $0 -s /custom/home"
       # echo "  $0 -f orochi-network -f zkdb" # TEMPORARILY DISABLED
       exit 0 ;;
    ?) echo "Invalid option -$OPTARG" >&2; exit 1 ;;
  esac
done

# TEMPORARILY DISABLED - Validate scopes if provided
# if [ ${#SCOPES[@]} -eq 0 ]; then
#   echo "Error: At least one scope required (-f orochi-network or -f zkdb)" >&2
#   exit 1
# fi

# Create .npmrc
echo "//registry.npmjs.org/:_authToken=${NPM_ACCESS_TOKEN}" > "${HOME_PATH}/.npmrc"

# TEMPORARILY USING GLOBAL SCOPE
# Create .yarnrc.yml with global npm auth
cat > "${HOME_PATH}/.yarnrc.yml" << EOF
enableTelemetry: false
nodeLinker: node-modules
npmAuthToken: "${NPM_ACCESS_TOKEN}"
npmRegistryServer: "https://registry.npmjs.org"
npmAlwaysAuth: true
EOF

# TEMPORARILY COMMENTED OUT - Scope-specific configuration
# # Create .yarnrc.yml base
# cat > "${HOME_PATH}/.yarnrc.yml" << EOF
# enableTelemetry: false
# nodeLinker: node-modules
# npmScopes:
# EOF
#
# # Add scopes dynamically
# for SCOPE in "${SCOPES[@]}"; do
#   case "$SCOPE" in
#     orochi-network|zkdb)
#       cat >> "${HOME_PATH}/.yarnrc.yml" << EOF
#   ${SCOPE}:
#     npmRegistryServer: "https://registry.npmjs.org"
#     npmAlwaysAuth: true
#     npmAuthToken: "${NPM_ACCESS_TOKEN}"
# EOF
#       ;;
#     *)
#       echo "Error: Invalid scope '$SCOPE'. Use orochi-network or zkdb" >&2
#       exit 1
#       ;;
#   esac
# done

echo "✅ Configured ${HOME_PATH}/.npmrc and .yarnrc.yml with global npm access token"
