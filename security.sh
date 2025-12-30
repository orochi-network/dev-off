#!/usr/bin/env bash

# Concat all public keys
cat ./gpg/*.asc >gpg-list.asc

# Update checksum file
sha256sum ./gpg-list.asc ./configs/* ./scripts/* >checksum.sha256

