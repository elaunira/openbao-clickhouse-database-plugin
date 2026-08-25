# syntax=docker/dockerfile:1.9

# OpenBao image bundled with the ClickHouse database secrets plugin.
#
# Modelled on the upstream OpenBao Dockerfile
# (https://github.com/openbao/openbao/blob/main/Dockerfile): the plugin binary
# is produced in a helper stage so the resulting layer is identical no matter
# which base flavour it is copied into, and the same file permissions are
# applied everywhere.

ARG OPENBAO_VERSION=2.4.4
ARG GO_VERSION=1.26.3

# ---------------------------------------------------------------------------
# Build the plugin. Runs on the build platform and cross-compiles to TARGETARCH
# so multi-arch builds do not need emulation.
# ---------------------------------------------------------------------------
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine AS builder

ARG TARGETARCH
ARG VERSION=v0.0.0-dev

WORKDIR /src

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download

COPY . .

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" \
      -o /out/clickhouse-database-plugin ./cmd/clickhouse-database-plugin

# ---------------------------------------------------------------------------
# Helper stage: fixes the path and permissions of the plugin binary once, so
# every flavour below copies an identical layer.
# ---------------------------------------------------------------------------
FROM scratch AS plugin
COPY --chmod=555 --from=builder /out/clickhouse-database-plugin /openbao/plugins/clickhouse-database-plugin

# ---------------------------------------------------------------------------
# Alpine flavour — based on openbao/openbao.
# ---------------------------------------------------------------------------
FROM openbao/openbao:${OPENBAO_VERSION} AS default

LABEL org.opencontainers.image.title="openbao-clickhouse" \
      org.opencontainers.image.description="OpenBao with the ClickHouse database secrets plugin preinstalled" \
      org.opencontainers.image.source="https://github.com/digitalis-io/openbao-plugin-database-clickhouse" \
      org.opencontainers.image.licenses="MPL-2.0"

USER root
RUN mkdir -p /openbao/plugins
COPY --from=plugin /openbao/plugins/clickhouse-database-plugin /openbao/plugins/clickhouse-database-plugin
RUN chown -R openbao:openbao /openbao/plugins
USER openbao

# The plugin directory must also be declared in the server configuration:
#   plugin_directory = "/openbao/plugins"
ENV BAO_PLUGIN_DIR=/openbao/plugins

EXPOSE 8200

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["server", "-dev", "-dev-no-store-token", "-dev-plugin-dir=/openbao/plugins"]

# ---------------------------------------------------------------------------
# UBI flavour — based on openbao/openbao-ubi.
# ---------------------------------------------------------------------------
FROM openbao/openbao-ubi:${OPENBAO_VERSION} AS ubi

LABEL org.opencontainers.image.title="openbao-clickhouse" \
      org.opencontainers.image.description="OpenBao with the ClickHouse database secrets plugin preinstalled" \
      org.opencontainers.image.source="https://github.com/digitalis-io/openbao-plugin-database-clickhouse" \
      org.opencontainers.image.licenses="MPL-2.0"

USER root
RUN mkdir -p /openbao/plugins
COPY --from=plugin /openbao/plugins/clickhouse-database-plugin /openbao/plugins/clickhouse-database-plugin
RUN chown -R openbao /openbao/plugins && \
    chgrp -R 0 /openbao/plugins && chmod -R g+rwX /openbao/plugins
USER openbao

ENV BAO_PLUGIN_DIR=/openbao/plugins

EXPOSE 8200

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["server", "-dev", "-dev-no-store-token", "-dev-plugin-dir=/openbao/plugins"]
