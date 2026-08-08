#!/usr/bin/env bash

# ==============================================================================
# SproutAI Gateway - MySQL & Environment Auto-Installer
# ==============================================================================
# Description: Installs MySQL server, generates secure credentials, creates
#              default API keys & JSON schema, and updates .env.
# ==============================================================================

set -euo pipefail

# --- Color Formatting ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Check Root/Sudo Privileges ---
if [ "$EUID" -ne 0 ]; then
  log_error "Please run this script with sudo or as root: sudo ./install.sh"
fi

# --- File Paths ---
ENV_FILE=".env"
ENV_EXAMPLE=".env.example"

# Ensure .env exists or create it from .env.example
if [ ! -f "$ENV_FILE" ]; then
    if [ -f "$ENV_EXAMPLE" ]; then
        log_info "Creating .env from .env.example..."
        cp "$ENV_EXAMPLE" "$ENV_FILE"
    else
        log_error "Neither .env nor .env.example was found in this directory."
    fi
fi

# --- Helper Function: Generate Random Strings ---
generate_random_string() {
    local length=${1:-24}
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
}

# --- Step 1: Install MySQL Server ---
log_info "Checking MySQL installation..."

if ! command -v mysql &> /dev/null; then
    log_info "MySQL not found. Installing mysql-server..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y mysql-server
    systemctl enable mysql
    systemctl start mysql
else
    log_info "MySQL is already installed."
fi

# Ensure MySQL service is running
if ! systemctl is-active --quiet mysql; then
    log_info "Starting MySQL service..."
    systemctl start mysql
fi

# --- Step 2: Generate Credentials & API Keys ---
DB_NAME="sproutai_db"
DB_USER="sproutai_user"
DB_HOST="localhost"
DB_PORT="3306"
DB_PASSWORD=$(generate_random_string 32)
PEPPER_SECRET=$(generate_random_string 32)

# Generate a default Gateway API key with prefix
RANDOM_KEY_SUFFIX=$(generate_random_string 24)
DEFAULT_API_KEY="sproutai-dev-${RANDOM_KEY_SUFFIX}"

# Construct the API_KEYS_JSON payload matching your schema
API_KEYS_JSON_RAW=$(cat <<EOF
{"${DEFAULT_API_KEY}":{"team":"Technology","application":"POC","monthly_budget_usd":100,"allowed_models":["claude-sonnet-5","claude-sonnet-4.6","claude-sonnet-3.5","claude-haiku-4.5","gpt-4o","gpt-4o-mini","gpt-5.4","gpt-5.5"]}}
EOF
)

# Minify JSON string (remove newlines)
API_KEYS_JSON=$(echo "$API_KEYS_JSON_RAW" | tr -d '\n')

log_info "Generated database credentials, pepper, and default API key: ${DEFAULT_API_KEY}"

# --- Step 3: Configure Database & User in MySQL ---
log_info "Configuring MySQL database and privileges..."

mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
EOF

log_info "Database '${DB_NAME}' and user '${DB_USER}' configured successfully."

# --- Step 4: Update the .env File ---
log_info "Updating ${ENV_FILE} with MySQL and Gateway settings..."

# Helper function to set or replace a key in .env
set_env_var() {
    local key="$1"
    local value="$2"
    
    # Escape special characters for sed
    local escaped_value
    escaped_value=$(printf '%s\n' "$value" | sed -e 's/[\/&]/\\&/g')

    if grep -q "^${key}=" "$ENV_FILE"; then
        sed -i "s/^${key}=.*/${key}=${escaped_value}/" "$ENV_FILE"
    else
        echo "${key}=${escaped_value}" >> "$ENV_FILE"
    fi
}

# Write Database settings
set_env_var "MYSQL_HOST" "$DB_HOST"
set_env_var "MYSQL_PORT" "$DB_PORT"
set_env_var "MYSQL_DATABASE" "$DB_NAME"
set_env_var "MYSQL_USER" "$DB_USER"
set_env_var "MYSQL_PASSWORD" "$DB_PASSWORD"
set_env_var "API_KEY_HASH_PEPPER" "$PEPPER_SECRET"

# Write Gateway API Key settings
set_env_var "API_KEYS_JSON" "$API_KEYS_JSON"
set_env_var "VITE_GATEWAY_API_KEY" "$DEFAULT_API_KEY"
set_env_var "GATEWAY_UI_API_KEY" "$DEFAULT_API_KEY"

log_info ".env file successfully configured!"

# --- Step 5: Final Summary ---
echo ""
echo -e "${GREEN}======================================================================${NC}"
echo -e "${GREEN}      Installation & Gateway Key Generation Complete!                  ${NC}"
echo -e "${GREEN}======================================================================${NC}"
echo ""
echo "Configured Settings in .env:"
echo "  - MYSQL_DATABASE:       $DB_NAME"
echo "  - MYSQL_USER:           $DB_USER"
echo "  - DEFAULT API KEY:      $DEFAULT_API_KEY"
echo "  - VITE_GATEWAY_API_KEY: $DEFAULT_API_KEY"
echo "  - GATEWAY_UI_API_KEY:   $DEFAULT_API_KEY"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Open .env and add your provider API keys (OPENAI_API_KEY, ANTHROPIC_API_KEY, etc.):"
echo "   nano .env"
echo ""
echo "2. Start the gateway containers:"
echo "   docker compose up -d"
echo ""
