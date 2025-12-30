# dev-off

Easy develove &lt;3 Orochi Network

## Check GPG for all commits in a given PR

You can set `BASE_REVISION` environment variable to specify a version of the given script

```bash
curl -sL https://raw.githubusercontent.com/orochi-network/dev-off/main/check-gpg.sh | bash
```

## Docker template

Docker template help our CI/CD alway up to date

### Requirement

All repo must include `./scripts/build-prod.sh`, this will be used to build for building images.

### Node.js Application

- `-t | --template`: Template to use, now we support `node` and `nginx`
  - `node`: Using for Node.js application
  - `nginx`: Using for React.js application or startic website
- `-f | --file`: Selected file to copy
- `-c | --command`: Command to be executed default to `["yarn", "start"]`

```bash
curl -sL https://raw.githubusercontent.com/orochi-network/dev-off/main/dockerfile.sh | bash -- -t node -f package.json -f node_modules -f build -c "[\"yarn\", \"start\"]"
```

### Static website

Build result **MUST** be in `./build`

```bash
curl -sL https://raw.githubusercontent.com/orochi-network/dev-off/main/dockerfile.sh | bash -- -t nginx
```
