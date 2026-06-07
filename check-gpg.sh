#!/usr/bin/env bash

set -euo pipefail

# If base revision was set, we are going to use given revision
# BASE_REVISION="db70372fd4ecbc111cb195ebe249809d8f0768a3" curl -sL https://...
BASE_REVISION="${BASE_REVISION:-main}"
# Validate BASE_REVISION before it is interpolated into any fetch URL and before
# any destructive setup runs. Accept only a git commit SHA, tag, or branch name;
# reject shell metacharacters and any '..' sequence (curl normalizes '../' in URL
# paths and could be repointed at an arbitrary repo/path). See SECURITY.md.
if [[ ! "$BASE_REVISION" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ || "$BASE_REVISION" == *..* ]]; then
  echo "Error: invalid BASE_REVISION '${BASE_REVISION}'. Use a commit SHA, tag, or branch name (chars [A-Za-z0-9._/-], no '..')." >&2
  exit 1
fi
BASE_URL="https://raw.githubusercontent.com/orochi-network/dev-off/${BASE_REVISION}"

# Log the revision we are trusting (forensics: pin this to a commit SHA in CI).
echo "[dev-off] check-gpg using revision: ${BASE_REVISION}" >&2

# --connect-timeout/--max-time/--retry: bound every network fetch so a stalled
# connection fails fast (and retries transient blips) instead of hanging the
# trust check indefinitely.
CURL_OPTS=(--connect-timeout 15 --max-time 120 --retry 3 --retry-delay 2)

check_sha256sum() {
  curl -fsSL "${CURL_OPTS[@]}" "$BASE_URL/checksum.sha256" | grep -F --color=never -- "$1" | sha256sum -c --strict -
}

# Clean state (important for self-hosted runners)
rm -rf ~/.gnupg
mkdir -p ~/.gnupg
chmod 700 ~/.gnupg

# Fetch and verify allowlist
curl -fsSL "${CURL_OPTS[@]}" -O "$BASE_URL/gpg-list.asc"
check_sha256sum "gpg-list.asc"

# Import keys and trust them so Git returns 'G'
gpg --batch --import gpg-list.asc
gpg --list-keys --with-colons | awk -F: '/^fpr:/ {print $10":6:"}' | gpg --import-ownertrust

# Build allowlist of pub + sub key IDs (LONG)
gpg --show-keys --keyid-format LONG gpg-list.asc |
  awk '/^(pub|sub) /{print $2}' | cut -d'/' -f2 >.allowed-keyids.txt

# Ensure git uses gpg
git config --global gpg.program gpg

# Check commit signatures. Fail closed: never pass silently when the range is
# unusable. If BASE_SHA/HEAD_SHA are unset this script only imported keys, so we
# warn loudly that NO commits were verified (manual setup usage); CI must pass
# both SHAs for the check to be enforced.
if [[ -z "${BASE_SHA:-}" || -z "${HEAD_SHA:-}" ]]; then
  echo "WARNING: BASE_SHA/HEAD_SHA not set — keys imported but NO COMMITS WERE VERIFIED." >&2
  echo "         Set BASE_SHA and HEAD_SHA to enforce GPG signature checks." >&2
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

    # Defense-in-depth: an empty key id would match a blank line in the allowlist
    # via `grep -Fxq ""`. Reject it before the membership check.
    if [[ -z "$KEY" ]]; then
      echo "Empty signer key id for commit $COMMIT" >&2
      exit 1
    fi

    # Key must be in central allowlist
    if ! grep -Fxq "$KEY" .allowed-keyids.txt; then
      echo "Signer key $KEY not in allowlist"
      exit 1
    fi
    echo "Valid: trusted signature from allowed key"
done
