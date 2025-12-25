#!/usr/bin/env bash

set -e

curl -O https://raw.githubusercontent.com/orochi-network/dev-off/refs/heads/main/gpg-list.asc
curl -O https://raw.githubusercontent.com/orochi-network/dev-off/refs/heads/main/gpg-list.sha256

sha256sum -c --strict gpg-list.sha256
