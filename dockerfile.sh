#!/usr/bin/env bash

set -e

# If base revision was set, we are going to use given revision
# BASE_REVISION="db70372fd4ecbc111cb195ebe249809d8f0768a3" curl -sL https://...
BASE_REVISION="${BASE_REVISION:-main}"
BASE_URL="https://raw.githubusercontent.com/orochi-network/dev-off/${BASE_REVISION}"

# ============================================================================
# Default values
# ============================================================================
BUILDER_BASE_IMAGE="orochinetwork/ubuntu:node"
BUILDER_USER="ubuntu"
BUILDER_GROUP="ubuntu"
BUILDER_WORKDIR="/home/ubuntu/app"

RUNNER_BASE_IMAGE="node:24-alpine"
RUNNER_USER="node"
RUNNER_GROUP="node"
RUNNER_WORKDIR="/home/node/app"

# ============================================================================
# CLI variables
# ============================================================================
DOCKER_FILE=()
DOCKER_COMMAND="[\"npm\", \"start\"]"
BUILD_COMMAND=""
RUNNER_COMMANDS=()
RUNNER_IMAGE=""
DRY_RUN=false
EXTRA_ENV=""
EXPOSE_PORT=""

show_help() {
  cat <<EOF
Usage: ./dockerfile.sh [OPTIONS]

Generate Dockerfile for Node.js projects with customizable runner stages.

Options:
  -t, --template TYPE        Template type: node, nginx, next, rust
  -c, --command CMD          CMD to run (default: ["npm", "start"])
  -f, --file FILE            File/directory to copy (can be used multiple times)
                             Format: "file" or "src;dst" for custom paths
  -b, --build CMD            Custom build command (default: uses build-prod.sh)
  -r, --runner-image IMAGE   Custom runner image (default: node:24-alpine for node/next)
  --run CMD                  RUN command to execute in runner stage (repeatable)
  --dry-run                  Print Dockerfile to stdout instead of writing to file
  -l, --list                 List all templates with their details
  -h, --help                 Show this help message

File Copy Behavior:
  Single argument (-f file.txt):
    Copies from builder workdir to runner workdir
    Example: -f package.json
    Result: COPY --from=builder /home/ubuntu/app/package.json /home/node/app/package.json

  Two arguments (-f "src;dst"):
    Uses full paths for both source and destination
    Example: -f "nginx.conf;/etc/nginx/nginx.conf"
    Result: COPY --from=builder nginx.conf /etc/nginx/nginx.conf

Examples:
  # Basic Next.js project
  ./dockerfile.sh -t next -f .next -f package.json -f node_modules -f public

  # Custom runner image and CMD
  ./dockerfile.sh -t node -r node:24-trixie-slim -f build -f package.json \\
    -c '["node", "server.js"]'

  # Nginx with custom config path
  ./dockerfile.sh -t nginx -f "nginx.conf;/etc/nginx/conf.d/default.conf"

  # With post-copy RUN command and dry-run
  ./dockerfile.sh -t next -f .next -f package.json \\
    --run 'chmod +x /home/node/app/run-service.sh' --dry-run
EOF
}

list_templates() {
  cat <<EOF
Available templates:

  node    - Node.js application
           Builder: orochinetwork/ubuntu:node
           Runner: node:24-alpine (default)
           Files to copy: package.json, build/, node_modules/, etc.

  next    - Next.js application
           Builder: orochinetwork/ubuntu:node
           Runner: node:24-alpine (default, with NEXT_TELEMETRY_DISABLED=1)
           Files to copy: .next/, package.json, node_modules/, public/, next.config.*, etc.

  nginx   - Static website (React, Vue, or HTML/CSS/JS)
           Builder: orochinetwork/ubuntu:node
           Runner: nginx:stable-alpine
           Build output: build/ directory

  rust    - Rust application (coming soon)
EOF
}

while [[ $# -gt 0 ]]; do
  case $1 in
  -h | --help)
    show_help
    exit 0
    ;;
  -l | --list)
    list_templates
    exit 0
    ;;
  -t | --template)
    DOCKER_TEMPLATE="$2"
    shift # Past argument
    shift # Past value
    ;;
  -c | --command)
    DOCKER_COMMAND=${2:-${DOCKER_COMMAND}}
    shift
    shift
    ;;
  -f | --file)
    DOCKER_FILE+=("$2")
    shift
    shift
    ;;
  -b | --build)
    BUILD_COMMAND="$2"
    shift
    shift
    ;;
  -r | --runner-image)
    RUNNER_IMAGE="$2"
    shift
    shift
    ;;
  --run)
    RUNNER_COMMANDS+=("$2")
    shift
    shift
    ;;
  --dry-run)
    DRY_RUN=true
    DF_BUFFER="/dev/stdout"
    shift
    ;;
  *)
    UNKNOWN_ARGS+=("$1") # Save unknown ones for later
    shift
    ;;
  esac
done

CWD=$(pwd)
if [[ "$DRY_RUN" == false ]]; then
  DF_BUFFER="${CWD}/Dockerfile"
fi

check_file() {
  if [[ ! -f "$1" ]]; then
    echo "File $1 was not existed"
    exit 1
  fi
}

# ============================================================================
# Template-specific overrides
# ============================================================================
case $DOCKER_TEMPLATE in
node)
  RUNNER_BASE_IMAGE="${RUNNER_IMAGE:-node:24-alpine}"
  ;;
nginx)
  RUNNER_BASE_IMAGE="nginx:stable-alpine"
  RUNNER_USER="nginx"
  RUNNER_GROUP="nginx"
  RUNNER_WORKDIR="/usr/share/nginx/html"
  DOCKER_COMMAND="[\"nginx\", \"-g\", \"daemon off;\"]"
  EXPOSE_PORT=$'\nEXPOSE 80'
  # For nginx, if no files specified, use default build directory
  if [[ ${#DOCKER_FILE[@]} -eq 0 ]]; then
    DOCKER_FILE=("build;/usr/share/nginx/html")
  fi
  ;;
next)
  RUNNER_BASE_IMAGE="${RUNNER_IMAGE:-node:24-alpine}"
  EXTRA_ENV=$'\nENV NEXT_TELEMETRY_DISABLED=1'
  ;;
esac

# ============================================================================
# Generate COPY instructions
# ============================================================================
generate_copy_instructions() {
  local first=true

  for item in "${DOCKER_FILE[@]}"; do
    if [[ "$item" == *";"* ]]; then
      # Two arguments: full paths
      IFS=';' read -r src dst <<< "$item"
      echo "Copy file (custom): ${src} → ${dst}" >&2
      echo "COPY --from=builder --chown=${RUNNER_USER}:${RUNNER_GROUP} ${src} ${dst}"
    else
      # One argument: copy from builder workdir to runner workdir
      echo "Copy file: ${item}" >&2
      echo "COPY --from=builder --chown=${RUNNER_USER}:${RUNNER_GROUP} ${BUILDER_WORKDIR}/${item} ./${item}"
    fi
  done
}

# ============================================================================
# Generate runner commands
# ============================================================================
generate_runner_commands() {
  if [[ ${#RUNNER_COMMANDS[@]} -gt 0 ]]; then
    echo ""
    for cmd in "${RUNNER_COMMANDS[@]}"; do
      echo "RUN ${cmd}"
    done
  fi
}

# ============================================================================
# Generate build command
# ============================================================================
generate_build_command() {
  if [[ -n "$BUILD_COMMAND" ]]; then
    echo "Using custom build command" >&2
    echo "# Run custom build command"
    echo "RUN $BUILD_COMMAND"
  elif [[ -f "$CWD/scripts/build-prod.sh" ]]; then
    echo "Using local build-prod.sh" >&2
    echo "# Run build-prod.sh"
    echo "RUN chmod +x scripts/build-prod.sh && \\"
    echo "  ./scripts/build-prod.sh"
  else
    echo "Using remote build script" >&2
    local build_script="${BASE_URL}/scripts/build-prod-${DOCKER_TEMPLATE}.sh"
    echo "# Run default build script"
    echo "RUN curl -sL ${build_script} | bash -eo pipefail"
  fi
}

# ============================================================================
# Process template
# ============================================================================
echo "Generating Dockerfile using template: ${DOCKER_TEMPLATE}"

TEMPLATE_FILE="${CWD}/Dockerfile.template"
if [[ ! -f "$TEMPLATE_FILE" ]]; then
  # Try to download from remote
  echo "Downloading template from ${BASE_URL}/Dockerfile.template"
  curl -sL "${BASE_URL}/Dockerfile.template" -o /tmp/Dockerfile.template
  TEMPLATE_FILE="/tmp/Dockerfile.template"
fi

# Write multi-line content to temp files
generate_copy_instructions > /tmp/copy_instructions.txt
generate_runner_commands > /tmp/runner_commands.txt
generate_build_command > /tmp/build_command.txt

# Read template and replace simple variables using perl
perl -pe "
  s|\{\{builder_base_image\}\}|${BUILDER_BASE_IMAGE}|g;
  s|\{\{builder_user\}\}|${BUILDER_USER}|g;
  s|\{\{builder_group\}\}|${BUILDER_GROUP}|g;
  s|\{\{runner_base_image\}\}|${RUNNER_BASE_IMAGE}|g;
  s|\{\{runner_user\}\}|${RUNNER_USER}|g;
  s|\{\{runner_group\}\}|${RUNNER_GROUP}|g;
" "$TEMPLATE_FILE" | \
perl -pe "s|\{\{extra_env\}\}|${EXTRA_ENV}|g" | \
perl -pe "s|\{\{expose_port\}\}|${EXPOSE_PORT}|g" | \
perl -pe "s|\{\{cmd\}\}|${DOCKER_COMMAND}|g" > /tmp/dockerfile_partial.txt

# Now replace multi-line placeholders by reading the line and replacing when we see the marker
while IFS= read -r line; do
  if [[ "$line" == "{{build_command}}" ]]; then
    cat /tmp/build_command.txt
  elif [[ "$line" == "{{copy_instructions}}" ]]; then
    cat /tmp/copy_instructions.txt
  elif [[ "$line" == "{{runner_commands}}" ]]; then
    cat /tmp/runner_commands.txt
  else
    echo "$line"
  fi
done < /tmp/dockerfile_partial.txt > /tmp/dockerfile_pre_final.txt

# Remove consecutive blank lines (keep only one)
awk 'BEGIN {blank=0} /^[[:space:]]*$/ {blank++; if(blank==1) print; next} {blank=0; print}' /tmp/dockerfile_pre_final.txt > "$DF_BUFFER"

# Clean up temp files
rm -f /tmp/dockerfile_partial.txt /tmp/copy_instructions.txt /tmp/runner_commands.txt /tmp/build_command.txt /tmp/dockerfile_pre_final.txt

if [[ "$DRY_RUN" == false ]]; then
  echo "Dockerfile generated successfully: $DF_BUFFER"
fi
