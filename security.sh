#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Rebuild the GPG allowlist (gpg-list.asc) from the individual keys in gpg/,
# then refresh checksum.sha256 via the shared generator.
#
# Run this after adding/removing a key in gpg/ and commit the result.
# ============================================================================

cd "$(dirname "$0")"

OUTPUT_FILE="gpg-list.asc"
rm -f "$OUTPUT_FILE"

shopt -s nullglob
asc_files=(./gpg/*.asc)
if [[ ${#asc_files[@]} -eq 0 ]]; then
  echo "ERROR: no keys found in gpg/ — refusing to write an empty allowlist" >&2
  exit 1
fi

for file in "${asc_files[@]}"; do
  # Only regular files
  [[ -f "$file" ]] || continue

  # Append content to output
  cat "$file" >> "$OUTPUT_FILE"

  # Ensure each block ends with a newline. $(tail -c 1) is empty when the last
  # byte is a newline (Bash strips it), non-empty otherwise.
  if [[ -n "$(tail -c 1 "$file")" ]]; then
    echo "" >> "$OUTPUT_FILE"
  fi
done

echo "Done! ${#asc_files[@]} ASC file(s) merged into $OUTPUT_FILE"

# Refresh checksums via the single source of truth.
./generate-checksums.sh
