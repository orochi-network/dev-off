# Changelog

All notable changes to dev-off are documented here. Downstream consumers should
pin `BASE_REVISION` to a tagged release rather than `main`.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Security
- **Build-time npm token no longer persists in builder layers:** credentials are
  created, used, and deleted inside a single `--mount=type=secret` build `RUN`
  (`Dockerfile.template` + `dockerfile.sh`), so the token never lands in any image
  layer. Enforced by a new CI job (`builder-secret-no-leak`) that builds the
  builder stage with a canary secret and fails if it is found in the image.
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
- **`BASE_REVISION` is validated before use:** `check-gpg.sh`, `check-ssh.sh`, and
  `dockerfile.sh` now reject a `BASE_REVISION` containing shell metacharacters or
  a `..` path-traversal sequence (curl normalizes `../`) before it is interpolated
  into any fetch URL or any destructive setup runs. Only a commit SHA, tag, or
  branch name is accepted.
- **`dockerfile.sh` directive-injection hardening:** user-supplied values
  (`-c`, `-f`, `-b`, `-r`, `--run`) are rejected if they contain a newline or
  carriage return, so a value like `$'build\nRUN …'` can no longer inject extra
  Dockerfile directives. A `-f` value with more than one `;` is also rejected
  (the credential guard and the COPY generator parsed it differently).
- **`check-ssh.sh` fails closed on unparseable signers:** if any
  `ssh-allowed-signers` line fails to produce a fingerprint it now errors instead
  of silently building a narrower allowlist.
- **`generate-yarn-npm.sh` carries an explicit do-not-use-in-`docker build`
  warning** (it writes a plaintext token for ephemeral runners only; image builds
  must use `dockerfile.sh`'s BuildKit secret mount).
- **CI shellcheck action pinned to a commit SHA** (`ludeeus/action-shellcheck`)
  instead of a moving `@master` branch.

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
- **nginx template build no longer aborts:** the runner stage pre-creates
  `/home/<runner_user>` before `chown`, so the `nginx` template (whose base image
  ships no `/home/nginx`) builds successfully. nginx still runs non-root and
  listens on `:80`, which requires the host to allow unprivileged low ports
  (`net.ipv4.ip_unprivileged_port_start=0`, the Docker Desktop default).
- `docker-compose.yaml`: removed the obsolete top-level `version` key (ignored by
  Compose v2).
- `README.md`: documents the `next` template and corrects the default command to
  `["npm", "start"]`.
