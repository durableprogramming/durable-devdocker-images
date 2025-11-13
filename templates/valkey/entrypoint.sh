#!/bin/bash
set -e

# Durable Devdocker Valkey Entrypoint
# Provides dynamic environment variable support for development environments

STATEFILE="/data/.devdocker-state"
VERBOSE="${DEVDOCKER_VERBOSE:-false}"

log() {
    echo "[devdocker] $*"
}

debug() {
    if [ "$VERBOSE" = "true" ]; then
        log "DEBUG: $*"
    fi
}

# Update UID/GID if specified
update_uid_gid() {
    if [ -n "$DEVDOCKER_UID" ] || [ -n "$DEVDOCKER_GID" ]; then
        local current_uid=$(id -u valkey)
        local current_gid=$(id -g valkey)
        local target_uid="${DEVDOCKER_UID:-$current_uid}"
        local target_gid="${DEVDOCKER_GID:-$current_gid}"

        if [ "$current_uid" != "$target_uid" ] || [ "$current_gid" != "$target_gid" ]; then
            log "Updating valkey user UID:GID from ${current_uid}:${current_gid} to ${target_uid}:${target_gid}"
            groupmod -g "$target_gid" valkey 2>/dev/null || true
            usermod -u "$target_uid" -g "$target_gid" valkey 2>/dev/null || true

            # Update ownership of data directory
            if [ -d "/data" ]; then
                log "Updating ownership of /data"
                chown -R valkey:valkey /data
            fi
        fi
    fi
}

# Apply dynamic configuration
apply_config() {
    if [ "$DEVDOCKER_SKIP_CONFIG_UPDATE" = "true" ]; then
        debug "Configuration updates disabled"
        return
    fi

    # Save current state
    {
        echo "DEVDOCKER_UID=$DEVDOCKER_UID"
        echo "DEVDOCKER_GID=$DEVDOCKER_GID"
    } > "$STATEFILE"
}

# Main entrypoint logic
main() {
    log "Durable Devdocker Valkey starting"

    # Update UID/GID first
    update_uid_gid

    # Apply configuration updates
    apply_config

    # Call original Valkey entrypoint
    exec docker-entrypoint.sh "$@"
}

main "$@"
