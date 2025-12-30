#!/usr/bin/env bash

set -euo pipefail

# If base revision was set, we are going to use given revision
# BASE_REVISION="db70372fd4ecbc111cb195ebe249809d8f0768a3" curl -sL https://...
BASE_REVISION="${BASE_REVISION:-main}"
BASE_URL="https://raw.githubusercontent.com/orochi-network/dev-off/${BASE_REVISION}/"

check_sha256sum() {
  curl -sL $BASE_URL/checksum.sha256 | grep --color=never $1 | sha256sum -c --strict -
}

# Clean state (important for self-hosted runners)
rm -rf ~/.gnupg
mkdir -p ~/.gnupg
chmod 700 ~/.gnupg

# Fetch and verify allowlist
curl -O $BASE_URL/gpg-list.asc
check_sha256sum "gpg-list.asc"

# Import keys and trust them so Git returns 'G'
gpg --batch --import gpg-list.asc
gpg --list-keys --with-colons | awk -F: '/^fpr:/ {print $10":6:"}' | gpg --import-ownertrust

# Build allowlist of pub + sub key IDs (LONG)
gpg --show-keys --keyid-format LONG gpg-list.asc |
  awk '/^(pub|sub) /{print $2}' | cut -d'/' -f2 >.allowed-keyids.txt

# Ensure git uses gpg
git config --global gpg.program gpg

# Check commit signatures (only if BASE_SHA and HEAD_SHA are set)
if [[ -n "${BASE_SHA:-}" && -n "${HEAD_SHA:-}" ]]; then
  COMMITS=$(git rev-list "$BASE_SHA..$HEAD_SHA")
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
      "X" | "Y") echo "Expired signature/key" ;;
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
fi
