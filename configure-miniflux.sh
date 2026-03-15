#!/usr/bin/env bash
set -euo pipefail

# -----------------------
# Load environment variables from .env if it exists
# -----------------------
ENV_FILE="$(dirname "$0")/.env"
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
fi

# -----------------------
# Configuration (with defaults)
# -----------------------
DB_ROLE="${DB_ROLE:-miniflux}"
DB_NAME="${DB_NAME:-miniflux}"
LISTEN_ADDR="${LISTEN_ADDR:-127.0.0.1:8080}"
CONFIG_DIR="$HOME/.config/miniflux"
CONFIG_FILE="$CONFIG_DIR/config.env"
TEMPLATE_FILE="$(dirname "$0")/miniflux/config.env.example"

# -----------------------
# Ensure secrets are set (prompt if missing)
# -----------------------
prompt_if_empty() {
    local var_name="$1"
    local prompt_text="$2"
    local is_password="${3:-false}"

    if [[ -z "${!var_name:-}" ]]; then
        if [[ "$is_password" == "true" ]]; then
            read -rs -p "$prompt_text: " value
            echo "" >&2
        else
            read -r -p "$prompt_text: " value
        fi
        export "$var_name"="$value"
        # Save to .env for future runs (only if not already there)
        if ! grep -q "^$var_name=" "$ENV_FILE" 2>/dev/null; then
            echo "$var_name=\"$value\"" >> "$ENV_FILE"
        fi
    fi
}

mkdir -p "$CONFIG_DIR"
touch "$ENV_FILE"

prompt_if_empty "DB_PASS" "Enter Database Password (for role $DB_ROLE)" true
prompt_if_empty "ADMIN_USERNAME" "Enter Miniflux Admin Username"
prompt_if_empty "ADMIN_PASSWORD" "Enter Miniflux Admin Password" true

# Export for envsubst
export DB_ROLE DB_PASS DB_NAME LISTEN_ADDR ADMIN_USERNAME ADMIN_PASSWORD

# -----------------------
# Generate configuration file from template
# -----------------------
echo "Generating configuration file at $CONFIG_FILE..."
envsubst < "$TEMPLATE_FILE" > "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

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
    # sudo cp miniflux.service /etc/systemd/system/
    # sudo systemctl daemon-reload
    # sudo systemctl restart miniflux
else
    echo "Warning: No known service manager found (brew or systemctl). Starting manually in background..."
    nohup miniflux -c "$CONFIG_FILE" >/tmp/miniflux.log 2>&1 &
fi

echo "✅ Miniflux configuration complete. Service is running at http://$LISTEN_ADDR"
