# Changelog

All notable changes to dev-off are documented here. Downstream consumers should
pin `BASE_REVISION` to a tagged release rather than `main`.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Removed
- **GPG commit verification — commit signing is now SSH-only.** Deleted
  `check-gpg.sh`, `security.sh`, `gpg-list.asc`, and the `gpg/` key directory;
  dropped them from `checksum.sha256` coverage and CODEOWNERS, and removed the
  GPG-vs-SSH drift report from `generate-ssh-allowed-signers.sh`. Consumers must
  use `check-ssh.sh`; signer onboarding is documented in SECURITY.md.
- **Trusted-signer roster reduction (security boundary):** `GITHUB_USERS` /
  `ssh-allowed-signers` now cover only `brng1151`, `chiro-hiro`,
  `bao-ninh-orochi`, and `chirojr`. Removed `alothanhh`, `BaoNinh2808`,
  `brianw3b`, `CaoHoaiTan`, `harris1111`, `hungnguyen18`, `ngotrongphuc`,
  `nguyendinhthang3101`, `SangTran-127`, `ThanhNguyen03`, and `wonrax`
  (`BaoNinh2808`/`brianw3b` published no SSH keys, so only the other nine had
  live entries). Their commits will no longer pass `check-ssh.sh`; re-add via
  the SECURITY.md onboarding flow if they resume committing.

### Security
- **Build-time npm token no longer persists in builder layers:** credentials are
  created, used, and deleted inside a single `--mount=type=secret` build `RUN`
  (`Dockerfile.template` + `dockerfile.sh`), so the token never lands in any image
  layer. Enforced by a new CI job (`builder-secret-no-leak`) that builds the
  builder stage with a canary secret and fails if it is found in the image.
- **Closed the checksum coverage gap:** `checksum.sha256` now covers the
  executable scripts that are fetched via `curl | bash` (`check-ssh.sh`,
  `dockerfile.sh`, `generate-yarn-npm.sh`) and `Dockerfile.template`, not just
  the allowlist data files.
- **`dockerfile.sh` injection hardening:** template values are now passed to
  `perl` via the environment (`$ENV{…}`) so user-controlled content (commands,
  image names, `CMD`) can never be interpreted as perl/regex. Added
  `set -euo pipefail`, `mktemp` working dir (no predictable `/tmp` names),
  template/argument validation, and a guard refusing to copy credential files
  (`.npmrc`/`.yarnrc`/`.yarnrc.yml`/`.netrc`) into images.
- **Fail-closed signature checks:** `check-ssh.sh` now errors on an empty
  commit range and warns loudly when `BASE_SHA`/`HEAD_SHA` are unset, instead
  of silently passing. Quoted URLs; `curl -fsSL`; revision logging.
  (Signature *matching* logic was verified correct and left unchanged.)
- **Secrets hygiene:** `generate-yarn-npm.sh` uses `umask 077`; `.env` removed
  from version control with a committed `.env.example`; added `.gitignore` and a
  `.dockerignore.example`; parameterized RabbitMQ credentials in
  `docker-compose.yaml`.
- **`BASE_REVISION` is validated before use:** `check-ssh.sh` and
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
- **Empty signer-key guard:** `check-ssh.sh` rejects an empty key fingerprint
  before the `grep -Fxq` allowlist check, so an empty value can never match a
  blank line in the allowlist (defense-in-depth).
- **Generated `.yarnrc.yml` is written with `printf`, not `echo "…\n…"`:** the
  multi-line credential file is now produced shell-agnostically (POSIX `printf`
  interprets `\n` in every shell) instead of relying on the builder's `/bin/sh`
  being dash.

### Added
- **`strapi` template** (`dockerfile.sh`): builds a Strapi headless CMS. Builder
  `orochinetwork/ubuntu:node`; runner defaults to the glibc image
  **`node:22-trixie-slim`** (required — Strapi's native `sharp`/`libvips` break on
  Alpine/musl), still overridable via `-r`/`RUNNER_IMAGE`. Enables `corepack`
  (Yarn 4 berry), sets `NODE_ENV=production`, `EXPOSE 1337`, defaults `CMD` to
  `["npm", "run", "start"]`, and copies a sensible runtime set
  (`config src database public types dist .strapi tsconfig.json package.json
  node_modules favicon.png`) when no `-f` is given. A Strapi build is a node build,
  so the template **reuses the shared `scripts/build-prod-node.sh`** (via a
  `BUILD_SCRIPT_TEMPLATE` indirection) rather than carrying a duplicate build
  script. Exercised by the CI dry-run smoke matrix.
- `generate-checksums.sh` — single source of truth for `checksum.sha256`;
  `generate-ssh-allowed-signers.sh` delegates to it.
- `SECURITY.md`, `CODEOWNERS`, this `CHANGELOG.md`, and an "Adding a new
  template" guide in `DOCKERFILE.md`.
- CI: `.github/workflows/lint-and-test.yml` (shellcheck, `bash -n`,
  checksum-freshness check, and `dockerfile.sh --dry-run` smoke tests). The smoke
  matrix now also covers `strapi`, with an extra assertion that the template keeps
  its glibc runner / corepack / `NODE_ENV=production` / `EXPOSE 1337` contract.

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
