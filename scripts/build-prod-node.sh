#!/bin/bash

# On error exit
set -euo pipefail

CWD=$(pwd)

# APP_VERSION is normally injected from the build host (the image build context
# has no .git, so git cannot run here). Fall back to git only when this script
# is run locally inside a real repository.
if [ -z "${APP_VERSION:-}" ]; then
  git config --global --add safe.directory "$CWD" 2>/dev/null || true
  REV=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
  TAG=$(git tag --points-at HEAD 2>/dev/null || echo "")
  APP_VERSION="${REV} (${TAG:-undefined})"
fi

echo "Building: ${APP_VERSION}"

# Write APP_VERSION to src/version.ts (only when a src/ directory exists)
if [ -d "$CWD/src" ]; then
  echo "export const APP_VERSION = '${APP_VERSION}';" >"$CWD/src/version.ts"
else
  echo "Note: no src/ directory — skipping version.ts generation" >&2
fi

# Build
yarn install --frozen-lockfile
yarn build

echo "Completed: ${APP_VERSION}"
