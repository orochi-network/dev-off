#!/bin/bash

# On error exit
set -euo pipefail

git config --global --add safe.directory /home/ubuntu/app

# Compute version info (logged only — unlike the node/next/nginx scripts this
# deliberately does NOT write src/version.ts. Strapi owns its own src/ tree and
# generates a typed project from it; injecting a version.ts there is both
# unnecessary and risks clashing with Strapi's own type generation.)
REV=$(git rev-parse --short HEAD)
TAG=$(git tag --points-at HEAD 2>/dev/null || echo "")
APP_VERSION="${REV} (${TAG:-undefined})"

echo "Building: ${APP_VERSION}"

# Enable corepack so the project's pinned package manager (Strapi ships Yarn 4
# berry; the base image only ships Yarn 1) is the one that runs the build.
corepack enable

# Immutable install (Yarn 4 berry equivalent of --frozen-lockfile): fail if the
# lockfile would have to change. `yarn build` runs `strapi build`, which compiles
# the admin panel and the server (TypeScript → dist, per tsconfig.json outDir).
yarn install --immutable
yarn build

echo "Completed: ${APP_VERSION}"
