# Security Model — dev-off

`dev-off` is a **root of trust** for Orochi Network's CI/CD. Downstream
repositories (via [`orochi-network/actions`](https://github.com/orochi-network/actions))
fetch and execute scripts from this repo **at runtime**:

```bash
curl -sL https://raw.githubusercontent.com/orochi-network/dev-off/${BASE_REVISION}/check-gpg.sh | bash
```

A compromise of any executable file here runs on **every** downstream CI runner.
Treat changes to this repository with the same care as production secrets.

---

## Threat model

| Asset | Threat | Control |
|-------|--------|---------|
| Executable scripts (`check-*.sh`, `dockerfile.sh`, `generate-yarn-npm.sh`) | Tampering on `main` → RCE on all runners | Signed commits + branch protection; `checksum.sha256` coverage; consumer-side pinning |
| Allowlists (`gpg-list.asc`, `ssh-allowed-signers`) | Unauthorized signer added | `checksum.sha256`; CODEOWNERS review; signed PRs |
| `checksum.sha256` | Edited to match malicious files | Signed commits are the real anchor (a hash is not a signature) |
| Build-time npm token | Leaks into image layers | BuildKit `--mount=type=secret`; credential-file copy guard in `dockerfile.sh` |

## Integrity model — how trust actually flows

1. **`checksum.sha256` covers the executable scripts**, not just the data files.
   Generate it only via `./generate-checksums.sh` (the single source of truth).
   `security.sh` and `generate-ssh-allowed-signers.sh` both delegate to it so the
   covered file set can never drift.

2. **A checksum is not a signature.** Anyone who can write to `main` can edit a
   file *and* its checksum. The real anchor is therefore **branch protection +
   signed commits** (see below). The checksum protects against accidental
   corruption, truncated downloads, and tampering by anyone who does *not* have
   `main` write access (e.g. a CDN/MITM).

3. **Consumers should pin `BASE_REVISION` to a commit SHA or release tag**, not
   `main`. Every script accepts `BASE_REVISION`; the `actions` composite actions
   expose it as the `base_revision` input. Pinning converts "track a moving
   branch" into "run a reviewed, tested release." The scripts validate the value
   before interpolating it into any fetch URL — only a commit SHA, tag, or branch
   name is accepted, and `..` / shell metacharacters are rejected (a malicious
   `BASE_REVISION` could otherwise repoint `curl` at an arbitrary repo/path).

## Required GitHub settings (must be enabled on `main`)

- ✅ Require a pull request before merging, with **≥1 review** (CODEOWNERS).
- ✅ Require **signed commits**.
- ✅ Require status checks to pass (the `lint-and-test` workflow).
- ✅ Disallow force-pushes and branch deletion.

These are repository settings, not code, and must be configured in the GitHub UI
by an admin. They are what make the unsigned `checksum.sha256` trustworthy.

## Build-time credentials

`Dockerfile.template` reads the npm token from a BuildKit secret
(`--mount=type=secret`), which keeps it out of the build context. The credentials
(`.npmrc`/`.yarnrc.yml`) are **created, used, and deleted inside a single build
`RUN`**, so the token never persists in any image layer:

- never copied into the runner image (multi-stage; only `runner` ships);
- `dockerfile.sh` refuses `-f .npmrc|.yarnrc|.yarnrc.yml|.netrc` (source and
  destination, case-insensitive) to prevent accidental copying; and
- absent from **builder-stage** layers too, because the same RUN that writes them
  also removes them (the layer diff contains no credential file).

This is enforced in CI: the `builder-secret-no-leak` job builds the builder stage
with a canary secret and fails if the token is found in the builder image
filesystem. (`mode=0444` on the secret mount lets the non-root build user read
it; if the build fails, `set -e` aborts the RUN so no layer is committed.)

Requires BuildKit (`DOCKER_BUILDKIT=1`, the default with `docker buildx`).

## Reporting a vulnerability

Email **security@orochi.network** (or contact a CODEOWNER directly). Do not open
a public issue for undisclosed vulnerabilities.

## Adding a trusted signer (security boundary)

Adding a key here grants someone authority to sign commits that pass CI.

- **GPG:** add their public key as `gpg/<github-username>.asc`, run
  `./security.sh`, commit `gpg-list.asc` + `checksum.sha256`.
- **SSH:** add their GitHub username to `GITHUB_USERS` in
  `generate-ssh-allowed-signers.sh`, run it, commit `ssh-allowed-signers` +
  `checksum.sha256`. The script prints a drift report comparing GPG vs SSH
  coverage — investigate any warnings.

Both require a reviewed, signed PR approved by a CODEOWNER.

## Follow-ups in the `actions` repo (coordinated changes)

These live in `orochi-network/actions`, not here, but complete the model:

1. **Pre-execution verification:** before piping a script to `bash`, fetch
   `checksum.sha256` and run `sha256sum -c --strict -` on the downloaded script.
   Now possible because the scripts are covered.
2. **Replace `eval "$CMD"`** in `build-docker-template/action.yml` with an
   argument array (`set -- …; "$@"`).
3. **Default `base_revision` to a release tag** instead of `main`, and add the
   input to `configure-auth` (currently it cannot pin).
