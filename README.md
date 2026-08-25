# OpenBao Database Plugin for ClickHouse

This plugin provides ClickHouse database connectivity for [OpenBao](https://openbao.org/), enabling dynamic credential management using SQL user management.

> **Note**: This plugin is adapted from [ContentSquare/vault-plugin-database-clickhouse](https://github.com/ContentSquare/vault-plugin-database-clickhouse) for use with OpenBao instead of HashiCorp Vault.

## Features

- Dynamic user creation with temporary credentials
- Credential rotation and revocation
- TLS connection support
- SQL-based user management
- Role-based access control integration
- ClickHouse cluster support with `ON CLUSTER` syntax

## Prerequisites

- OpenBao 2.4.4 or later (uses SDK v2.4.0)
- ClickHouse 21.8 or later with SQL user management enabled (tested with v25.12)
- Go 1.23+ (for building from source)

### ClickHouse Requirements

ClickHouse must be configured to use SQL-based user management instead of the default XML-based configuration. This requires:

1. A user with `access_management=1` permission (typically the `default` user)
2. Database roles defined in advance if you want to assign roles to dynamic users

## Building the Plugin

```bash
# Clone the repository
git clone https://github.com/elaunira/openbao-plugin-database-clickhouse.git
cd openbao-plugin-database-clickhouse

# Build the plugin
make build

# Or with a specific version
make build VERSION=v2.4.4

# Calculate SHA256 checksum (needed for plugin registration)
sha256sum clickhouse-database-plugin
```

## Plugin Registration

### 1. Copy the Plugin Binary

Copy the compiled plugin binary to the OpenBao plugin directory:

```bash
# Create plugin directory if it doesn't exist
sudo mkdir -p /etc/openbao/plugins

# Copy the plugin
sudo cp clickhouse-database-plugin /etc/openbao/plugins/

# Set appropriate permissions
sudo chmod 755 /etc/openbao/plugins/clickhouse-database-plugin
```

### 2. Configure OpenBao

Ensure your OpenBao configuration includes the plugin directory:

```hcl
# /etc/openbao/config.hcl
plugin_directory = "/etc/openbao/plugins"

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true  # Set to false in production with proper TLS
}

storage "file" {
  path = "/var/lib/openbao/data"
}
```

### 3. Register the Plugin

```bash
# Get the SHA256 checksum of the plugin
PLUGIN_SHA256=$(sha256sum /etc/openbao/plugins/clickhouse-database-plugin | cut -d' ' -f1)

# Register the plugin
bao plugin register -sha256=$PLUGIN_SHA256 database clickhouse-database-plugin
```

### 4. Enable the Database Secrets Engine

```bash
bao secrets enable database
```

## Container Image

A prebuilt OpenBao image with this plugin already installed is published to GitHub
Container Registry on every `v*` tag by the `Docker` workflow
(`.github/workflows/docker.yml`); it can also be run manually via
`workflow_dispatch`:

```bash
# Alpine flavour (default)
docker pull ghcr.io/digitalis-io/openbao-plugin-database-clickhouse:latest

# UBI flavour
docker pull ghcr.io/digitalis-io/openbao-plugin-database-clickhouse:latest-ubi
```

Images are built for `linux/amd64` and `linux/arm64`, based on the upstream
`openbao/openbao` and `openbao/openbao-ubi` images. The plugin binary lives at
`/openbao/plugins/clickhouse-database-plugin`.

The plugin self-reports the tag it was built from, so a `v1.2.3` tag produces a
plugin registered in the catalog as `v1.2.3`. The workflow fails fast if the tag
is not a valid semantic version; builds from `workflow_dispatch` on a branch are
stamped `v0.0.0-dev.g<short-sha>`.

### Running

The default command starts a dev-mode server with the plugin directory already
registered:

```bash
docker run --rm -p 8200:8200 ghcr.io/digitalis-io/openbao-plugin-database-clickhouse:latest

export BAO_ADDR=http://127.0.0.1:8200
export BAO_TOKEN=root
bao plugin list database   # clickhouse-database-plugin is listed
```

For production, mount a config file that declares the plugin directory and
register the plugin explicitly:

```hcl
# /openbao/config/bao.hcl
plugin_directory = "/openbao/plugins"

storage "file" {
  path = "/openbao/file"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = false
  tls_cert_file = "/openbao/config/tls.crt"
  tls_key_file  = "/openbao/config/tls.key"
}
```

```bash
docker run -d --name openbao \
  -p 8200:8200 \
  -v "$PWD/config:/openbao/config" \
  -v openbao-data:/openbao/file \
  ghcr.io/digitalis-io/openbao-plugin-database-clickhouse:latest \
  server -config=/openbao/config/bao.hcl
```

### Building Locally

```bash
# Alpine flavour
make docker-build

# UBI flavour
make docker-build-ubi

# Dev-mode server on http://127.0.0.1:8200 with the plugin registered
make docker-run

# Multi-arch build (add PUSH=true to publish; multi-arch images cannot be
# loaded into the local Docker daemon)
make docker-buildx PUSH=true IMAGE_TAG=1.0.0

# Pin the OpenBao base version and stamp the plugin version
make docker-build OPENBAO_VERSION=2.4.4 PLUGIN_VERSION=1.0.0 IMAGE_TAG=1.0.0
```

| Variable | Default | Purpose |
|----------|---------|---------|
| `IMAGE` | `ghcr.io/digitalis-io/openbao-plugin-database-clickhouse` | Image name |
| `IMAGE_TAG` | `local` | Image tag (`-ubi` appended for the UBI flavour) |
| `OPENBAO_VERSION` | `2.4.4` | OpenBao base image version |
| `PLUGIN_VERSION` | `v0.0.0-dev` | Version the plugin self-reports |
| `PLATFORMS` | `linux/amd64,linux/arm64` | Platforms for `docker-buildx` |
| `PUSH` | unset | Set to `true` to push from `docker-buildx` |

The equivalent raw Docker commands are `docker build --load --target default .`
and `docker build --load --target ubi .`.

`PLUGIN_VERSION` must be a valid semantic version with a leading `v`. OpenBao
rejects plugins that self-report a non-semver version, and its catalog lookups
normalise to a `v` prefix — a plugin stamped `1.0.0` registers as `1.0.0` but is
then looked up as `v1.0.0` and reported as "plugin not found in the catalog".

## Usage

The plugin is registered and used with the name `clickhouse-database-plugin`. This name is:
- The binary filename produced by `make build`
- The name used when registering with `bao plugin register`
- The value for `plugin_name` in database configuration

Quick reference:

```bash
# Register the plugin
bao plugin register -sha256=$PLUGIN_SHA256 database clickhouse-database-plugin

# Configure a connection (plugin_name must be clickhouse-database-plugin)
bao write database/config/my-clickhouse \
    plugin_name=clickhouse-database-plugin \
    allowed_roles="*" \
    connection_url="clickhouse://{{username}}:{{password}}@localhost:9000/default" \
    username="admin" \
    password="secret"

# Create a role
bao write database/roles/my-role \
    db_name=my-clickhouse \
    creation_statements="CREATE USER IF NOT EXISTS '{{name}}' IDENTIFIED BY '{{password}}'" \
    default_ttl="1h" \
    max_ttl="24h"

# Generate credentials
bao read database/creds/my-role
```

## Configuration

### Basic Configuration

```bash
bao write database/config/clickhouse \
    plugin_name=clickhouse-database-plugin \
    allowed_roles="*" \
    connection_url="clickhouse://{{username}}:{{password}}@clickhouse.example.com:9000/default" \
    username="admin" \
    password="admin_password"
```

### Configuration with TLS

For secure connections (port 9440), add `secure=true`:

```bash
bao write database/config/clickhouse \
    plugin_name=clickhouse-database-plugin \
    allowed_roles="*" \
    connection_url="clickhouse://{{username}}:{{password}}@clickhouse.example.com:9440/default?secure=true" \
    username="admin" \
    password="admin_password"
```

### Configuration with TLS and Skip Verification

For self-signed certificates:

```bash
bao write database/config/clickhouse \
    plugin_name=clickhouse-database-plugin \
    allowed_roles="*" \
    connection_url="clickhouse://{{username}}:{{password}}@clickhouse.example.com:9440/default?secure=true&skip_verify=true" \
    username="admin" \
    password="admin_password"
```

### Configuration Parameters

| Parameter | Description | Required |
|-----------|-------------|----------|
| `connection_url` | ClickHouse connection URL | Yes (or use host/port) |
| `host` | ClickHouse server hostname | Yes (if no connection_url) |
| `port` | ClickHouse server port (9000 for native, 9440 for TLS) | Yes (if no connection_url) |
| `username` | Admin username for managing users | Yes |
| `password` | Admin password | Yes |
| `database` | Default database name | No |
| `tls` | Enable TLS connection | No (default: false) |
| `tls_skip_verify` | Skip TLS certificate verification | No (default: false) |
| `max_open_connections` | Maximum open connections | No (default: 4) |
| `max_idle_connections` | Maximum idle connections | No (default: max_open) |
| `max_connection_lifetime` | Connection lifetime in seconds | No (default: 0/unlimited) |
| `username_template` | Template for generating usernames | No |

## Creating Roles

### Basic Role

```bash
bao write database/roles/my-role \
    db_name=clickhouse \
    creation_statements="CREATE USER IF NOT EXISTS '{{name}}' IDENTIFIED BY '{{password}}'" \
    default_ttl="1h" \
    max_ttl="24h"
```

### Role with Database Permissions

```bash
bao write database/roles/readonly \
    db_name=clickhouse \
    creation_statements="CREATE USER IF NOT EXISTS '{{name}}' IDENTIFIED BY '{{password}}'; GRANT SELECT ON mydb.* TO '{{name}}'" \
    revocation_statements="DROP USER IF EXISTS '{{name}}'" \
    default_ttl="1h" \
    max_ttl="24h"
```

### Role with ClickHouse Role Assignment

First, create a role in ClickHouse:

```sql
CREATE ROLE readonly_role;
GRANT SELECT ON mydb.* TO readonly_role;
```

Then create an OpenBao role that assigns this ClickHouse role:

```bash
bao write database/roles/readonly \
    db_name=clickhouse \
    creation_statements="CREATE USER IF NOT EXISTS '{{name}}' IDENTIFIED BY '{{password}}'; GRANT readonly_role TO '{{name}}'" \
    revocation_statements="REVOKE readonly_role FROM '{{name}}'; DROP USER IF EXISTS '{{name}}'" \
    default_ttl="1h" \
    max_ttl="24h"
```

### Role for ClickHouse Cluster

For ClickHouse clusters, use `ON CLUSTER`:

```bash
bao write database/roles/cluster-role \
    db_name=clickhouse \
    creation_statements="CREATE USER IF NOT EXISTS '{{name}}' ON CLUSTER 'my_cluster' IDENTIFIED BY '{{password}}'; GRANT SELECT ON mydb.* TO '{{name}}' ON CLUSTER 'my_cluster'" \
    revocation_statements="DROP USER IF EXISTS '{{name}}' ON CLUSTER 'my_cluster'" \
    default_ttl="1h" \
    max_ttl="24h"
```

## Generating Credentials

```bash
# Generate new credentials
bao read database/creds/my-role

# Example output:
# Key                Value
# ---                -----
# lease_id           database/creds/my-role/abcd1234
# lease_duration     1h
# lease_renewable    true
# password           A1B2C3D4E5F6G7H8
# username           v-token-my-role-abc123def456-1234567890
```

## Statement Template Variables

The following variables are available in creation, revocation, and rotation statements:

| Variable | Description |
|----------|-------------|
| `{{name}}` | Generated username |
| `{{username}}` | Alias for `{{name}}` |
| `{{password}}` | Generated password |
| `{{expiration}}` | Credential expiration time |

## Rotating Root Credentials

```bash
bao write -force database/rotate-root/clickhouse
```

## Username Templates

You can customize the username format using Go template syntax:

```bash
bao write database/config/clickhouse \
    plugin_name=clickhouse-database-plugin \
    allowed_roles="*" \
    connection_url="clickhouse://{{username}}:{{password}}@clickhouse.example.com:9000/default" \
    username="admin" \
    password="admin_password" \
    username_template="{{ printf \"myapp-%s-%s\" (.RoleName | truncate 10) (random 8) }}"
```

Available template functions:
- `random N` - Generate N random characters
- `truncate N` - Truncate to N characters
- `uppercase` / `lowercase` - Case conversion
- `unix_time` - Current Unix timestamp
- `uuid` - Generate UUID

## Testing

Run tests with Docker:

```bash
go test -v ./...
```

Or with an existing ClickHouse instance:

```bash
CLICKHOUSE_URL="clickhouse://localhost:9000?username=default&password=password" go test -v ./...
```

## Troubleshooting

### Plugin not found

Ensure the plugin binary is in the configured plugin directory and has execute permissions:

```bash
ls -la /etc/openbao/plugins/clickhouse-database-plugin
```

### Connection errors

Verify ClickHouse connectivity:

```bash
# Using clickhouse-client
clickhouse-client --host clickhouse.example.com --port 9000 --user admin --password admin_password

# Or using the native protocol
nc -zv clickhouse.example.com 9000
```

### Permission errors

Ensure the admin user has `access_management=1`:

```sql
SHOW GRANTS FOR admin;
```

### TLS issues

For self-signed certificates, use `skip_verify=true` in the connection URL:

```
clickhouse://host:9440?secure=true&skip_verify=true
```

## License

This project is licensed under the Mozilla Public License 2.0 (MPL-2.0).

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## Acknowledgments

This plugin is adapted from [ContentSquare/vault-plugin-database-clickhouse](https://github.com/ContentSquare/vault-plugin-database-clickhouse) for use with OpenBao.
