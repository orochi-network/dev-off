#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Single source of truth for checksum.sha256.
#
# Lists EXACTLY the files that are distributed to (or fetched at runtime by)
# downstream consumers and therefore must be integrity-verifiable. Crucially this
# now includes the executable scripts that are run via `curl | bash`
# (check-gpg.sh, check-ssh.sh, dockerfile.sh, generate-yarn-npm.sh) — previously
# only the allowlist data files were covered, leaving the scripts themselves
# unverifiable.
#
# Run this after changing any covered file and commit the updated checksum.sha256.
# Both security.sh and generate-ssh-allowed-signers.sh delegate here so the file
# set never drifts between generators.
# ============================================================================

cd "$(dirname "$0")"

# Covered files (relative paths). Add new distributed scripts/templates here.
FILES=(
  # Executable scripts fetched via curl|bash by the actions repo
  check-gpg.sh
  check-ssh.sh
  dockerfile.sh
  generate-yarn-npm.sh
  # Template + configs consumed at build time
  Dockerfile.template
  configs/nginx.conf
  # In-container build scripts (fetched by generated Dockerfiles)
  scripts/build-prod-node.sh
  scripts/build-prod-next.sh
  scripts/build-prod-nginx.sh
  # Trust allowlists
  gpg-list.asc
  ssh-allowed-signers
)

OUT="checksum.sha256"
TMP="$(mktemp "${TMPDIR:-/tmp}/checksum.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

missing=0
for f in "${FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: covered file is missing: $f" >&2
    missing=1
    continue
  fi
  sha256sum "./$f" >> "$TMP"
done

if [[ "$missing" -ne 0 ]]; then
  echo "Refusing to write an incomplete $OUT" >&2
  exit 1
fi

# Deterministic ordering so the file is reproducible regardless of array order.
sort -o "$OUT" "$TMP"

echo "Wrote $OUT covering ${#FILES[@]} files"
