# Changelog

All notable changes to dev-off are documented here. Downstream consumers should
pin `BASE_REVISION` to a tagged release rather than `main`.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Security
- **Closed the checksum coverage gap:** `checksum.sha256` now covers the
  executable scripts that are fetched via `curl | bash` (`check-gpg.sh`,
  `check-ssh.sh`, `dockerfile.sh`, `generate-yarn-npm.sh`) and
  `Dockerfile.template`, not just the allowlist data files.
- **`dockerfile.sh` injection hardening:** template values are now passed to
  `perl` via the environment (`$ENV{…}`) so user-controlled content (commands,
  image names, `CMD`) can never be interpreted as perl/regex. Added
  `set -euo pipefail`, `mktemp` working dir (no predictable `/tmp` names),
  template/argument validation, and a guard refusing to copy credential files
  (`.npmrc`/`.yarnrc`/`.yarnrc.yml`/`.netrc`) into images.
- **Fail-closed signature checks:** `check-gpg.sh` / `check-ssh.sh` now error on
  an empty commit range and warn loudly when `BASE_SHA`/`HEAD_SHA` are unset,
  instead of silently passing. Quoted URLs; `curl -fsSL`; revision logging.
  (Signature *matching* logic was verified correct and left unchanged.)
- **Secrets hygiene:** `generate-yarn-npm.sh` uses `umask 077`; `.env` removed
  from version control with a committed `.env.example`; added `.gitignore` and a
  `.dockerignore.example`; parameterized RabbitMQ credentials in
  `docker-compose.yaml`.

### Added
- `generate-checksums.sh` — single source of truth for `checksum.sha256`;
  `security.sh` and `generate-ssh-allowed-signers.sh` delegate to it.
- Trust-anchor drift report (GPG keys vs SSH signers) in
  `generate-ssh-allowed-signers.sh`.
- `SECURITY.md`, `CODEOWNERS`, this `CHANGELOG.md`, and an "Adding a new
  template" guide in `DOCKERFILE.md`.
- CI: `.github/workflows/lint-and-test.yml` (shellcheck, `bash -n`,
  checksum-freshness check, and `dockerfile.sh --dry-run` smoke tests).

### Fixed
- `build-prod-*.sh` only write `src/version.ts` when a `src/` directory exists
  (pure static sites no longer fail the build).
- `dockerfile.sh` no longer advertises the unimplemented `rust` template as
  selectable; invalid/unknown templates and arguments now fail fast.
