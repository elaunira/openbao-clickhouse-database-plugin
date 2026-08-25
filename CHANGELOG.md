# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Go toolchain bumped to 1.26.3 (`go.mod`, CI workflows and the container build)
  and all Go module dependencies updated to their latest releases, including
  `github.com/ClickHouse/clickhouse-go/v2` v2.48.0 and
  `github.com/openbao/openbao/sdk/v2` v2.6.2.

### Added

- Container image bundling OpenBao with the ClickHouse database plugin
  preinstalled at `/openbao/plugins`, in alpine (`openbao/openbao`) and UBI
  (`openbao/openbao-ubi`) flavours.
- GitHub Actions `Docker` workflow that builds both flavours for
  `linux/amd64` and `linux/arm64` and publishes them to GHCR on every `v*`
  tag, with an SBOM, a build provenance attestation and a post-push smoke
  test. The plugin version is taken from the tag and the build fails if the
  tag is not valid semver.
- `docker-compose.yml` test stack: ClickHouse with SQL access management plus a
  dev-mode OpenBao, with the database secrets engine, a ClickHouse connection
  and a `readonly` role configured automatically.
- CI `e2e` job that brings up the `docker-compose.yml` stack, configures the
  secrets engine, issues a dynamic credential, authenticates to ClickHouse with
  it and verifies the user is dropped when the lease is revoked.
- Makefile targets `docker-build`, `docker-build-ubi`, `docker-buildx`,
  `docker-run`, `compose-up`, `compose-down`, `compose-logs` and
  `compose-test`.
