# syntax=docker/dockerfile:1

ARG NODE_IMAGE=node:24-bookworm-slim

FROM ghcr.io/astral-sh/uv:0.13 AS uv

FROM ${NODE_IMAGE} AS dsh

ARG DSH_VERSION=latest

# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates python3 make g++ \
 && rm -rf /var/lib/apt/lists/*

RUN npm install --prefix /opt/dsh --no-audit --no-fund "@deepseek-ai/dsh@${DSH_VERSION}" \
 && test -e /opt/dsh/node_modules/.bin/dsh

FROM ${NODE_IMAGE}

ARG INSTALL_DEVTOOLS=0

LABEL org.opencontainers.image.title="DeepSeek Harness (Docker)" \
      org.opencontainers.image.description="Container image for the DeepSeek Harness Web UI" \
      org.opencontainers.image.source="https://github.com/pkgship/deepseek-harness" \
      org.opencontainers.image.licenses="MIT"

ENV LANG=C.UTF-8 \
    HOME=/home/node \
    DSH_HOME=/home/node/.dsh \
    DSH_PORT=3080

# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      procps \
      tini \
 && if [ "$INSTALL_DEVTOOLS" = "1" ]; then \
      apt-get install -y --no-install-recommends \
        bash-completion \
        build-essential \
        htop \
        jq \
        nano \
        openssh-client \
        openssl \
        python3 \
        tmux \
        tree \
        unzip \
        vim \
        wget \
        zip; \
    fi \
 && rm -rf /var/lib/apt/lists/*

COPY --from=uv /uv /uvx /usr/local/bin/
COPY --from=dsh /opt/dsh /opt/dsh

RUN ln -s /opt/dsh/node_modules/.bin/dsh /usr/local/bin/dsh \
 && npm install -g --no-audit --no-fund pnpm@12 \
 && npm cache clean --force \
 && mkdir -p "$DSH_HOME" /workspace \
 && chown -R node:node "$DSH_HOME" /workspace \
 && chmod 700 "$DSH_HOME"

COPY docker/entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 755 /usr/local/bin/docker-entrypoint.sh

# hadolint ignore=DL3066
USER node
RUN dsh --version

WORKDIR /workspace

EXPOSE 3080

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
