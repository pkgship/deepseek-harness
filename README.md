# DeepSeek Harness Docker image

Container packaging for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (`dsh`), the open-source agent harness from DeepSeek AI. The image installs the official `@deepseek-ai/dsh` npm package and serves the Web UI as the unprivileged `node` user (UID 1000).

This is a community packaging repository, not an official DeepSeek AI image. DeepSeek Harness is developer-preview software: review its [safety notice](https://github.com/deepseek-ai/deepseek-harness/blob/master/SAFETY.md) before exposing it to anything.

## What this image does differently

The commonly referenced [Docker recipe](https://github.com/deepseek-ai/deepseek-harness/discussions/1762) predates native non-loopback binding and wraps DSH in a Node reverse proxy. Current DSH versions accept one concrete local IP with `dsh web --host`, so this image runs DSH directly:

- No proxy process, no Host/Origin rewrite, and no authentication bypass. DSH's launch-token login and its Host/Origin fence stay in force.
- The old `crypto.randomUUID` HTML injection is unnecessary; current DSH uses a cross-runtime UUID helper that works on plain-HTTP LAN origins.
- The container binds its own interface address, which Docker port publishing can reach. Wildcard binds remain rejected by DSH.

A reverse proxy is still the right tool for listener TLS or a URL path prefix; when you use one, follow the [upstream proxy requirements](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/user/guide/public-deployments.md): preserve `Host`, forward WebSocket upgrades, and strip the mount prefix.

## Quick start

```sh
docker run -d --name dsh \
  -p 3080:3080 \
  -v dsh-home:/home/node/.dsh \
  -v dsh-workspace:/workspace \
  --restart unless-stopped \
  pkgship/deepseek-harness:latest

docker logs -f dsh
```

Open the line that starts with `dsh web:`:

```
dsh web: http://localhost:3080/?token=...
```

The token is a one-time credential. Opening the URL exchanges it for a signed, HttpOnly session cookie and redirects to `/`. The cookie is bound to the authority in the URL and lasts 30 days by default. If you lose the token, restart the container to print a new one; an existing cookie keeps working.

If port 3080 is already taken, map another host port and advertise it:

```sh
docker run -d --name dsh \
  -p 8080:3080 \
  -e DSH_PUBLIC_URL=http://localhost:8080/ \
  -v dsh-home:/home/node/.dsh \
  -v dsh-workspace:/workspace \
  --restart unless-stopped \
  pkgship/deepseek-harness:latest
```

Or use the included `docker-compose.yml`:

```sh
docker compose up -d
docker compose logs -f dsh
```

## Accessing from another machine

Set `DSH_PUBLIC_URL` to the address the browser actually uses. The image adds its authority and its bare hostname to DSH's `--trusted-host` list, so the Host fence accepts that host on any published port:

```sh
docker run -d --name dsh \
  -p 3080:3080 \
  -e DSH_PUBLIC_URL=http://192.168.1.50:3080/ \
  -v dsh-home:/home/node/.dsh \
  -v dsh-workspace:/workspace \
  --restart unless-stopped \
  pkgship/deepseek-harness:latest
```

Then open the `dsh web: http://192.168.1.50:3080/?token=...` line from the logs.

For additional names, such as a DNS name that reaches the same server, set `DSH_TRUSTED_HOSTS` (comma or space separated). A `host:port` entry matches exactly; a bare `host` entry matches any port.

Plain HTTP on a LAN sends the launch token and session cookie unencrypted. Use a trusted network, listener TLS (below), or an HTTPS reverse proxy.

## Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `DSH_HOST` | first container IPv4 | Concrete local IP to bind. Wildcards such as `0.0.0.0` are rejected. Leave unset normally. |
| `DSH_PORT` | `3080` | Listener port inside the container. |
| `DSH_PUBLIC_URL` | `http://localhost:<DSH_PORT>/` | Browser-facing address. Sets the printed login URL, `DSH_WEB_URL`, and the trusted authority (`host:port` and `host`, so a republished host port still passes the fence). |
| `DSH_TRUSTED_HOSTS` | – | Extra accepted authorities, comma or space separated. |
| `DSH_TLS_CERT` | – | PEM certificate chain for the listener. Requires `DSH_TLS_KEY`. |
| `DSH_TLS_KEY` | – | Unencrypted PEM private key. Requires `DSH_TLS_CERT`. |
| `DSH_HOME` | `/home/node/.dsh` | Harness home. Persist it. |

Any arguments after the image name are appended to `dsh web`, for example `--patch /config/extra.yml`.

### TLS on the listener

```sh
docker run -d --name dsh \
  -p 3080:3080 \
  -v "$PWD/certs:/certs:ro" \
  -e DSH_PUBLIC_URL=https://dsh.example.com:3080/ \
  -e DSH_TLS_CERT=/certs/fullchain.pem \
  -e DSH_TLS_KEY=/certs/privkey.pem \
  -v dsh-home:/home/node/.dsh \
  --restart unless-stopped \
  pkgship/deepseek-harness:latest
```

The certificate must cover the hostname or IP the browser opens, and both files must be readable by UID 1000. With a reverse proxy or tunnel in front, terminate TLS there instead and keep `DSH_PUBLIC_URL` on the external HTTPS URL.

## Data, workspace, and permissions

- `/home/node/.dsh` holds credentials, profiles, sessions, attachments, and the browser-session signing secret. `/workspace` is the default working directory and the recommended workspace mount for the agent.
- Mount either as a named volume or as a host directory; nothing has to be prepared on the host. The entrypoint gives `DSH_HOME` to UID 1000, sets `DSH_HOME` to mode `700` and `.credentials.yaml` to `600` (matching DSH's credential check), then runs DSH as `node`.
- Both paths are declared as image mount points (`VOLUME` in the Dockerfile), so `docker inspect` and container managers list them without being told the paths. The trade-off: `docker run` without `-v` puts the data in anonymous volumes that outlive the container, so clean them up with `docker volume ls` and `docker volume prune` if you experiment.

## Image variants and tags

| Tag | Contents |
| --- | --- |
| `latest` | DSH, Node 24, git, curl, procps, pnpm, uv |
| `devtools-latest` | Everything above plus build-essential, python3, OpenSSH client, vim, nano, jq, htop, tmux, tree, zip/unzip, wget, openssl, bash-completion |
| `dsh-<version>` | Pinned DSH release, for example `dsh-0.2.1-rc.2` |
| `devtools-dsh-<version>` | The same DSH release with development tools |

`pnpm` is needed by `dsh plugin` and the community plugin market; `uv`/`uvx` are needed by MCP servers that launch through them. Use `devtools-latest` when you compile native plugins or node-pty addons inside the container.

Every build also gets a `sha-<commit>` tag and a `dsh-<version>` tag for the resolved `@deepseek-ai/dsh` release. For git tags such as `v1.0.0`, builds get version tags too. The devtools variant prefixes all of them with `devtools-` (`devtools-sha-...`, `devtools-dsh-...`).

All tags are published on Docker Hub as `pkgship/deepseek-harness`, for example `pkgship/deepseek-harness:devtools-latest`.

## Building and publishing

The GitHub Actions workflow in [`.github/workflows/docker.yml`](.github/workflows/docker.yml) builds both variants for `linux/amd64` and `linux/arm64` and pushes them to Docker Hub as `pkgship/deepseek-harness`, authenticating with the `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` repository secrets:

- daily schedule (02:15 UTC) → resolve the npm `latest` dist-tag and build only if `dsh-<version>` or `devtools-dsh-<version>` is missing
- push to `main` → `latest` / `devtools-latest`
- push a `v*` tag → semver tags
- pull request → amd64 build only, no push
- manual dispatch → optional `dsh_version` input with an exact version or dist-tag; empty means `latest`

Every build installs the exact version resolved by the upstream job, so a build never changes under your feet.

### Automatic upstream tracking

The schedule checks `https://registry.npmjs.org/@deepseek-ai/dsh/latest` once a day. Unless both `dsh-<version>` and `devtools-dsh-<version>` already exist on Docker Hub, it rebuilds both variants, refreshes `latest`, and adds the version tags. This follows npm's `latest` dist-tag, which is what the image installs; a GitHub release that is not published to that dist-tag (or a version only available under `next`) will not trigger it, but you can build it with manual dispatch. Scheduled workflows only run once this file is on the default branch.

Local build:

```sh
docker build -t dsh .
docker build --build-arg INSTALL_DEVTOOLS=1 -t dsh:devtools .
docker build --build-arg DSH_VERSION=0.2.1-rc.2 -t dsh:pinned .
```

## Upgrading

Pull a newer image and recreate the container; `DSH_HOME` survives. The launch token rotates on every process start, while an existing browser cookie remains valid until it expires.

`latest` follows npm's `latest` dist-tag within a day when upstream publishes a new release. DeepSeek Harness changes quickly and has had breaking releases, so a production deployment may prefer a `dsh-<version>` tag and a deliberate update; the workflow's `dsh_version` input and the `DSH_VERSION` build arg both accept an exact version.

## Security notes

- DSH runs model-generated commands as UID 1000; the container starts as root only for the entrypoint's ownership step. A container is not a hard security boundary; mount only the directories the agent should touch, and never mount the Docker socket, SSH keys, or unrelated credentials.
- The printed URL contains a process credential. Do not paste it into issue trackers, logs, or chat.
- Do not expose the port to untrusted networks over plain HTTP. Prefer listener TLS or an HTTPS reverse proxy.
- Changing the browser-session secret is the global logout mechanism: delete the `client-connection/browser-session` entry under `records:` in `.credentials.yaml` and restart. Every issued cookie is then invalid.

## License

DeepSeek Harness is MIT-licensed. This packaging repository contains only build and deployment files.
