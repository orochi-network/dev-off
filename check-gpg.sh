#!/usr/bin/env bash

set -e
 # Clean state (important for self-hosted runners)
rm -rf ~/.gnupg
mkdir -p ~/.gnupg
chmod 700 ~/.gnupg

# Download GPG keys and checksum
curl -O https://raw.githubusercontent.com/orochi-network/dev-off/refs/heads/main/gpg-list.asc
curl -O https://raw.githubusercontent.com/orochi-network/dev-off/refs/heads/main/gpg-list.sha256

# Verify checksum
sha256sum -c --strict gpg-list.sha256

 # Import keys and trust them so Git returns 'G'
gpg --batch --import gpg-list.asc
gpg --list-keys --with-colons | awk -F: '/^fpr:/ {print $10":6:"}' | gpg --import-ownertrust

# Build allowlist of pub + sub key IDs (LONG)
gpg --show-keys --keyid-format LONG gpg-list.asc \
| awk '/^(pub|sub) /{print $2}' | cut -d'/' -f2 > .allowed-keyids.txt
 # Ensure git uses gpg
git config --global gpg.program gpg

# Check all commits are signed by an allowed key
COMMITS=$(git rev-list ${{ github.event.pull_request.base.sha }}..${{ github.event.pull_request.head.sha }})
for COMMIT in $COMMITS; do
            SIG=$(git log --format='%G?' -n 1 "$COMMIT")
            KEY=$(git log --format='%GK' -n 1 "$COMMIT")
            echo "Commit $COMMIT: sig=$SIG key=$KEY"

            # Require good + trusted signature
            if [[ "$SIG" != "G" ]]; then
              case "$SIG" in
                "E") echo "Missing key $KEY" ;;
                "N") echo "Unsigned commit" ;;
                "B") echo "Bad signature (tampered)" ;;
                "U") echo "Key not trusted (setup issue)" ;;
                "X"|"Y") echo "Expired signature/key" ;;
                "R") echo "Revoked key" ;;
                *) echo "Unknown signature status: $SIG" ;;
              esac
              exit 1
            fi

            # Key must be in central allowlist
            if ! grep -Fxq "$KEY" .allowed-keyids.txt; then
              echo "Signer key $KEY not in allowlist"
              exit 1
            fi
            echo "Valid: trusted signature from allowed key"
        done
