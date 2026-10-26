#!/usr/bin/env bash
set -euo pipefail

DSH_HOME="${DSH_HOME:-/home/node/.dsh}"
DSH_PORT="${DSH_PORT:-3080}"

log() { printf '[dsh-docker] %s\n' "$*"; }
die() { printf '[dsh-docker] error: %s\n' "$*" >&2; exit 1; }

if [[ "${DSH_HOST:-}" == "0.0.0.0" || "${DSH_HOST:-}" == "::" ]]; then
  die "DSH_HOST=$DSH_HOST is a wildcard address; DeepSeek Harness rejects wildcard binds. Unset DSH_HOST to bind the container address."
fi

bind_host="${DSH_HOST:-}"
if [[ -z "$bind_host" ]]; then
  bind_host="$(hostname -i 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { print $i; exit } }')"
  if [[ -z "$bind_host" ]]; then
    bind_host="$(hostname -i 2>/dev/null | awk '{ print $1; exit }')"
  fi
  [[ -n "$bind_host" ]] || die "could not determine the container address; set DSH_HOST to one concrete local IP."
fi

public_url="${DSH_PUBLIC_URL:-http://localhost:${DSH_PORT}/}"
public_authority="${public_url#*://}"
public_authority="${public_authority%%/*}"
[[ -n "$public_authority" ]] || die "DSH_PUBLIC_URL=$public_url does not name a host."

mkdir -p "$DSH_HOME" || die "cannot create DSH_HOME=$DSH_HOME"
chmod 700 "$DSH_HOME" 2>/dev/null || true
if [[ -f "$DSH_HOME/.credentials.yaml" ]]; then
  chmod 600 "$DSH_HOME/.credentials.yaml" || die "cannot restrict $DSH_HOME/.credentials.yaml to mode 600"
fi

args=(
  web
  --no-open
  --host "$bind_host"
  --port "$DSH_PORT"
  --public-url "$public_url"
  --trusted-host "$public_authority"
)

if [[ -n "${DSH_TRUSTED_HOSTS:-}" ]]; then
  read -r -a trusted_hosts <<< "${DSH_TRUSTED_HOSTS//,/ }"
  for host in "${trusted_hosts[@]}"; do
    [[ -n "$host" ]] && args+=(--trusted-host "$host")
  done
fi

if [[ -n "${DSH_TLS_CERT:-}" || -n "${DSH_TLS_KEY:-}" ]]; then
  [[ -n "${DSH_TLS_CERT:-}" && -n "${DSH_TLS_KEY:-}" ]] \
    || die "DSH_TLS_CERT and DSH_TLS_KEY must be set together."
  [[ -r "$DSH_TLS_CERT" ]] || die "DSH_TLS_CERT=$DSH_TLS_CERT is not readable."
  [[ -r "$DSH_TLS_KEY" ]] || die "DSH_TLS_KEY=$DSH_TLS_KEY is not readable."
  args+=(--tls-cert "$DSH_TLS_CERT" --tls-key "$DSH_TLS_KEY")
fi

log "data:   $DSH_HOME"
log "bind:   $bind_host:$DSH_PORT"
log "public: $public_url"
log "open the 'dsh web: ...' URL below once; its token sets the browser session cookie."

exec dsh "${args[@]}" "$@"
