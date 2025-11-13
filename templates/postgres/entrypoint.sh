#!/bin/bash
set -e

# Durable Devdocker PostgreSQL Entrypoint
# Provides dynamic environment variable support for development environments

STATEFILE="$PGDATA/.devdocker-state"
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
        local current_uid=$(id -u postgres)
        local current_gid=$(id -g postgres)
        local target_uid="${DEVDOCKER_UID:-$current_uid}"
        local target_gid="${DEVDOCKER_GID:-$current_gid}"

        if [ "$current_uid" != "$target_uid" ] || [ "$current_gid" != "$target_gid" ]; then
            log "Updating postgres user UID:GID from ${current_uid}:${current_gid} to ${target_uid}:${target_gid}"
            groupmod -g "$target_gid" postgres 2>/dev/null || true
            usermod -u "$target_uid" -g "$target_gid" postgres 2>/dev/null || true

            # Update ownership of data directory
            if [ -n "$PGDATA" ] && [ -d "$PGDATA" ]; then
                log "Updating ownership of $PGDATA"
                chown -R postgres:postgres "$PGDATA"
            fi
        fi
    fi
}

# Apply PostgreSQL extensions
apply_extensions() {
    local target_db="${POSTGRES_DB:-postgres}"

    # Enable extensions specified in POSTGRES_EXTENSIONS
    if [ -n "$POSTGRES_EXTENSIONS" ]; then
        debug "Processing extensions to enable: $POSTGRES_EXTENSIONS"
        IFS=',' read -ra EXTENSIONS <<< "$POSTGRES_EXTENSIONS"
        for ext in "${EXTENSIONS[@]}"; do
            # Trim whitespace
            ext=$(echo "$ext" | xargs)
            if [ -n "$ext" ]; then
                log "Enabling extension: $ext in database $target_db"
                su-exec postgres psql -v ON_ERROR_STOP=0 --username postgres -d "$target_db" <<-EOSQL
                    CREATE EXTENSION IF NOT EXISTS "$ext";
EOSQL
                if [ $? -eq 0 ]; then
                    debug "Successfully enabled extension: $ext"
                else
                    log "Warning: Failed to enable extension: $ext (extension may not be available)"
                fi
            fi
        done
    fi

    # Disable extensions specified in POSTGRES_EXTENSIONS_DISABLE
    if [ -n "$POSTGRES_EXTENSIONS_DISABLE" ]; then
        debug "Processing extensions to disable: $POSTGRES_EXTENSIONS_DISABLE"
        IFS=',' read -ra EXTENSIONS_DISABLE <<< "$POSTGRES_EXTENSIONS_DISABLE"
        for ext in "${EXTENSIONS_DISABLE[@]}"; do
            # Trim whitespace
            ext=$(echo "$ext" | xargs)
            if [ -n "$ext" ]; then
                log "Disabling extension: $ext in database $target_db"
                su-exec postgres psql -v ON_ERROR_STOP=0 --username postgres -d "$target_db" <<-EOSQL
                    DROP EXTENSION IF EXISTS "$ext" CASCADE;
EOSQL
                if [ $? -eq 0 ]; then
                    debug "Successfully disabled extension: $ext"
                else
                    log "Warning: Failed to disable extension: $ext"
                fi
            fi
        done
    fi
}

# Apply dynamic configuration
apply_config() {
    if [ "$DEVDOCKER_SKIP_CONFIG_UPDATE" = "true" ]; then
        debug "Configuration updates disabled"
        return
    fi

    # Check if database is initialized
    if [ ! -s "$PGDATA/PG_VERSION" ]; then
        debug "Database not initialized, skipping config updates"
        return
    fi

    # Start PostgreSQL temporarily for configuration updates
    log "Starting PostgreSQL temporarily for configuration updates"
    su-exec postgres pg_ctl -D "$PGDATA" -o "-c listen_addresses=''" -w start

    # Apply user/database configuration
    if [ -n "$POSTGRES_USER" ] && [ -n "$POSTGRES_PASSWORD" ]; then
        log "Ensuring user '$POSTGRES_USER' exists with current password"
        su-exec postgres psql -v ON_ERROR_STOP=1 --username postgres <<-EOSQL
            DO \$\$
            BEGIN
                IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$POSTGRES_USER') THEN
                    CREATE ROLE "$POSTGRES_USER" WITH LOGIN PASSWORD '$POSTGRES_PASSWORD';
                ELSE
                    ALTER ROLE "$POSTGRES_USER" WITH PASSWORD '$POSTGRES_PASSWORD';
                END IF;
            END
            \$\$;
EOSQL

        if [ -n "$POSTGRES_DB" ]; then
            log "Ensuring database '$POSTGRES_DB' exists"
            su-exec postgres psql -v ON_ERROR_STOP=1 --username postgres <<-EOSQL
                SELECT 'CREATE DATABASE "$POSTGRES_DB" OWNER "$POSTGRES_USER"'
                WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$POSTGRES_DB')\gexec
                GRANT ALL PRIVILEGES ON DATABASE "$POSTGRES_DB" TO "$POSTGRES_USER";
EOSQL
        fi
    fi

    # Apply PostgreSQL extensions configuration
    apply_extensions

    # Stop temporary PostgreSQL
    su-exec postgres pg_ctl -D "$PGDATA" -m fast -w stop

    # Save current state
    {
        echo "POSTGRES_USER=$POSTGRES_USER"
        echo "POSTGRES_DB=$POSTGRES_DB"
        echo "POSTGRES_EXTENSIONS=$POSTGRES_EXTENSIONS"
        echo "POSTGRES_EXTENSIONS_DISABLE=$POSTGRES_EXTENSIONS_DISABLE"
        echo "DEVDOCKER_UID=$DEVDOCKER_UID"
        echo "DEVDOCKER_GID=$DEVDOCKER_GID"
    } > "$STATEFILE"
}

# Main entrypoint logic
main() {
    log "Durable Devdocker PostgreSQL starting"

    # Set default PGDATA if not set
    export PGDATA="${PGDATA:-/var/lib/postgresql/data}"

    # Update UID/GID first
    update_uid_gid

    # Apply configuration updates if not first run
    if [ -f "$STATEFILE" ]; then
        debug "Previous state found, applying configuration updates"
        apply_config
    else
        debug "First run, standard initialization will handle setup"
    fi

    # Call original PostgreSQL entrypoint
    exec docker-entrypoint.sh "$@"
}

main "$@"
