#!/usr/bin/env bash

set -euo pipefail

# If base revision was set, we are going to use given revision
# BASE_REVISION="db70372fd4ecbc111cb195ebe249809d8f0768a3" curl -sL https://...
BASE_REVISION="${BASE_REVISION:-main}"
BASE_URL="https://raw.githubusercontent.com/orochi-network/dev-off/${BASE_REVISION}"

check_sha256sum() {
  curl -sL $BASE_URL/checksum.sha256 | grep --color=never $1 | sha256sum -c --strict -
}

# Clean state (important for self-hosted runners)
rm -f ./ssh-allowed-signers .allowed-ssh-fingerprints.txt

# Fetch and verify allowlist
curl -O $BASE_URL/ssh-allowed-signers
check_sha256sum "ssh-allowed-signers"

# Extract allowed key fingerprints from allowed-signers file
# Each non-comment line: <email> <key-type> <key-data>
# Strip email prefix, compute fingerprint via ssh-keygen
grep -v '^#' ssh-allowed-signers | grep -v '^$' | while read -r line; do
  echo "$line" | awk '{print $2, $3}' | ssh-keygen -lf /dev/stdin 2>/dev/null
done | awk '{print $2}' > .allowed-ssh-fingerprints.txt

# Configure git to use SSH signature verification
git config --global gpg.format ssh
git config --global gpg.ssh.allowedSignersFile "$(pwd)/ssh-allowed-signers"

# Check commit signatures (only if BASE_SHA and HEAD_SHA are set)
if [[ -n "${BASE_SHA:-}" && -n "${HEAD_SHA:-}" ]]; then
  COMMITS=$(git rev-list "$BASE_SHA..$HEAD_SHA")
  for COMMIT in $COMMITS; do
    SIG=$(git log --format='%G?' -n 1 "$COMMIT")
    KEY=$(git log --format='%GK' -n 1 "$COMMIT")
    echo "Commit $COMMIT: sig=$SIG key=$KEY"

    # Require good signature
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

    # Key fingerprint must be in central allowlist
    if ! grep -Fxq "$KEY" .allowed-ssh-fingerprints.txt; then
      echo "Signer key $KEY not in allowlist"
      exit 1
    fi
    echo "Valid: trusted SSH signature from allowed key"
  done
fi
