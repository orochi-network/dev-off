#!/usr/bin/env bash
set -euo pipefail

# Dev helper: prints the local POSTGRES_URL derived from .env.
# .env is git-ignored; copy .env.example to .env first.
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "Error: .env not found. Copy .env.example to .env first." >&2
  exit 1
fi

# shellcheck disable=SC1091
source .env

echo "POSTGRES_URL=\"postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:${POSTGRES_PORT}/${POSTGRES_DB}\""