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
| `strapi` | `node:22-trixie-slim` | Strapi headless CMS (glibc runner for `sharp`/`libvips`) |

List all templates with details:

```bash
./dockerfile.sh -l
```

## Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `-t, --template TYPE` | Template type: `node`, `nginx`, `next`, `strapi` | Required |
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

### Strapi Headless CMS

`strapi` defaults to the glibc runner `node:22-trixie-slim` (Strapi's native
`sharp`/`libvips` are built against glibc and break at runtime on Alpine/musl). It
enables `corepack` (Strapi ships Yarn 4 berry; the base image only carries Yarn 1),
sets `ENV NODE_ENV=production`, `EXPOSE 1337`, and defaults `CMD` to
`["npm", "run", "start"]`.

If you pass no `-f`, it copies a sensible default runtime set:
`config src database public types dist .strapi tsconfig.json package.json
node_modules favicon.png`. `tsconfig.json` is **load-bearing** — Strapi reads its
`outDir` to locate the compiled server in `dist/`.

```bash
# Use the built-in default copy set
./dockerfile.sh -t strapi

# Or specify the copy set explicitly (equivalent to the default)
./dockerfile.sh -t strapi \
  -f config \
  -f src \
  -f database \
  -f public \
  -f types \
  -f dist \
  -f .strapi \
  -f tsconfig.json \
  -f package.json \
  -f node_modules \
  -f favicon.png
```

If you must override the runner image, keep it glibc-based:

```bash
./dockerfile.sh -t strapi -r node:22-bookworm-slim
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

| Setting | Builder | Runner (node/next) | Runner (nginx) | Runner (strapi) |
|---------|---------|-------------------|----------------|-----------------|
| Base Image | `orochinetwork/ubuntu:node` | `node:24-alpine` | `nginx:stable-alpine` | `node:22-trixie-slim` |
| User | `ubuntu` | `node` | `nginx` | `node` |
| Group | `ubuntu` | `node` | `nginx` | `node` |
| Workdir | `/home/ubuntu/app` | `/home/node/app` | `/usr/share/nginx/html` | `/home/node/app` |

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

#### Strapi (`-t strapi`)
- Runner defaults to **`node:22-trixie-slim`** (glibc — **required**: Strapi's
  native `sharp`/`libvips` are built against glibc and break at runtime on
  Alpine/musl). A `-r`/`RUNNER_IMAGE` override is still honored — keep it glibc.
- Enables `corepack` in both the builder and the runner (Strapi uses Yarn 4 berry;
  the base image ships Yarn 1).
- Includes `ENV NODE_ENV=production` and `EXPOSE 1337`
- Default CMD: `["npm", "run", "start"]`
- Auto-defaults to copying `config src database public types dist .strapi
  tsconfig.json package.json node_modules favicon.png` if no files specified.
  `tsconfig.json` is load-bearing (Strapi reads its `outDir` to find `dist/`).
- Build script (`scripts/build-prod-strapi.sh`) runs an immutable install
  (`yarn install --immutable`) then `yarn build` (= `strapi build`: admin panel +
  server → `dist`). Unlike the node/next/nginx scripts it does **not** write
  `src/version.ts` — Strapi owns its `src/` tree and type generation.

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
          files_to_copy: .next package.json node_modules public
          platform: linux/amd64
        secrets: inherit
```

### Action Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `template` | Template type | Yes | - |
| `docker_repo` | Docker repository name | Yes | - |
| `image_tag` | Docker image tag | No | `${{ github.sha }}` |
| `files_to_copy` | Space-separated files | No | - |
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
      files_to_copy: .next package.json node_modules next.config.ts public
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

## Adding a new template

Templates are defined in `dockerfile.sh`. Adding one is a small, well-bounded
change — `dockerfile.sh` validates `--template` against `SUPPORTED_TEMPLATES` and
fails fast on anything unknown, so a half-added template can't silently emit the
wrong Dockerfile.

1. **Register the name.** Add it to the `SUPPORTED_TEMPLATES` array near the top
   of `dockerfile.sh`.
2. **Add an override block.** Add a `case "$DOCKER_TEMPLATE"` branch setting the
   runner image, user/group, workdir, default `CMD`, exposed ports, and any
   default `-f`/`--run` behavior (use the `node`/`nginx`/`next` branches as a
   model).
3. **Add the build script (if needed).** Create
   `scripts/build-prod-<template>.sh`. Keep it self-contained — these are fetched
   individually inside the container, so they must not depend on a shared lib.
   Guard any source-tree writes (e.g. `version.ts`) behind a directory check.
4. **Refresh checksums.** Run `./generate-checksums.sh` and commit the updated
   `checksum.sha256` (add the new build script to the `FILES` list in
   `generate-checksums.sh` first).
5. **Document & test.** Add the template to `show_help`/`list_templates`, then
   verify with `./dockerfile.sh -t <template> --dry-run`. CI runs the same
   dry-run smoke test.

> The `rust` template is intentionally **not** implemented yet — follow the steps
> above to add it rather than re-enabling the old placeholder.