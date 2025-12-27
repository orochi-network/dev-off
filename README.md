# dev-off

Easy develove &lt;3 Orochi Network

## How to run check GPG for all commits

```bash
curl -sL https://raw.githubusercontent.com/orochi-network/dev-off/refs/heads/main/check-gpg.sh | bash
```

## How to run yarn setup

```bash
curl -sL https://raw.githubusercontent.com/orochi-network/dev-off/main/yarn-setup.sh | bash -s -- --lint
```

### Usage

```yaml
- name: Setup Yarn
- run: curl -sL https://raw.githubusercontent.com/orochi-network/dev-off/main/yarn-setup.sh | bash -s -- --lint
  env:
    NPM_ACCESS_TOKEN: ${{ secrets.NPM_ACCESS_TOKEN }}
```
