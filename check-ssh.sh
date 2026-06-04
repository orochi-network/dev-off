#!/usr/bin/env bash

set -euo pipefail

# If base revision was set, we are going to use given revision
# BASE_REVISION="db70372fd4ecbc111cb195ebe249809d8f0768a3" curl -sL https://...
BASE_REVISION="${BASE_REVISION:-main}"
BASE_URL="https://raw.githubusercontent.com/orochi-network/dev-off/${BASE_REVISION}"

# Log the revision we are trusting (forensics: pin this to a commit SHA in CI).
echo "[dev-off] check-ssh using revision: ${BASE_REVISION}" >&2

check_sha256sum() {
  curl -fsSL "$BASE_URL/checksum.sha256" | grep -F --color=never -- "$1" | sha256sum -c --strict -
}

# Clean state (important for self-hosted runners)
rm -f ./ssh-allowed-signers .allowed-ssh-fingerprints.txt

# Fetch and verify allowlist
curl -fsSL -O "$BASE_URL/ssh-allowed-signers"
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

# Check commit signatures. Fail closed: never pass silently when the range is
# unusable. If BASE_SHA/HEAD_SHA are unset this script only configured Git, so we
# warn loudly that NO commits were verified (manual setup usage); CI must pass
# both SHAs for the check to be enforced.
if [[ -z "${BASE_SHA:-}" || -z "${HEAD_SHA:-}" ]]; then
  echo "WARNING: BASE_SHA/HEAD_SHA not set — Git configured but NO COMMITS WERE VERIFIED." >&2
  echo "         Set BASE_SHA and HEAD_SHA to enforce SSH signature checks." >&2
  exit 0
fi

COMMITS=$(git rev-list "$BASE_SHA..$HEAD_SHA")
if [[ -z "$COMMITS" ]]; then
  echo "ERROR: commit range $BASE_SHA..$HEAD_SHA is empty — refusing to pass without verifying any commit." >&2
  exit 1
fi

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
