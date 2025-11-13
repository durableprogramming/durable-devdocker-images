#!/bin/bash
set -e

# Durable Devdocker MySQL Entrypoint
# Provides dynamic environment variable support for development environments

STATEFILE="/var/lib/mysql/.devdocker-state"
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
        local current_uid=$(id -u mysql)
        local current_gid=$(id -g mysql)
        local target_uid="${DEVDOCKER_UID:-$current_uid}"
        local target_gid="${DEVDOCKER_GID:-$current_gid}"

        if [ "$current_uid" != "$target_uid" ] || [ "$current_gid" != "$target_gid" ]; then
            log "Updating mysql user UID:GID from ${current_uid}:${current_gid} to ${target_uid}:${target_gid}"
            groupmod -g "$target_gid" mysql 2>/dev/null || true
            usermod -u "$target_uid" -g "$target_gid" mysql 2>/dev/null || true

            # Update ownership of data directory
            if [ -d "/var/lib/mysql" ]; then
                log "Updating ownership of /var/lib/mysql"
                chown -R mysql:mysql /var/lib/mysql
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

    # Check if database is initialized
    if [ ! -d "/var/lib/mysql/mysql" ]; then
        debug "Database not initialized, skipping config updates"
        return
    fi

    # Start MySQL temporarily for configuration updates
    log "Starting MySQL temporarily for configuration updates"
    mysqld --daemonize --skip-networking --socket=/tmp/mysql-devdocker.sock

    # Wait for MySQL to start
    for i in {1..30}; do
        if mysqladmin ping --socket=/tmp/mysql-devdocker.sock &>/dev/null; then
            break
        fi
        sleep 1
    done

    # Apply user/database configuration
    if [ -n "$MYSQL_USER" ] && [ -n "$MYSQL_PASSWORD" ]; then
        log "Ensuring user '$MYSQL_USER' exists with current password"
        mysql --socket=/tmp/mysql-devdocker.sock <<-EOSQL
            CREATE USER IF NOT EXISTS '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD';
            ALTER USER '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD';
EOSQL

        if [ -n "$MYSQL_DATABASE" ]; then
            log "Ensuring database '$MYSQL_DATABASE' exists"
            mysql --socket=/tmp/mysql-devdocker.sock <<-EOSQL
                CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\`;
                GRANT ALL PRIVILEGES ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_USER'@'%';
                FLUSH PRIVILEGES;
EOSQL
        fi
    fi

    # Stop temporary MySQL
    mysqladmin shutdown --socket=/tmp/mysql-devdocker.sock

    # Save current state
    {
        echo "MYSQL_USER=$MYSQL_USER"
        echo "MYSQL_DATABASE=$MYSQL_DATABASE"
        echo "DEVDOCKER_UID=$DEVDOCKER_UID"
        echo "DEVDOCKER_GID=$DEVDOCKER_GID"
    } > "$STATEFILE"
}

# Main entrypoint logic
main() {
    log "Durable Devdocker MySQL starting"

    # Update UID/GID first
    update_uid_gid

    # Apply configuration updates if not first run
    if [ -f "$STATEFILE" ]; then
        debug "Previous state found, applying configuration updates"
        apply_config
    else
        debug "First run, standard initialization will handle setup"
    fi

    # Call original MySQL entrypoint
    exec docker-entrypoint.sh "$@"
}

main "$@"
