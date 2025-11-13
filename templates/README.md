# Durable Devdocker Image Templates

This directory contains templates for generating Durable Devdocker images for various database systems.

## Structure

Each database type has its own directory containing:
- `Dockerfile.template` - Template for the Dockerfile with `{{VERSION}}` placeholder
- `entrypoint.sh` - Entrypoint script that provides dynamic environment variable support

## Supported Databases

- **mysql** - MySQL/MariaDB with dynamic user and database management
- **postgres** - PostgreSQL with dynamic role and schema configuration
- **redis** - Redis with dynamic configuration updates
- **mongodb** - MongoDB with dynamic user and authentication changes

## Template Variables

Templates use the following placeholders:
- `{{VERSION}}` - Replaced with the specific version tag (e.g., `8.0.44`, `16-alpine`)

## Building Images

Use the `build.sh` script in the project root to generate and build images:

```bash
# Generate all images (templates → build/)
./build.sh

# Generate only MySQL images
./build.sh --db mysql

# Generate and build all images
./build.sh --build

# Generate and build specific database
./build.sh --db postgres --build

# Generate, build, and push to registry
./build.sh --push
```

The build script will:
1. Fetch Docker image versions released in the last 6 months from Docker Hub
2. Generate Dockerfiles from templates for each version
3. Optionally build and push the images

## Adding a New Database

To add support for a new database type:

1. Create a new directory: `templates/newdb/`
2. Create `Dockerfile.template` with the base image and entrypoint setup
3. Create `entrypoint.sh` with dynamic configuration logic
4. Make the entrypoint executable: `chmod +x templates/newdb/entrypoint.sh`
5. Run the build script: `./build.sh --db newdb`

## Entrypoint Script Guidelines

Each entrypoint script should:

1. **Check for configuration updates** - Compare current environment variables with saved state
2. **Apply changes dynamically** - Update users, databases, permissions as needed
3. **Support UID/GID changes** - Allow setting `DEVDOCKER_UID` and `DEVDOCKER_GID`
4. **Save state** - Record current configuration for comparison on next restart
5. **Call original entrypoint** - Chain to the official image's entrypoint script
6. **Provide logging** - Support `DEVDOCKER_VERBOSE` for detailed output
7. **Allow opt-out** - Respect `DEVDOCKER_SKIP_CONFIG_UPDATE` to disable dynamic behavior

## Example Entrypoint Pattern

```bash
#!/bin/bash
set -e

STATEFILE="/path/to/.devdocker-state"

# Update UID/GID if specified
update_uid_gid() {
    # Change service user UID/GID
    # Update file ownership
}

# Apply dynamic configuration
apply_config() {
    if [ "$DEVDOCKER_SKIP_CONFIG_UPDATE" = "true" ]; then
        return
    fi

    # Start service temporarily
    # Apply configuration changes
    # Stop service
    # Save state
}

# Main logic
main() {
    update_uid_gid

    if [ -f "$STATEFILE" ]; then
        apply_config
    fi

    exec docker-entrypoint.sh "$@"
}

main "$@"
```

## Version Selection

By default, the build script fetches versions from the last 6 months. Use `--fallback` to get the latest N versions instead:

```bash
./build.sh --fallback
```

This is useful for testing or when the Docker Hub API is unavailable.
