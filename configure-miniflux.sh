#!/usr/bin/env bash
set -euo pipefail

# -----------------------
# Configuration
# -----------------------
DB_ROLE="miniflux"
DB_PASS="miniflux"
DB_NAME="miniflux"
ADMIN_USER=""
ADMIN_PASS=""   # change as needed
CONFIG_FILE="$HOME/.config/miniflux/config.env"
LISTEN_ADDR="127.0.0.1:8080"

# -----------------------
# Start PostgreSQL 18 via Homebrew
# -----------------------
echo "Starting PostgreSQL..."
brew services start postgresql@18

# Wait until Postgres is ready
until pg_isready-18 -h localhost -p 5432 -q; do
    echo "Waiting for PostgreSQL..."
    sleep 1
done

# -----------------------
# Ensure 'postgres' database exists
# -----------------------
createdb-18 -h localhost -p 5432 postgres 2>/dev/null || true

# -----------------------
# Create role if missing
# -----------------------
psql-18 -h localhost -p 5432 -d postgres -v ON_ERROR_STOP=1 <<EOSQL
DO
\$do\$
BEGIN
   IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$DB_ROLE') THEN
      CREATE ROLE $DB_ROLE WITH LOGIN PASSWORD '$DB_PASS';
   END IF;
END
\$do\$;
EOSQL

# -----------------------
# Create database if missing
# -----------------------
DB_EXISTS=$(psql-18 -h localhost -p 5432 -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME';")
if [[ "$DB_EXISTS" != "1" ]]; then
    createdb-18 -h localhost -p 5432 -O "$DB_ROLE" "$DB_NAME"
fi

# -----------------------
# Run migrations (idempotent)
# -----------------------
echo "Running database migrations..."
miniflux -c "$CONFIG_FILE" -migrate

# -----------------------
# Service configuration (Platform-agnostic approach)
# -----------------------
if command -v brew >/dev/null 2>&1; then
    echo "Configuring Homebrew service for Miniflux..."
    BREW_ETC=$(brew --prefix)/etc
    mkdir -p "$BREW_ETC"
    # Link our config to where brew services expects it
    ln -sf "$CONFIG_FILE" "$BREW_ETC/miniflux.conf"
    
    # Restart the service to apply changes (including admin creation)
    echo "Restarting Miniflux service..."
    brew services restart miniflux
elif command -v systemctl >/dev/null 2>&1; then
    echo "Configuring systemd service for Miniflux..."
    # Placeholder for systemd support if needed later
    # sudo cp miniflux.service /etc/systemd/system/
    # sudo systemctl daemon-reload
    # sudo systemctl restart miniflux
else
    echo "Warning: No known service manager found (brew or systemctl). Starting manually in background..."
    nohup miniflux -c "$CONFIG_FILE" >/tmp/miniflux.log 2>&1 &
fi

echo "✅ Miniflux configuration complete. Service is running at http://$LISTEN_ADDR"
