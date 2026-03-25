# Dockerfile Generator

A bash script that automatically generates optimized, multi-stage Dockerfiles for Node.js, Next.js, and Nginx projects.

## Overview

Instead of writing Dockerfiles manually, this tool generates them based on templates and command-line options. It follows Docker best practices including:

- **Multi-stage builds** - Separate builder and runner stages for smaller final images
- **Non-root users** - Runs applications as non-privileged users for security
- **Optimized layers** - Efficient COPY instructions with proper ownership
- **NPM token handling** - Secure mounting of NPM access tokens as Docker secrets

## Quick Start

```bash
# Download the script
curl -sL https://raw.githubusercontent.com/orochi-network/dev-off/main/dockerfile.sh -o dockerfile.sh
chmod +x dockerfile.sh

# Generate a Dockerfile for a Next.js project
./dockerfile.sh -t next -f .next -f package.json -f node_modules -f public

# Preview without writing to file
./dockerfile.sh -t node -f build -f package.json --dry-run
```

## Installation

### Option 1: Download directly

```bash
curl -sL https://raw.githubusercontent.com/orochi-network/dev-off/main/dockerfile.sh -o dockerfile.sh
chmod +x dockerfile.sh
```

### Option 2: Use with specific revision

```bash
# Pin to a specific commit/tag for reproducibility
BASE_REVISION="main" curl -sL https://raw.githubusercontent.com/orochi-network/dev-off/main/dockerfile.sh | bash -s -- -t next -f .next
```

### Option 3: Use via GitHub Actions

See [GitHub Actions Integration](#github-actions-integration) section below.

## Available Templates

| Template | Runner Image | Use Case |
|----------|--------------|----------|
| `node` | `node:24-alpine` | Node.js backend applications |
| `next` | `node:24-alpine` | Next.js applications (SSR/SSG) |
| `nginx` | `nginx:stable-alpine` | Static websites (React, Vue, HTML) |

List all templates with details:

```bash
./dockerfile.sh -l
```

## Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `-t, --template TYPE` | Template type: `node`, `nginx`, `next` | Required |
| `-f, --file FILE` | File/directory to copy (repeatable) | None |
| `-c, --command CMD` | Container CMD command | `["npm", "start"]` |
| `-b, --build CMD` | Custom build command | Auto-detected |
| `-r, --runner-image IMAGE` | Custom runner image | Template default |
| `--run CMD` | Extra RUN command in runner (repeatable) | None |
| `--dry-run` | Print to stdout instead of file | `false` |
| `-l, --list` | List available templates | - |
| `-h, --help` | Show help message | - |

## File Copy Behavior

The `-f` option supports two formats:

### Single Argument (Simple)

Copies from builder workdir to runner workdir automatically.

```bash
./dockerfile.sh -t node -f package.json -f build -f node_modules
```

Generated output:

```dockerfile
COPY --from=builder --chown=node:node /home/ubuntu/app/package.json ./package.json
COPY --from=builder --chown=node:node /home/ubuntu/app/build ./build
COPY --from=builder --chown=node:node /home/ubuntu/app/node_modules ./node_modules
```

### Two Arguments with Semicolon (Custom Paths)

For cases where source and destination paths differ.

```bash
./dockerfile.sh -t nginx -f "nginx.conf;/etc/nginx/conf.d/default.conf" -f "build;/usr/share/nginx/html"
```

Generated output:

```dockerfile
COPY --from=builder --chown=nginx:nginx nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder --chown=nginx:nginx build /usr/share/nginx/html
```

## Examples

### Node.js Backend

```bash
./dockerfile.sh -t node \
  -f package.json \
  -f build \
  -f node_modules
```

### Node.js with Custom Runner Image

```bash
./dockerfile.sh -t node \
  -r node:22-trixie-slim \
  -f package.json \
  -f dist \
  -f node_modules \
  -c '["node", "dist/server.js"]'
```

### Next.js Application

```bash
./dockerfile.sh -t next \
  -f .next \
  -f package.json \
  -f node_modules \
  -f next.config.ts \
  -f public
```

### Nginx Static Website

```bash
./dockerfile.sh -t nginx \
  -f "nginx.conf;/etc/nginx/conf.d/default.conf" \
  -f "build;/usr/share/nginx/html"
```

### Nginx with Extra RUN Commands

```bash
./dockerfile.sh -t nginx \
  -f "build;/usr/share/nginx/html" \
  --run "chown -R nginx:nginx /var/cache/nginx" \
  --run "touch /run/nginx.pid && chown nginx:nginx /run/nginx.pid"
```

### Complex Example with All Options

```bash
./dockerfile.sh -t node \
  -r node:22-alpine \
  -f package.json \
  -f tsconfig.json \
  -f migrations \
  -f seeds \
  -f node_modules \
  -f build \
  -b "yarn install --frozen-lockfile && yarn build" \
  -c '["node", "build/index.js"]' \
  --run "chmod +x /home/node/app/build/index.js"
```

### Preview Without Writing (Dry Run)

```bash
./dockerfile.sh -t next -f .next -f package.json --dry-run
```

## Build Command Priority

The script determines the build command in this order:

1. **Custom command** (`-b` option) - If provided, uses this command
2. **Local script** - If `scripts/build-prod.sh` exists in your project
3. **Remote script** - Downloads from `build-prod-{template}.sh`

```
Priority:
┌─────────────────────────────────────────┐
│ 1. -b "custom command"                  │  ← Highest
├─────────────────────────────────────────┤
│ 2. ./scripts/build-prod.sh (local)      │
├─────────────────────────────────────────┤
│ 3. Remote build-prod-{template}.sh      │  ← Lowest
└─────────────────────────────────────────┘
```

## Generated Dockerfile Structure

The generated Dockerfile follows this structure:

```dockerfile
# ============ BUILDER STAGE ============
FROM orochinetwork/ubuntu:node AS builder

ARG BUILDER_WORKDIR=/home/ubuntu/app

# Setup NPM/Yarn credentials (mounted as secret)
RUN --mount=type=secret,id=npm_access_token ...

WORKDIR ${BUILDER_WORKDIR}
COPY --chown=ubuntu:ubuntu . .
USER ubuntu:ubuntu

# Build command (custom, local, or remote script)
RUN ...

# ============ RUNNER STAGE ============
FROM node:24-alpine AS runner

ARG RUNNER_WORKDIR=/home/node/app

# Create app directory with proper permissions
RUN mkdir -p ${RUNNER_WORKDIR} && ...

WORKDIR ${RUNNER_WORKDIR}

# Copy built artifacts from builder
COPY --from=builder --chown=node:node ...

# Extra RUN commands (if any)
RUN ...

USER node:node

CMD ["npm", "start"]
```

## Template Configuration

### Default Values

| Setting | Builder | Runner (node/next) | Runner (nginx) |
|---------|---------|-------------------|----------------|
| Base Image | `orochinetwork/ubuntu:node` | `node:24-alpine` | `nginx:stable-alpine` |
| User | `ubuntu` | `node` | `nginx` |
| Group | `ubuntu` | `node` | `nginx` |
| Workdir | `/home/ubuntu/app` | `/home/node/app` | `/usr/share/nginx/html` |

### Template-Specific Features

#### Node.js (`-t node`)
- Standard Node.js runtime
- Default CMD: `["npm", "start"]`

#### Next.js (`-t next`)
- Includes `ENV NEXT_TELEMETRY_DISABLED=1`
- Default CMD: `["npm", "start"]`

#### Nginx (`-t nginx`)
- Includes `EXPOSE 80`
- Default CMD: `["nginx", "-g", "daemon off;"]`
- Auto-defaults to copying `build/` to `/usr/share/nginx/html` if no files specified

## GitHub Actions Integration

### Using the Composite Action

```yaml
name: Build Docker Image

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build Docker Image
        uses: orochi-network/actions/build-docker-template@main
        with:
          template: next
          docker_repo: myorg/myapp
          files_to_copy: |
            .next
            package.json
            node_modules
            public
          platform: linux/amd64
        secrets: inherit
```

### Action Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `template` | Template type | Yes | - |
| `docker_repo` | Docker repository name | Yes | - |
| `image_tag` | Docker image tag | No | `${{ github.sha }}` |
| `files_to_copy` | Newline-separated files (use `src;dst` for custom paths) | No | - |
| `command` | Container CMD | No | `["npm", "start"]` |
| `build_command` | Custom build command | No | Auto |
| `runner_image` | Custom runner image | No | Template default |
| `runner_commands` | Extra RUN commands (newline-separated) | No | - |
| `platform` | Build platform | No | `linux/amd64` |
| `npm_access_token` | NPM token (secret) | No | - |
| `env_file_content` | Content for .env file | No | - |
| `base_revision` | Script revision | No | `main` |

### Using Reusable Workflow

```yaml
name: Build and Deploy

on:
  push:
    tags: ['v*']

jobs:
  build:
    uses: orochi-network/actions/.github/workflows/test-docker-gen-build.yml@main
    with:
      template: next
      docker_repo: myorg/myapp
      image_tag: ${{ github.ref_name }}
      files_to_copy: |
        .next
        package.json
        node_modules
        next.config.ts
        public
    secrets: inherit
```

## Building the Docker Image

After generating the Dockerfile:

```bash
# Basic build
docker build -t myapp:latest .

# With NPM access token (for private packages)
echo "$NPM_ACCESS_TOKEN" > npm_access_token
docker build \
  --secret id=npm_access_token,src=./npm_access_token \
  -t myapp:latest .

# Multi-platform build
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --secret id=npm_access_token,src=./npm_access_token \
  -t myapp:latest \
  --push .
```

## Customizing the Template

If you need to customize the Dockerfile template, create a `Dockerfile.template` file in your project root. The script will use local template over remote one.

### Available Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{builder_base_image}}` | Builder stage base image |
| `{{builder_user}}` | Builder user name |
| `{{builder_group}}` | Builder group name |
| `{{runner_base_image}}` | Runner stage base image |
| `{{runner_user}}` | Runner user name |
| `{{runner_group}}` | Runner group name |
| `{{build_command}}` | Build command(s) |
| `{{copy_instructions}}` | COPY instructions |
| `{{runner_commands}}` | Extra RUN commands |
| `{{extra_env}}` | Extra ENV variables |
| `{{expose_port}}` | EXPOSE instruction |
| `{{cmd}}` | CMD instruction |

## Troubleshooting

### Script not found

```bash
# Make sure the script is executable
chmod +x dockerfile.sh
```

### Template not generating correctly

```bash
# Use --dry-run to preview output
./dockerfile.sh -t node -f build --dry-run

# Check if local template exists (might override remote)
ls -la Dockerfile.template
```

### Build fails with permission errors

Ensure your build outputs are owned by the correct user. The script sets up proper ownership, but your build process should not change file ownership.

### NPM packages not installing

Make sure to mount the NPM access token as a Docker secret:

```bash
docker build --secret id=npm_access_token,src=./npm_access_token -t myapp .
```