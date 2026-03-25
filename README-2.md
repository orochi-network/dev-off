# dev-off

DevOps toolchain for Orochi Network — Dockerfile generation, GPG commit verification, local infrastructure, and developer environment setup.

## Table of Contents

- [Overview](#overview)
- [Dockerfile Generator](#dockerfile-generator)
- [GPG Commit Verification](#gpg-commit-verification)
- [Local Infrastructure](#local-infrastructure)
- [NPM/Yarn Configuration](#npmyarn-configuration)
- [Claude Code Setup (Z.AI)](#claude-code-setup-zai)
- [Security & Checksums](#security--checksums)
- [Repository Structure](#repository-structure)
- [Contributing](#contributing)

## Overview

`dev-off` provides shared DevOps utilities used across Orochi Network repositories:

| Tool | Description |
|------|-------------|
| `dockerfile.sh` | Generate multi-stage Dockerfiles from templates |
| `check-gpg.sh` | Verify GPG signatures on PR commits |
| `docker-compose.yaml` | Local dev infrastructure (Postgres, Redis, RabbitMQ) |
| `generate-yarn-npm.sh` | Configure `.npmrc` and `.yarnrc.yml` for private packages |
| `claude_code_zai_env.sh` | Install and configure Claude Code with Z.AI API |
| `security.sh` | Merge GPG keys and update checksums |

Scripts can be run locally or fetched remotely via `curl`. Pin a specific revision with `BASE_REVISION`:

```bash
BASE_REVISION="main" curl -sL https://raw.githubusercontent.com/orochi-network/dev-off/main/<script> | bash
```

## Dockerfile Generator

Generate optimized multi-stage Dockerfiles for Node.js, Next.js, and Nginx projects.

### Quick Start

```bash
# Remote usage
curl -sL https://raw.githubusercontent.com/orochi-network/dev-off/main/dockerfile.sh | bash -- -t node -f package.json -f build

# Local usage
./dockerfile.sh -t next -f .next -f package.json -f node_modules -f public
```

### Templates

| Template | Runner Image | Use Case |
|----------|-------------|----------|
| `node` | `node:24-alpine` | Node.js backend apps |
| `next` | `node:24-alpine` | Next.js apps (adds `NEXT_TELEMETRY_DISABLED=1`) |
| `nginx` | `nginx:stable-alpine` | Static sites (React, Vue, HTML); exposes port 80 |

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `-t, --template TYPE` | Template: `node`, `nginx`, `next` | Required |
| `-f, --file FILE` | File/dir to copy (repeatable). Use `"src;dst"` for custom paths | — |
| `-c, --command CMD` | Container CMD | `["npm", "start"]` |
| `-b, --build CMD` | Custom build command | Auto-detected |
| `-r, --runner-image IMAGE` | Custom runner image | Template default |
| `-e, --env-file FILE` | Copy .env file before build | — |
| `--run CMD` | Extra RUN in runner stage (repeatable) | — |
| `--dry-run` | Print to stdout instead of writing file | `false` |
| `-l, --list` | List templates | — |

### File Copy Formats

**Simple** — copies between builder and runner workdirs:

```bash
-f package.json     # /home/ubuntu/app/package.json → ./package.json
```

**Custom paths** — semicolon-separated `src;dst`:

```bash
-f "nginx.conf;/etc/nginx/conf.d/default.conf"
```

### Build Command Priority

1. `-b "custom command"` (highest)
2. Local `scripts/build-prod.sh` if exists
3. Remote `build-prod-{template}.sh` (lowest)

### Examples

```bash
# Node.js with custom runner
./dockerfile.sh -t node -r node:24-trixie-slim -f build -f package.json \
  -c '["node", "server.js"]'

# Nginx with custom config
./dockerfile.sh -t nginx -f "nginx.conf;/etc/nginx/conf.d/default.conf"

# Next.js with env file and dry-run
./dockerfile.sh -t next -e .env.production -f .next -f package.json --dry-run

# Post-copy RUN commands
./dockerfile.sh -t node -f build -f package.json \
  --run "chmod +x /home/node/app/run-service.sh"
```

### Building the Image

```bash
# Basic
docker build -t myapp:latest .

# With NPM token for private packages
echo "$NPM_ACCESS_TOKEN" > npm_access_token
docker build --secret id=npm_access_token,src=./npm_access_token -t myapp:latest .
```

### GitHub Actions

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: orochi-network/actions/build-docker-template@main
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

Full action inputs and reusable workflow docs: see [docs/dockerfile-generator.md](./docs/dockerfile-generator.md).

### Custom Templates

Place a `Dockerfile.template` in your project root to override the remote template. Available placeholders: `{{builder_base_image}}`, `{{runner_base_image}}`, `{{build_command}}`, `{{copy_instructions}}`, `{{cmd}}`, etc.

## GPG Commit Verification

Verify all commits in a PR are GPG-signed by allowed team members.

```bash
curl -sL https://raw.githubusercontent.com/orochi-network/dev-off/main/check-gpg.sh | bash
```

### How It Works

1. Downloads and verifies `gpg-list.asc` against `checksum.sha256`
2. Imports GPG keys and sets ultimate trust
3. Builds allowlist of authorized key IDs
4. For each commit in `BASE_SHA..HEAD_SHA`: checks signature status (`G` = good) and verifies key is in allowlist

### Environment Variables

| Variable | Description |
|----------|-------------|
| `BASE_REVISION` | Script revision to use (default: `main`) |
| `BASE_SHA` | Start of commit range to verify |
| `HEAD_SHA` | End of commit range to verify |

### Managing GPG Keys

Team member keys live in `gpg/*.asc`. To add/update:

1. Export public key: `gpg --armor --export <KEY_ID> > gpg/<name>.asc`
2. Run `./security.sh` to merge keys into `gpg-list.asc` and update `checksum.sha256`
3. Commit all changed files

## Local Infrastructure

Development services via Docker Compose (profile: `infra`):

| Service | Image | Ports |
|---------|-------|-------|
| PostgreSQL 16 | `postgres:16` | `${POSTGRES_PORT}:5432` |
| Redis | `redis:latest` | `7011:6379` |
| RabbitMQ 4.0.6 | `rabbitmq:4.0.6-management` | `7012:5672` (AMQP), `7013:15672` (UI) |

### Usage

```bash
# Create .env with required vars
cat > .env << 'EOF'
POSTGRES_USER=postgres
POSTGRES_PASSWORD=password
POSTGRES_DB=devdb
POSTGRES_PORT=5432
EOF

# Start all services
docker compose --profile infra up -d

# Stop
docker compose --profile infra down
```

All services include health checks and persistent volumes.

## NPM/Yarn Configuration

Generate `.npmrc` and `.yarnrc.yml` for private `@orochi-network` and `@zkdb` packages.

```bash
NPM_ACCESS_TOKEN="your-token" ./generate-yarn-npm.sh
```

### Options

| Flag | Description |
|------|-------------|
| `-s HOME_PATH` | Target directory (default: `/home/ubuntu`) |
| `-f SCOPE` | Add npm scope (repeatable; currently unused — global auth) |

Currently configures global npm authentication rather than per-scope.

## Claude Code Setup (Z.AI)

One-command setup for Claude Code with Z.AI API proxy.

```bash
curl -sL https://raw.githubusercontent.com/orochi-network/dev-off/main/claude_code_zai_env.sh | bash
```

### What It Does

1. Checks/installs Node.js >= 18 via nvm
2. Installs `@anthropic-ai/claude-code` globally
3. Prompts for Z.AI API key
4. Writes `~/.claude/settings.json` with API base URL and auth token

Get your API key at: https://z.ai/manage-apikey/apikey-list

## Security & Checksums

`security.sh` maintains integrity of shared assets:

1. Merges all `gpg/*.asc` files into `gpg-list.asc`
2. Generates `checksum.sha256` covering `gpg-list.asc`, `configs/*`, and `scripts/*`

Run after any change to GPG keys, configs, or build scripts:

```bash
./security.sh
```

## Repository Structure

```
dev-off/
├── check-gpg.sh              # GPG commit signature verification
├── dockerfile.sh              # Dockerfile generator CLI
├── Dockerfile.template        # Template used by dockerfile.sh
├── DOCKERFILE.md              # Detailed Dockerfile generator docs
├── docker-compose.yaml        # Local dev infrastructure
├── generate-yarn-npm.sh       # NPM/Yarn auth config generator
├── claude_code_zai_env.sh     # Claude Code + Z.AI setup
├── security.sh                # GPG key merger + checksum updater
├── checksum.sha256            # SHA256 checksums for verified files
├── gpg-list.asc               # Merged GPG public keys
├── gpg/                       # Individual team member GPG keys
│   └── *.asc
├── configs/
│   └── nginx.conf             # Default nginx configuration
├── scripts/
│   ├── build-prod-node.sh     # Default Node.js build script
│   ├── build-prod-next.sh     # Default Next.js build script
│   └── build-prod-nginx.sh    # Default Nginx build script
├── list-dockerfile/            # Example/reference Dockerfiles
├── .env                        # Local env vars (not committed)
└── LICENSE                     # Apache 2.0
```

## Contributing

1. Fork and create a feature branch
2. All commits must be GPG-signed (enforced by CI)
3. If modifying GPG keys, configs, or scripts — run `./security.sh` before committing
4. Open a PR against `main`

## License

[Apache License 2.0](./LICENSE)
