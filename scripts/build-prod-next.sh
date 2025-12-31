#!/bin/bash

# On error exit
set -euo pipefail

git config --global --add safe.directory /home/ubuntu/app

# Compute version info
REV=$(git rev-parse --short HEAD)
TAG=$(git tag --points-at HEAD 2>/dev/null || echo "")
CWD=$(pwd)
APP_VERSION="${REV} (${TAG:-undefined})"

echo "Building: ${APP_VERSION}"

# Write APP_VERSION to src/version.ts
echo "export const APP_VERSION = '${APP_VERSION}';" >$CWD/src/version.ts

# Build
yarn install --frozen-lockfile
yarn next telemetry disable
yarn build

echo "Completed: ${APP_VERSION}"
